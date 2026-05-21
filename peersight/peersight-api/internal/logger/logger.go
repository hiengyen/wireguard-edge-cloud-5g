// Package logger provides structured logging for PeerSight API.
// Uses Go's log/slog for JSON output in production and text output in development.
package logger

import (
	"log/slog"
	"os"
)

// Setup initializes the global slog logger based on the environment.
func Setup(env string) {
	var handler slog.Handler

	if env == "production" {
		// JSON output for production (structured, machine-parseable)
		handler = slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
			Level: slog.LevelInfo,
		})
	} else {
		// Text output for development (human-readable)
		handler = slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{
			Level: slog.LevelDebug,
		})
	}

	slog.SetDefault(slog.New(handler))
}
