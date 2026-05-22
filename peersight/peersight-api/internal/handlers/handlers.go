package handlers

import (
	"fmt"
	"net"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/peersight/api/internal/middleware"
	"github.com/peersight/api/internal/models"
	"github.com/peersight/api/internal/repository"
	"golang.org/x/crypto/bcrypt"
)

// AuthHandler handles user authentication.
type AuthHandler struct {
	DB        *repository.DB
	JWTSecret string
}

// LoginRequest is the JSON body for POST /sessions.
type LoginRequest struct {
	Email    string `json:"email"    binding:"required"`
	Password string `json:"password" binding:"required"`
}

// Login authenticates a user and returns access + refresh JWT tokens.
func (h *AuthHandler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request body"})
		return
	}

	user, err := h.DB.GetUserByEmail(c.Request.Context(), req.Email)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
		return
	}

	accessToken, err := middleware.GenerateToken(h.JWTSecret, user.ID, user.Role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	refreshToken, err := middleware.GenerateRefreshToken(h.JWTSecret, user.ID, user.Role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate refresh token"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"token":         accessToken,
		"refresh_token": refreshToken,
		"user_id":       user.ID,
		"role":          user.Role,
	})
}

// RefreshRequest is the JSON body for POST /sessions/refresh.
type RefreshRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

// Refresh validates a refresh token and returns a new access + refresh token pair.
func (h *AuthHandler) Refresh(c *gin.Context) {
	var req RefreshRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request body"})
		return
	}

	claims, err := middleware.ValidateRefreshToken(h.JWTSecret, req.RefreshToken)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired refresh token"})
		return
	}

	// Verify the user still exists
	user, err := h.DB.GetUserByID(c.Request.Context(), claims.UserID)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not found"})
		return
	}

	accessToken, err := middleware.GenerateToken(h.JWTSecret, user.ID, user.Role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	refreshToken, err := middleware.GenerateRefreshToken(h.JWTSecret, user.ID, user.Role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate refresh token"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"token":         accessToken,
		"refresh_token": refreshToken,
		"user_id":       user.ID,
		"role":          user.Role,
	})
}

// SignupRequest is the JSON body for POST /accounts/signup.
// Role is intentionally omitted — all self-signups are "operator".
type SignupRequest struct {
	Email    string `json:"email"    binding:"required,email"`
	Password string `json:"password" binding:"required,min=8"`
}

// Signup creates a new user account with the "operator" role.
// Admin accounts can only be created by existing admins via CreateUser.
func (h *AuthHandler) Signup(c *gin.Context) {
	var req SignupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to hash password"})
		return
	}

	user := &models.User{
		Email:        req.Email,
		PasswordHash: string(hash),
		Role:         "operator",
	}

	if err := h.DB.CreateUser(c.Request.Context(), user); err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "user already exists"})
		return
	}

	accessToken, err := middleware.GenerateToken(h.JWTSecret, user.ID, user.Role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	refreshToken, err := middleware.GenerateRefreshToken(h.JWTSecret, user.ID, user.Role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate refresh token"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"token":         accessToken,
		"refresh_token": refreshToken,
		"user_id":       user.ID,
		"role":          user.Role,
	})
}

// IssueAgentToken generates a long-lived JWT (10 years) for a systemd agent daemon.
// This token is stored in /etc/peersight/agent.env and used by the agent to authenticate pings.
// Admin-only: requires "admin" role in the caller's JWT.
func (h *AuthHandler) IssueAgentToken(c *gin.Context) {
	userID, _ := c.Get("user_id")
	role, _ := c.Get("user_role")

	uid, ok := userID.(uuid.UUID)
	if !ok {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "invalid user context"})
		return
	}

	roleStr, _ := role.(string)
	agentToken, err := middleware.GenerateAgentToken(h.JWTSecret, uid, roleStr)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate agent token"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"agent_token": agentToken,
		"note":        "This token is valid for 10 years. Store it in PEERSIGHT_TOKEN in /etc/peersight/agent.env.",
	})
}



// CreateUserRequest is the JSON body for admin-only user creation.
type CreateUserRequest struct {
	Email    string `json:"email"    binding:"required,email"`
	Password string `json:"password" binding:"required,min=8"`
	Role     string `json:"role"     binding:"required"`
}

// CreateUser allows an admin to create a user with any role.
// This endpoint must be protected by RequireAdmin middleware.
func (h *AuthHandler) CreateUser(c *gin.Context) {
	var req CreateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate role
	role := strings.ToLower(req.Role)
	if role != "admin" && role != "operator" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "role must be 'admin' or 'operator'"})
		return
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to hash password"})
		return
	}

	user := &models.User{
		Email:        req.Email,
		PasswordHash: string(hash),
		Role:         role,
	}

	if err := h.DB.CreateUser(c.Request.Context(), user); err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "user already exists"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"user_id": user.ID,
		"email":   user.Email,
		"role":    user.Role,
	})
}

