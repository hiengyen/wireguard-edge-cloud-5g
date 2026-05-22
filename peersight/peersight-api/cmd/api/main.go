package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/peersight/api/internal/config"
	"github.com/peersight/api/internal/handlers"
	"github.com/peersight/api/internal/logger"
	"github.com/peersight/api/internal/middleware"
	"github.com/peersight/api/internal/migrate"
	"github.com/peersight/api/internal/models"
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
	go runOperationalAlertLoop(db, cfg)

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

func runOperationalAlertLoop(db *repository.DB, cfg *config.Config) {
	ticker := time.NewTicker(60 * time.Second)
	defer ticker.Stop()

	for {
		runOperationalAlertCheck(db, cfg)
		<-ticker.C
	}
}

func runOperationalAlertCheck(db *repository.DB, cfg *config.Config) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	orgID := uuidDefaultOrg()
	staleHosts, err := db.ListStaleHosts(ctx, orgID, cfg.HostStaleSeconds, 100)
	if err == nil {
		for _, host := range staleHosts {
			hostID := host.ID
			createOpenAlertOnce(ctx, db, orgID, &hostID, "host_stale", "warning",
				fmt.Sprintf("Host %s has not pinged within %d seconds", host.Name, cfg.HostStaleSeconds))
		}
	}

	staleEndpoints, err := db.ListStaleEndpoints(ctx, orgID, cfg.HandshakeStaleSeconds, 100)
	if err == nil {
		for _, endpoint := range staleEndpoints {
			createOpenAlertOnce(ctx, db, orgID, endpoint.HostID, "endpoint_handshake_stale", "warning",
				fmt.Sprintf("Endpoint %s on host %s has a stale or unavailable WireGuard handshake", endpoint.IP, endpoint.HostName))
		}
	}

	backlog, err := db.QueueBacklog(ctx, orgID)
	if err == nil && cfg.QueueBacklogThreshold > 0 && backlog >= cfg.QueueBacklogThreshold {
		createOpenAlertOnce(ctx, db, orgID, nil, "broker_backlog_high", "warning",
			fmt.Sprintf("Broker queue backlog is %d events", backlog))
	}
}

func createOpenAlertOnce(ctx context.Context, db *repository.DB, orgID uuid.UUID, hostID *uuid.UUID, alertType string, level string, message string) {
	exists, err := db.OpenAlertExists(ctx, orgID, hostID, alertType)
	if err != nil || exists {
		return
	}
	_ = db.CreateAlert(ctx, &models.Alert{
		OrgID:    orgID,
		HostID:   hostID,
		Type:     alertType,
		Level:    level,
		Message:  message,
		Resolved: false,
	})
}

func uuidDefaultOrg() uuid.UUID {
	return uuid.MustParse("00000000-0000-0000-0000-000000000001")
}

func setupRouter(db *repository.DB, cfg *config.Config) *gin.Engine {
	r := gin.New()
	r.Use(gin.Logger(), gin.Recovery())

	// CORS
	r.Use(func(c *gin.Context) {
		origin := c.GetHeader("Origin")
		if isAllowedOrigin(origin, cfg.AllowedOrigins) {
			c.Header("Access-Control-Allow-Origin", origin)
			c.Header("Vary", "Origin")
		}
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
	sseH := &handlers.SSEHandler{DB: db, JWTSecret: cfg.JWTSecret}

	// ── Public routes ──
	r.GET("/health", healthH.Check)
	r.GET("/health/live", healthH.Live)
	r.GET("/health/ready", healthH.Ready)
	r.GET("/metrics", healthH.Metrics)
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
	agent.Use(middleware.AgentAuthMiddleware(cfg.JWTSecret, db))
	{
		agent.POST("/hosts/:id/ping/:version", pingH.Ping)
	}

	// ── Broker routes (broker service-token auth) ──
	broker := r.Group("/")
	broker.Use(middleware.BrokerAuthMiddleware(cfg.JWTSecret, db))
	{
		broker.POST("/queues/:type/next", queueH.PollNext)
		broker.POST("/queues/:type/ack", queueH.AckEvents)
		broker.POST("/queues/:type/fail", queueH.FailEvents)
	}

	// ── Authenticated routes (all roles) ──
	api := r.Group("/")
	api.Use(middleware.AuthMiddleware(cfg.JWTSecret))
	{
		// Hosts
		api.GET("/hosts", hostH.List)
		api.POST("/hosts", hostH.Create)
		api.GET("/hosts/:id", hostH.Show)
		api.PUT("/hosts/:id", hostH.Update)
		api.GET("/hosts/:id/interfaces", hostH.ListInterfaces)
		api.GET("/hosts/:id/endpoints", hostH.ListEndpoints)
		api.GET("/hosts/:id/changes", hostH.ListChanges)

		// Self-Service User Profile / Change Password
		api.POST("/profile/change-password", authH.ChangePassword)

		// Peers (read)
		api.GET("/peers", peerH.List)
		api.GET("/peers/:id", peerH.Show)
		api.GET("/peers/:id/endpoints", peerH.ListEndpoints)

		// Alerts (read + resolve)
		api.GET("/alerts", alertH.List)
		api.POST("/alerts/:id/resolve", alertH.Resolve)
		api.POST("/alerts/resolve-bulk", alertH.ResolveBulk)

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

		// Issue long-lived agent token (for use in PEERSIGHT_TOKEN env var)
		admin.POST("/admin/agent-tokens", authH.IssueAgentToken)
		admin.POST("/hosts/:id/agent-tokens", authH.IssueHostAgentToken)
		admin.POST("/admin/broker-tokens", authH.IssueBrokerToken)
		admin.GET("/admin/service-tokens", authH.ListServiceTokens)
		admin.POST("/admin/service-tokens/:id/revoke", authH.RevokeServiceToken)

		// Global change log audit
		admin.GET("/admin/changes", hostH.ListGlobalChanges)

		// Destructive ops
		admin.DELETE("/peers/:id", peerH.Delete)
		admin.DELETE("/hosts/:id", hostH.Delete)
		admin.POST("/hosts/:id/changes", hostH.CreateChange)
	}

	return r
}

func isAllowedOrigin(origin string, allowedOrigins string) bool {
	if origin == "" {
		return false
	}
	for _, allowed := range strings.Split(allowedOrigins, ",") {
		allowed = strings.TrimSpace(allowed)
		if allowed == "*" || allowed == origin {
			return true
		}
	}
	return false
}
