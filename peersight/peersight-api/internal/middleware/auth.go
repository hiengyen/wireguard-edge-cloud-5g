package middleware

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/peersight/api/internal/models"
)

const (
	IssuerUser    = "peersight-api"
	IssuerRefresh = "peersight-api-refresh"
	IssuerService = "peersight-service"
)

var (
	ErrTokenRevoked = errors.New("token_revoked")
	ErrTokenExpired = errors.New("token_expired")
)

// Claims holds JWT token claims.
type Claims struct {
	UserID uuid.UUID  `json:"user_id,omitempty"`
	Role   string     `json:"role,omitempty"`
	Kind   string     `json:"kind,omitempty"`
	HostID *uuid.UUID `json:"host_id,omitempty"`
	Scopes []string   `json:"scopes,omitempty"`
	jwt.RegisteredClaims
}

// ServiceTokenStore is the minimal repository interface required to validate daemon tokens.
type ServiceTokenStore interface {
	GetServiceTokenByHash(ctx context.Context, hash string) (*models.ServiceToken, error)
	TouchServiceToken(ctx context.Context, id uuid.UUID) error
}

// GenerateToken creates a new short-lived access JWT token (30 minutes).
func GenerateToken(secret string, userID uuid.UUID, role string) (string, error) {
	claims := Claims{
		UserID: userID,
		Role:   role,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(30 * time.Minute)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Issuer:    IssuerUser,
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(secret))
}

// GenerateAgentToken creates a long-lived JWT token (10 years) for systemd agent daemons.
// This token does not expire quickly so it can be stored in /etc/peersight/agent.env.
func GenerateAgentToken(secret string, userID uuid.UUID, role string) (string, error) {
	claims := Claims{
		UserID: userID,
		Role:   role,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(10 * 365 * 24 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Issuer:    IssuerUser,
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(secret))
}

// GenerateRefreshToken creates a long-lived refresh JWT token (7 days).
func GenerateRefreshToken(secret string, userID uuid.UUID, role string) (string, error) {
	claims := Claims{
		UserID: userID,
		Role:   role,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(7 * 24 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Issuer:    IssuerRefresh,
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(secret))
}

// ValidateRefreshToken parses and validates a refresh token.
func ValidateRefreshToken(secret string, tokenString string) (*Claims, error) {
	claims := &Claims{}
	token, err := jwt.ParseWithClaims(tokenString, claims, func(t *jwt.Token) (interface{}, error) {
		return []byte(secret), nil
	})
	if err != nil || !token.Valid {
		return nil, err
	}
	if claims.Issuer != IssuerRefresh {
		return nil, jwt.ErrTokenInvalidIssuer
	}
	return claims, nil
}

// GenerateServiceToken creates a scoped daemon token. Persist HashToken(token) before returning it.
func GenerateServiceToken(secret string, kind string, hostID *uuid.UUID, scopes []string, ttl time.Duration) (uuid.UUID, string, error) {
	tokenID := uuid.New()
	claims := Claims{
		Kind:   kind,
		HostID: hostID,
		Scopes: scopes,
		RegisteredClaims: jwt.RegisteredClaims{
			ID:        tokenID.String(),
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(ttl)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Issuer:    IssuerService,
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString([]byte(secret))
	return tokenID, tokenString, err
}

// HashToken returns the SHA-256 hash persisted for service-token lookup.
func HashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

// TokenPrefix returns a short non-secret prefix for display/audit.
func TokenPrefix(token string) string {
	if len(token) <= 12 {
		return token
	}
	return token[:12]
}

// AuthMiddleware validates the Bearer token in the Authorization header.
func AuthMiddleware(secret string) gin.HandlerFunc {
	return func(c *gin.Context) {
		claims, err := validateUserBearer(c.GetHeader("Authorization"), secret)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired token"})
			return
		}

		c.Set("user_id", claims.UserID)
		c.Set("user_role", claims.Role)
		c.Next()
	}
}

// AgentAuthMiddleware validates scoped agent tokens and binds them to the requested host.
func AgentAuthMiddleware(secret string, store ServiceTokenStore) gin.HandlerFunc {
	return func(c *gin.Context) {
		claims, record, err := validateServiceBearer(c.Request.Context(), c.GetHeader("Authorization"), secret, store, "agent", "hosts:ping")
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
			return
		}

		hostID, parseErr := uuid.Parse(c.Param("id"))
		if parseErr != nil {
			c.AbortWithStatusJSON(http.StatusBadRequest, gin.H{"error": "invalid host id"})
			return
		}
		if record.HostID != nil && *record.HostID != hostID {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "token_host_mismatch"})
			return
		}
		if claims.HostID != nil && *claims.HostID != hostID {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "token_host_mismatch"})
			return
		}

		c.Set("service_token_id", record.ID)
		c.Set("service_kind", record.Kind)
		c.Set("host_id", hostID)
		c.Next()
	}
}

