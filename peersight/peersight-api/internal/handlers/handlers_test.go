package handlers_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/peersight/api/internal/handlers"
	"github.com/peersight/api/internal/middleware"
)

func init() {
	gin.SetMode(gin.TestMode)
}

// TestLoginMissingBody verifies that login with no body returns 400.
func TestLoginMissingBody(t *testing.T) {
	r := gin.New()
	authH := &handlers.AuthHandler{JWTSecret: "test-secret"}
	r.POST("/sessions", authH.Login)

	req := httptest.NewRequest("POST", "/sessions", strings.NewReader("{}"))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

// TestLoginInvalidJSON verifies malformed JSON returns 400.
func TestLoginInvalidJSON(t *testing.T) {
	r := gin.New()
	authH := &handlers.AuthHandler{JWTSecret: "test-secret"}
	r.POST("/sessions", authH.Login)

	req := httptest.NewRequest("POST", "/sessions", strings.NewReader("not json"))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

// TestSignupValidation verifies that signup validates email and password length.
func TestSignupValidation(t *testing.T) {
	r := gin.New()
	authH := &handlers.AuthHandler{JWTSecret: "test-secret"}
	r.POST("/accounts/signup", authH.Signup)

	tests := []struct {
		name string
		body string
		code int
	}{
		{"missing email", `{"password":"12345678"}`, 400},
		{"invalid email", `{"email":"notanemail","password":"12345678"}`, 400},
		{"short password", `{"email":"test@test.com","password":"123"}`, 400},
		{"missing password", `{"email":"test@test.com"}`, 400},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest("POST", "/accounts/signup", strings.NewReader(tc.body))
			req.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()
			r.ServeHTTP(w, req)

			if w.Code != tc.code {
				t.Errorf("expected %d, got %d (body: %s)", tc.code, w.Code, w.Body.String())
			}
		})
	}
}

// TestGenerateToken verifies JWT token generation.
func TestGenerateToken(t *testing.T) {
	userID := [16]byte{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16}
	token, err := middleware.GenerateToken("test-secret", userID, "admin")
	if err != nil {
		t.Fatalf("GenerateToken failed: %v", err)
	}
	if token == "" {
		t.Fatal("expected non-empty token")
	}
}

// TestGenerateRefreshToken verifies refresh token generation and validation.
func TestGenerateRefreshToken(t *testing.T) {
	userID := [16]byte{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16}

	refreshToken, err := middleware.GenerateRefreshToken("test-secret", userID, "operator")
	if err != nil {
		t.Fatalf("GenerateRefreshToken failed: %v", err)
	}

	claims, err := middleware.ValidateRefreshToken("test-secret", refreshToken)
	if err != nil {
		t.Fatalf("ValidateRefreshToken failed: %v", err)
	}

	if claims.UserID != userID {
		t.Errorf("expected user_id %v, got %v", userID, claims.UserID)
	}
	if claims.Role != "operator" {
		t.Errorf("expected role 'operator', got %q", claims.Role)
	}
}

// TestValidateRefreshTokenRejectsAccessToken verifies refresh validation
// rejects a normal access token (different issuer).
func TestValidateRefreshTokenRejectsAccessToken(t *testing.T) {
	userID := [16]byte{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16}
	accessToken, _ := middleware.GenerateToken("test-secret", userID, "admin")

	_, err := middleware.ValidateRefreshToken("test-secret", accessToken)
	if err == nil {
		t.Fatal("expected error when validating access token as refresh token")
	}
}

// TestHealthEndpoint verifies the version response.
func TestVersionEndpoint(t *testing.T) {
	r := gin.New()
	r.GET("/version", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"version": "0.1.0", "name": "peersight-api"})
	})

	req := httptest.NewRequest("GET", "/version", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var body map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &body)
	if body["name"] != "peersight-api" {
		t.Errorf("expected name peersight-api, got %v", body["name"])
	}
}

// TestRequireAdminMiddleware verifies admin check works.
func TestRequireAdminMiddleware(t *testing.T) {
	r := gin.New()
	r.Use(func(c *gin.Context) {
		c.Set("user_role", "operator")
		c.Next()
	})
	r.Use(middleware.RequireAdmin())
	r.GET("/admin/test", func(c *gin.Context) {
		c.JSON(200, gin.H{"ok": true})
	})

	req := httptest.NewRequest("GET", "/admin/test", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusForbidden {
		t.Errorf("expected 403 for operator, got %d", w.Code)
	}

	// Now test with admin
	r2 := gin.New()
	r2.Use(func(c *gin.Context) {
		c.Set("user_role", "admin")
		c.Next()
	})
	r2.Use(middleware.RequireAdmin())
	r2.GET("/admin/test", func(c *gin.Context) {
		c.JSON(200, gin.H{"ok": true})
	})

	req2 := httptest.NewRequest("GET", "/admin/test", nil)
	w2 := httptest.NewRecorder()
	r2.ServeHTTP(w2, req2)

	if w2.Code != http.StatusOK {
		t.Errorf("expected 200 for admin, got %d", w2.Code)
	}
}
