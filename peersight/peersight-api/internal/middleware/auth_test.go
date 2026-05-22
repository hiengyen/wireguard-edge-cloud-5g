package middleware

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/peersight/api/internal/models"
)

type fakeTokenStore struct {
	token *models.ServiceToken
}

func (s *fakeTokenStore) GetServiceTokenByHash(ctx context.Context, hash string) (*models.ServiceToken, error) {
	if s.token == nil || s.token.TokenHash != hash {
		return nil, jwt.ErrTokenUnverifiable
	}
	return s.token, nil
}

func (s *fakeTokenStore) TouchServiceToken(ctx context.Context, id uuid.UUID) error {
	now := time.Now().UTC()
	s.token.LastUsedAt = &now
	return nil
}

func TestGenerateToken(t *testing.T) {
	secret := "test-secret-key"
	userID := uuid.New()
	role := "admin"

	tokenStr, err := GenerateToken(secret, userID, role)
	if err != nil {
		t.Fatalf("GenerateToken failed: %v", err)
	}

	if tokenStr == "" {
		t.Fatal("token should not be empty")
	}

	// Parse and validate
	claims := &Claims{}
	token, err := jwt.ParseWithClaims(tokenStr, claims, func(t *jwt.Token) (interface{}, error) {
		return []byte(secret), nil
	})
	if err != nil {
		t.Fatalf("ParseWithClaims failed: %v", err)
	}
	if !token.Valid {
		t.Fatal("token should be valid")
	}
	if claims.UserID != userID {
		t.Errorf("expected user_id %s, got %s", userID, claims.UserID)
	}
	if claims.Role != role {
		t.Errorf("expected role %s, got %s", role, claims.Role)
	}
	if claims.Issuer != "peersight-api" {
		t.Errorf("expected issuer peersight-api, got %s", claims.Issuer)
	}
}

func TestGenerateToken_Expiry(t *testing.T) {
	secret := "test-secret"
	tokenStr, _ := GenerateToken(secret, uuid.New(), "operator")

	claims := &Claims{}
	_, _ = jwt.ParseWithClaims(tokenStr, claims, func(t *jwt.Token) (interface{}, error) {
		return []byte(secret), nil
	})

	// Access tokens should expire in ~30 minutes.
	expires := claims.ExpiresAt.Time
	diff := time.Until(expires)
	if diff < 29*time.Minute || diff > 31*time.Minute {
		t.Errorf("expected ~30m expiry, got %v", diff)
	}
}

func TestGenerateToken_WrongSecret(t *testing.T) {
	tokenStr, _ := GenerateToken("correct-secret", uuid.New(), "admin")

	claims := &Claims{}
	_, err := jwt.ParseWithClaims(tokenStr, claims, func(t *jwt.Token) (interface{}, error) {
		return []byte("wrong-secret"), nil
	})

	if err == nil {
		t.Fatal("should fail with wrong secret")
	}
}

func TestUserTokenCannotCallAgentRoute(t *testing.T) {
	gin.SetMode(gin.TestMode)
	secret := "test-secret"
	hostID := uuid.New()
	userToken, _ := GenerateToken(secret, uuid.New(), "admin")

	r := gin.New()
	r.Use(AgentAuthMiddleware(secret, &fakeTokenStore{}))
	r.POST("/hosts/:id/ping/:version", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})

	req := httptest.NewRequest("POST", "/hosts/"+hostID.String()+"/ping/0.1.0", nil)
	req.Header.Set("Authorization", "Bearer "+userToken)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

func TestAgentTokenHostMismatch(t *testing.T) {
	gin.SetMode(gin.TestMode)
	secret := "test-secret"
	tokenHostID := uuid.New()
	routeHostID := uuid.New()
	_, tokenString, err := GenerateServiceToken(secret, "agent", &tokenHostID, []string{"hosts:ping"}, time.Hour)
	if err != nil {
		t.Fatalf("GenerateServiceToken failed: %v", err)
	}
	store := &fakeTokenStore{token: &models.ServiceToken{
		ID:        uuid.New(),
		TokenHash: HashToken(tokenString),
		Kind:      "agent",
		HostID:    &tokenHostID,
		Scopes:    []string{"hosts:ping"},
		ExpiresAt: time.Now().Add(time.Hour),
	}}

	r := gin.New()
	r.Use(AgentAuthMiddleware(secret, store))
	r.POST("/hosts/:id/ping/:version", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})

	req := httptest.NewRequest("POST", "/hosts/"+routeHostID.String()+"/ping/0.1.0", nil)
	req.Header.Set("Authorization", "Bearer "+tokenString)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", w.Code)
	}
}

func TestRevokedAgentTokenRejected(t *testing.T) {
	gin.SetMode(gin.TestMode)
	secret := "test-secret"
	hostID := uuid.New()
	_, tokenString, err := GenerateServiceToken(secret, "agent", &hostID, []string{"hosts:ping"}, time.Hour)
	if err != nil {
		t.Fatalf("GenerateServiceToken failed: %v", err)
	}
	revokedAt := time.Now().UTC()
	store := &fakeTokenStore{token: &models.ServiceToken{
		ID:        uuid.New(),
		TokenHash: HashToken(tokenString),
		Kind:      "agent",
		HostID:    &hostID,
		Scopes:    []string{"hosts:ping"},
		ExpiresAt: time.Now().Add(time.Hour),
		RevokedAt: &revokedAt,
	}}

	r := gin.New()
	r.Use(AgentAuthMiddleware(secret, store))
	r.POST("/hosts/:id/ping/:version", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})

	req := httptest.NewRequest("POST", "/hosts/"+hostID.String()+"/ping/0.1.0", nil)
	req.Header.Set("Authorization", "Bearer "+tokenString)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

func TestBrokerTokenCannotCallUserRoute(t *testing.T) {
	gin.SetMode(gin.TestMode)
	secret := "test-secret"
	_, brokerToken, err := GenerateServiceToken(secret, "broker", nil, []string{"queues:poll"}, time.Hour)
	if err != nil {
		t.Fatalf("GenerateServiceToken failed: %v", err)
	}

	r := gin.New()
	r.Use(AuthMiddleware(secret))
	r.GET("/hosts", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})

	req := httptest.NewRequest("GET", "/hosts", nil)
	req.Header.Set("Authorization", "Bearer "+brokerToken)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}
