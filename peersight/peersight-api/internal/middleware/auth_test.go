package middleware

import (
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

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

	// Token should expire in ~24 hours
	expires := claims.ExpiresAt.Time
	diff := time.Until(expires)
	if diff < 23*time.Hour || diff > 25*time.Hour {
		t.Errorf("expected ~24h expiry, got %v", diff)
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
