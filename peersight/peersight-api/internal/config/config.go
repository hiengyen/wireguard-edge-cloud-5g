package config

import (
	"log"
	"os"
	"strconv"
)

// Config holds all application configuration.
type Config struct {
	DatabaseURL    string
	JWTSecret      string
	Port           string
	Environment    string
	AllowedOrigins string
}

// Load reads environment variables and returns a Config.
func Load() *Config {
	cfg := &Config{
		DatabaseURL:    getEnv("DATABASE_URL", "postgres://peersight:peersight@localhost:5432/peersight?sslmode=disable"),
		JWTSecret:      getEnv("JWT_SECRET", "change-me-in-production"),
		Port:           getEnv("PORT", "4000"),
		Environment:    getEnv("ENV", "development"),
		AllowedOrigins: getEnv("ALLOWED_ORIGINS", "http://localhost:5173"),
	}

	if cfg.JWTSecret == "change-me-in-production" && cfg.Environment == "production" {
		log.Fatal("JWT_SECRET must be set in production")
	}

	return cfg
}

func getEnv(key, defaultVal string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return defaultVal
}

func getEnvInt(key string, defaultVal int) int {
	if val := os.Getenv(key); val != "" {
		i, err := strconv.Atoi(val)
		if err == nil {
			return i
		}
	}
	return defaultVal
}