// BrokerAuthMiddleware validates scoped broker tokens.
func BrokerAuthMiddleware(secret string, store ServiceTokenStore) gin.HandlerFunc {
	return func(c *gin.Context) {
		_, record, err := validateServiceBearer(c.Request.Context(), c.GetHeader("Authorization"), secret, store, "broker", "queues:poll")
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
			return
		}

		c.Set("service_token_id", record.ID)
		c.Set("service_kind", record.Kind)
		c.Next()
	}
}

// RequireAdmin checks that the authenticated user has the admin role.
func RequireAdmin() gin.HandlerFunc {
	return func(c *gin.Context) {
		role, exists := c.Get("user_role")
		if !exists || role != "admin" {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "admin access required"})
			return
		}
		c.Next()
	}
}

// ValidateUserQueryToken validates a user token passed via query string for EventSource.
func ValidateUserQueryToken(tokenString string, secret string) (*Claims, error) {
	return validateUserToken(tokenString, secret)
}

func validateUserBearer(authHeader string, secret string) (*Claims, error) {
	tokenString, err := bearerToken(authHeader)
	if err != nil {
		return nil, err
	}
	return validateUserToken(tokenString, secret)
}

func validateUserToken(tokenString string, secret string) (*Claims, error) {
	claims := &Claims{}
	token, err := jwt.ParseWithClaims(tokenString, claims, func(t *jwt.Token) (interface{}, error) {
		return []byte(secret), nil
	})
	if err != nil || !token.Valid {
		return nil, jwt.ErrTokenUnverifiable
	}
	if claims.Issuer != IssuerUser {
		return nil, jwt.ErrTokenInvalidIssuer
	}
	return claims, nil
}

func validateServiceBearer(ctx context.Context, authHeader string, secret string, store ServiceTokenStore, kind string, scope string) (*Claims, *models.ServiceToken, error) {
	tokenString, err := bearerToken(authHeader)
	if err != nil {
		return nil, nil, err
	}

	claims := &Claims{}
	token, err := jwt.ParseWithClaims(tokenString, claims, func(t *jwt.Token) (interface{}, error) {
		return []byte(secret), nil
	})
	if err != nil || !token.Valid {
		return nil, nil, jwt.ErrTokenUnverifiable
	}
	if claims.Issuer != IssuerService || claims.Kind != kind {
		return nil, nil, jwt.ErrTokenInvalidIssuer
	}
	if !hasScope(claims.Scopes, scope) {
		return nil, nil, jwt.ErrTokenInvalidClaims
	}

	record, err := store.GetServiceTokenByHash(ctx, HashToken(tokenString))
	if err != nil {
		return nil, nil, jwt.ErrTokenUnverifiable
	}
	now := time.Now()
	if record.RevokedAt != nil {
		return nil, nil, ErrTokenRevoked
	}
	if now.After(record.ExpiresAt) {
		return nil, nil, ErrTokenExpired
	}
	if record.Kind != kind || !hasScope(record.Scopes, scope) {
		return nil, nil, jwt.ErrTokenInvalidClaims
	}
	_ = store.TouchServiceToken(ctx, record.ID)

	return claims, record, nil
}

func bearerToken(authHeader string) (string, error) {
	if authHeader == "" {
		return "", jwt.ErrTokenRequiredClaimMissing
	}
	parts := strings.SplitN(authHeader, " ", 2)
	if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
		return "", jwt.ErrTokenMalformed
	}
	return parts[1], nil
}

func hasScope(scopes []string, wanted string) bool {
	for _, scope := range scopes {
		if scope == wanted || scope == "*" {
			return true
		}
	}
	return false
}
