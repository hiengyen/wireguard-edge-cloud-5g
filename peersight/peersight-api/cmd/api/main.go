package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/peersight/api/internal/config"
	"github.com/peersight/api/internal/handlers"
	"github.com/peersight/api/internal/logger"
	"github.com/peersight/api/internal/middleware"
	"github.com/peersight/api/internal/migrate"
	"github.com/peersight/api/internal/repository"
)

func main() {
	cfg := config.Load()

	// Initialize structured logging (#14)
	logger.Setup(cfg.Environment)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	db, err := repository.NewDB(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("[api] Failed to connect to database: %v", err)
	}
	defer db.Close()

	// Auto-migrate database schema (#12)
	if err := migrate.Run(ctx, db.Pool); err != nil {
		log.Fatalf("[api] Failed to run migrations: %v", err)
	}

	if cfg.Environment == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	router := setupRouter(db, cfg)

	srv := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Graceful shutdown
	go func() {
		quit := make(chan os.Signal, 1)
		signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
		<-quit
		log.Println("[api] Shutting down server...")

		shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer shutdownCancel()

		if err := srv.Shutdown(shutdownCtx); err != nil {
			log.Fatalf("[api] Server forced to shutdown: %v", err)
		}
	}()

	log.Printf("[api] Starting peersight-api on :%s (env=%s)", cfg.Port, cfg.Environment)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("[api] Server error: %v", err)
	}
	log.Println("[api] Server stopped")
}

func setupRouter(db *repository.DB, cfg *config.Config) *gin.Engine {
	r := gin.New()
	r.Use(gin.Logger(), gin.Recovery())

	// CORS
	r.Use(func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", cfg.AllowedOrigins)
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Authorization, Content-Type")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	})

	// Init handlers
	startedAt := time.Now()
	authH := &handlers.AuthHandler{DB: db, JWTSecret: cfg.JWTSecret}
	healthH := &handlers.HealthHandler{DB: db, StartedAt: startedAt}
	pingH := &handlers.PingHandler{DB: db}
	hostH := &handlers.HostHandler{DB: db}
	peerH := &handlers.PeerHandler{DB: db}
	alertH := &handlers.AlertHandler{DB: db}
	queueH := &handlers.QueueHandler{DB: db}
	sseH := &handlers.SSEHandler{DB: db}

	// ── Public routes ──
	r.GET("/health", healthH.Check)
	r.GET("/version", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"version": "0.1.0", "name": "peersight-api"})
	})

	// ── Auth routes (public) ──
	r.POST("/sessions", authH.Login)
	r.POST("/sessions/refresh", authH.Refresh)
	r.POST("/accounts/signup", authH.Signup)

	// ── SSE stream (token via query param) ──
	r.GET("/events/stream", sseH.Stream)

	// ── Agent routes (agent auth) ──
	agent := r.Group("/")
	agent.Use(middleware.AgentAuthMiddleware(cfg.JWTSecret))
	{
		agent.POST("/hosts/:id/ping/:version", pingH.Ping)
	}

	// ── Authenticated routes (all roles) ──
	api := r.Group("/")
	api.Use(middleware.AuthMiddleware(cfg.JWTSecret))
	{
		// Hosts
		api.GET("/hosts", hostH.List)
		api.POST("/hosts", hostH.Create)
		api.GET("/hosts/:id", hostH.Show)
		api.GET("/hosts/:id/interfaces", hostH.ListInterfaces)
		api.GET("/hosts/:id/endpoints", hostH.ListEndpoints)
		api.GET("/hosts/:id/changes", hostH.ListChanges)

		// Peers (read)
		api.GET("/peers", peerH.List)

		// Alerts (read + resolve)
		api.GET("/alerts", alertH.List)
		api.POST("/alerts/:id/resolve", alertH.Resolve)

		// Queues (for broker)
		api.POST("/queues/:type/next", queueH.PollNext)
		api.POST("/queues/:type/ack", queueH.AckEvents)
	}

	// ── Admin-only routes (destructive operations) ──
	admin := r.Group("/")
	admin.Use(middleware.AuthMiddleware(cfg.JWTSecret))
	admin.Use(middleware.RequireAdmin())
	{
		// User management
		admin.GET("/admin/users", authH.ListUsers)
		admin.POST("/admin/users", authH.CreateUser)
		admin.DELETE("/admin/users/:id", authH.DeleteUser)
		admin.PUT("/admin/users/:id/role", authH.UpdateUserRole)

		// Destructive ops
		admin.DELETE("/peers/:id", peerH.Delete)
		admin.POST("/hosts/:id/changes", hostH.CreateChange)
	}

	return r
}