// ListUsers returns all users (admin only).
func (h *AuthHandler) ListUsers(c *gin.Context) {
	users, err := h.DB.ListUsers(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list users"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": users})
}

// DeleteUser removes a user (admin only).
func (h *AuthHandler) DeleteUser(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user id"})
		return
	}

	// Prevent deleting oneself
	currentUserID, exists := c.Get("user_id")
	if exists && currentUserID.(uuid.UUID) == id {
		c.JSON(http.StatusForbidden, gin.H{"error": "cannot delete your own account"})
		return
	}

	if err := h.DB.DeleteUser(c.Request.Context(), id); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found or already deleted"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "user deleted"})
}

// UpdateUserRole updates a user's role (admin only).
func (h *AuthHandler) UpdateUserRole(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user id"})
		return
	}

	var req struct {
		Role string `json:"role" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	role := strings.ToLower(req.Role)
	if role != "admin" && role != "operator" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "role must be 'admin' or 'operator'"})
		return
	}

	// Prevent demoting oneself
	currentUserID, exists := c.Get("user_id")
	if exists && currentUserID.(uuid.UUID) == id && role != "admin" {
		c.JSON(http.StatusForbidden, gin.H{"error": "cannot demote your own account"})
		return
	}

	if err := h.DB.UpdateUserRole(c.Request.Context(), id, role); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "user role updated"})
}

// ────────────────────────────────────────────────
// Host handlers
// ────────────────────────────────────────────────

// HostHandler handles host-related API endpoints.
type HostHandler struct {
	DB *repository.DB
}

// List returns all hosts for the org.
func (h *HostHandler) List(c *gin.Context) {
	orgID := getOrgID(c)
	hosts, err := h.DB.ListHosts(c.Request.Context(), orgID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": hosts})
}

// CreateHostRequest is the JSON body for creating a host.
type CreateHostRequest struct {
	Name string `json:"name" binding:"required"`
}

// Create creates a new host.
func (h *HostHandler) Create(c *gin.Context) {
	var req CreateHostRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	orgID := getOrgID(c)
	host := &models.Host{
		OrgID: orgID,
		Name:  req.Name,
	}

	if err := h.DB.CreateHost(c.Request.Context(), host); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"data": host})
}

// Show returns a single host by ID.
func (h *HostHandler) Show(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid host id"})
		return
	}
	host, err := h.DB.GetHost(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "host not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": host})
}

// Update renames a host.
func (h *HostHandler) Update(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid host id"})
		return
	}

	var req struct {
		Name string `json:"name" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	host, err := h.DB.UpdateHost(c.Request.Context(), id, req.Name)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "host not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": host})
}

// Delete removes a host and all its cascaded data.
func (h *HostHandler) Delete(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid host id"})
		return
	}
	if err := h.DB.DeleteHost(c.Request.Context(), id); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "host deleted"})
}


// ListInterfaces returns all interfaces for a host.
func (h *HostHandler) ListInterfaces(c *gin.Context) {
	hostID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid host id"})
		return
	}
	ifaces, err := h.DB.ListInterfaces(c.Request.Context(), hostID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": ifaces})
}

// ListEndpoints returns all endpoints for a host (across all interfaces).
func (h *HostHandler) ListEndpoints(c *gin.Context) {
	hostID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid host id"})
		return
	}
	endpoints, err := h.DB.ListEndpointsByHost(c.Request.Context(), hostID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": endpoints})
}

// ListChanges returns desired changes for a host.
func (h *HostHandler) ListChanges(c *gin.Context) {
	hostID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid host id"})
		return
	}
	changes, err := h.DB.ListAllChanges(c.Request.Context(), hostID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": changes})
}

// CreateChangeRequest is the JSON body for creating a desired change.
type CreateChangeRequest struct {
	Type    string `json:"type"    binding:"required"`
	Payload string `json:"payload" binding:"required"`
}

// CreateChange creates a new desired change for a host.
func (h *HostHandler) CreateChange(c *gin.Context) {
	hostID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid host id"})
		return
	}

	var req CreateChangeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate change type
	validTypes := map[string]bool{"add_peer": true, "remove_peer": true, "update_interface": true}
	if !validTypes[req.Type] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "type must be one of: add_peer, remove_peer, update_interface"})
		return
	}

	dc := &models.DesiredChange{
		HostID:  hostID,
		Type:    req.Type,
		Payload: req.Payload,
	}

	if err := h.DB.CreateDesiredChange(c.Request.Context(), dc); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"data": dc})
}

