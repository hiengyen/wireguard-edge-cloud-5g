package config

import (
	"log"
	"os"
	"strconv"
)

// Config holds all application configuration.
type Config struct {
	DatabaseURL           string
	JWTSecret             string
	Port                  string
	Environment           string
	AllowedOrigins        string
	HostStaleSeconds      int
	HandshakeStaleSeconds int
	QueueBacklogThreshold int64
}

// Load reads environment variables and returns a Config.
func Load() *Config {
	cfg := &Config{
		DatabaseURL:           getEnv("DATABASE_URL", "postgres://peersight:peersight@localhost:5432/peersight?sslmode=disable"),
		JWTSecret:             getEnv("JWT_SECRET", "change-me-in-production"),
		Port:                  getEnv("PORT", "4000"),
		Environment:           getEnv("ENV", "development"),
		AllowedOrigins:        getEnv("ALLOWED_ORIGINS", "http://localhost:5173"),
		HostStaleSeconds:      getEnvInt("PEERSIGHT_HOST_STALE_SECONDS", 120),
		HandshakeStaleSeconds: getEnvInt("PEERSIGHT_HANDSHAKE_STALE_SECONDS", 180),
		QueueBacklogThreshold: int64(getEnvInt("PEERSIGHT_QUEUE_BACKLOG_ALERT_THRESHOLD", 1000)),
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