// ────────────────────────────────────────────────
// Peer handlers
// ────────────────────────────────────────────────

// PeerHandler handles peer-related API endpoints.
type PeerHandler struct {
	DB *repository.DB
}

// List returns all peers for the org.
func (h *PeerHandler) List(c *gin.Context) {
	orgID := getOrgID(c)
	peers, err := h.DB.ListPeers(c.Request.Context(), orgID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": peers})
}

// Delete removes a peer.
func (h *PeerHandler) Delete(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid peer id"})
		return
	}
	if err := h.DB.DeletePeer(c.Request.Context(), id); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "peer deleted"})
}

// ────────────────────────────────────────────────
// Alert handlers
// ────────────────────────────────────────────────

// AlertHandler handles alert-related API endpoints.
type AlertHandler struct {
	DB *repository.DB
}

// List returns alerts for the org.
func (h *AlertHandler) List(c *gin.Context) {
	orgID := getOrgID(c)
	alerts, err := h.DB.ListAlerts(c.Request.Context(), orgID, 100)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": alerts})
}

// Resolve marks an alert as resolved.
func (h *AlertHandler) Resolve(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid alert id"})
		return
	}
	if err := h.DB.ResolveAlert(c.Request.Context(), id); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "alert resolved"})
}

// ────────────────────────────────────────────────
// Queue handlers (for Broker)
// ────────────────────────────────────────────────

// QueueHandler handles broker queue polling.
type QueueHandler struct {
	DB *repository.DB
}

// PollNext returns the next batch of unacknowledged events from the queue.
// Events are NOT auto-acked; the broker must call AckEvents after processing.
func (h *QueueHandler) PollNext(c *gin.Context) {
	orgID := getOrgID(c)
	eventType := c.Param("type")

	var body struct {
		Max int `json:"max"`
	}
	if err := c.ShouldBindJSON(&body); err != nil || body.Max <= 0 {
		body.Max = 10
	}

	events, err := h.DB.PollQueue(c.Request.Context(), orgID, eventType, body.Max)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": events})
}

// AckEventsRequest is the JSON body for POST /queues/:type/ack.
type AckEventsRequest struct {
	EventIDs []string `json:"event_ids" binding:"required"`
}

// AckEvents marks specific queue events as acknowledged after the broker
// has successfully processed them. This prevents event loss on broker crashes.
func (h *QueueHandler) AckEvents(c *gin.Context) {
	var req AckEventsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var ids []uuid.UUID
	for _, idStr := range req.EventIDs {
		id, err := uuid.Parse(idStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid event_id: " + idStr})
			return
		}
		ids = append(ids, id)
	}

	if err := h.DB.AckQueueEvents(c.Request.Context(), ids); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "events acknowledged", "count": len(ids)})
}

// ────────────────────────────────────────────────
// Agent Ping handler
// ────────────────────────────────────────────────

// PingHandler handles heartbeats from agents.
type PingHandler struct {
	DB *repository.DB
}

// Ping processes a ping request from an agent.
func (h *PingHandler) Ping(c *gin.Context) {
	hostID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid host_id"})
		return
	}

	var req models.PingRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx := c.Request.Context()

	// 1. Record the ping
	if err := h.DB.RecordPing(ctx, hostID, req.AgentVersion); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to record ping"})
		return
	}

	// 2. Process executed changes
	for _, exec := range req.Executed {
		changeID, parseErr := uuid.Parse(exec.ChangeID)
		if parseErr != nil {
			continue
		}
		_ = h.DB.MarkChangeExecuted(ctx, changeID, exec.Success, exec.Output)
	}

	// 3. Get the host for org_id lookup
	host, err := h.DB.GetHost(ctx, hostID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "host not found"})
		return
	}

	// 4. Upsert interfaces and endpoints
	for _, iface := range req.Interfaces {
		if iface.PublicKey == "" {
			continue
		}

		peer, err := h.DB.FindOrCreatePeer(ctx, host.OrgID, iface.PublicKey, peerNameFromPublicKey(iface.PublicKey))
		if err != nil {
			continue
		}

		dbIface, err := h.DB.FindOrCreateInterface(ctx, &models.Interface{
			HostID:     hostID,
			PeerID:     peer.ID,
			Name:       iface.Name,
			ListenPort: iface.ListenPort,
			Fwmark:     iface.Fwmark,
			Up:         iface.Up,
			Address:    iface.Address,
			DNS:        iface.DNS,
			MTU:        iface.MTU,
		})
		if err != nil {
			continue
		}

		for _, p := range iface.Peers {
			if p.PublicKey == "" {
				continue
			}

			remotePeer, err := h.DB.FindOrCreatePeer(ctx, host.OrgID, p.PublicKey, peerNameFromPublicKey(p.PublicKey))
			if err != nil {
				continue
			}

			var lastHandshake *time.Time
			if p.LatestHandshake > 0 {
				t := time.Unix(p.LatestHandshake, 0).UTC()
				lastHandshake = &t
			}

			ep := &models.Endpoint{
				InterfaceID:   dbIface.ID,
				PeerID:        remotePeer.ID,
				IP:            extractIP(p.Endpoint),
				Port:          extractPort(p.Endpoint),
				AllowedIPs:    joinIPs(p.AllowedIPs),
				Keepalive:     p.PersistentKeepalive,
				Available:     p.Available,
				LastHandshake: lastHandshake,
				RxBytes:       p.TransferRx,
				TxBytes:       p.TransferTx,
			}
			_, _ = h.DB.UpsertEndpoint(ctx, ep)
		}
	}

	// 5. Return pending desired changes
	changes, err := h.DB.ListPendingChanges(ctx, hostID)
	if err != nil {
		changes = []models.DesiredChange{}
	}

	c.JSON(http.StatusOK, models.PingResponse{Data: changes})
}

// ────────────────────────────────────────────────
// Health endpoint
// ────────────────────────────────────────────────

// HealthHandler returns system health status.
type HealthHandler struct {
	DB        *repository.DB
	StartedAt time.Time
}

// Check returns the health status with uptime and DB stats (#17).
func (h *HealthHandler) Check(c *gin.Context) {
	err := h.DB.Pool.Ping(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"status": "unhealthy", "error": err.Error()})
		return
	}

	uptime := time.Since(h.StartedAt).Round(time.Second).String()
	dbStats := h.DB.Pool.Stat()

	c.JSON(http.StatusOK, gin.H{
		"status":  "healthy",
		"version": "0.1.0",
		"uptime":  uptime,
		"database": gin.H{
			"total_conns": dbStats.TotalConns(),
			"idle_conns":  dbStats.IdleConns(),
			"acquired":    dbStats.AcquiredConns(),
		},
	})
}

// ────────────────────────────────────────────────
// SSE Stream handler (#10)
// ────────────────────────────────────────────────

// SSEHandler provides Server-Sent Events for realtime notifications.
type SSEHandler struct {
	DB *repository.DB
}

// Stream opens an SSE connection and sends alert/ping events.
func (h *SSEHandler) Stream(c *gin.Context) {
	// Authenticate via query param (EventSource doesn't support headers)
	tokenStr := c.Query("token")
	if tokenStr == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "missing token"})
		return
	}

	c.Writer.Header().Set("Content-Type", "text/event-stream")
	c.Writer.Header().Set("Cache-Control", "no-cache")
	c.Writer.Header().Set("Connection", "keep-alive")
	c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
	c.Writer.Flush()

	ticker := time.NewTicker(15 * time.Second)
	defer ticker.Stop()

	ctx := c.Request.Context()

	// Send initial keepalive
	fmt.Fprintf(c.Writer, "event: connected\ndata: {\"status\":\"ok\"}\n\n")
	c.Writer.Flush()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			// Send keepalive ping
			fmt.Fprintf(c.Writer, "event: ping\ndata: {\"ts\":\"%s\"}\n\n", time.Now().Format(time.RFC3339))
			c.Writer.Flush()
		}
	}
}

// ────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────

// getOrgID extracts the org_id from the context (set by auth middleware or hardcoded for now).
func getOrgID(c *gin.Context) uuid.UUID {
	if id, exists := c.Get("org_id"); exists {
		return id.(uuid.UUID)
	}
	// Default org for single-tenant setup
	return uuid.MustParse("00000000-0000-0000-0000-000000000001")
}

func peerNameFromPublicKey(publicKey string) string {
	if len(publicKey) <= 8 {
		return "peer-" + publicKey
	}
	return "peer-" + publicKey[:8]
}

func extractIP(endpoint string) string {
	if endpoint == "" {
		return ""
	}
	host, _, err := net.SplitHostPort(endpoint)
	if err == nil {
		return strings.Trim(host, "[]")
	}
	if strings.HasPrefix(endpoint, "[") && strings.Contains(endpoint, "]") {
		return strings.Trim(endpoint, "[]")
	}
	return endpoint
}

func extractPort(endpoint string) int {
	_, port, err := net.SplitHostPort(endpoint)
	if err != nil {
		return 0
	}
	value, err := strconv.Atoi(port)
	if err != nil {
		return 0
	}
	return value
}

func joinIPs(ips []string) string {
	return strings.Join(ips, ",")
}
