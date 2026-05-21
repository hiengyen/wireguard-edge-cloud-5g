// Package migrate provides automatic database migration on API startup.
// Migrations are embedded and run in order during initialization.
package migrate

import (
	"context"
	"embed"
	"log"
	"sort"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

//go:embed *.sql
var migrationFiles embed.FS

// Run executes all pending migrations in order.
// It creates a schema_migrations table to track which migrations have been applied.
func Run(ctx context.Context, pool *pgxpool.Pool) error {
	// Create migrations tracking table
	_, err := pool.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS schema_migrations (
			version TEXT PRIMARY KEY,
			applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
		)
	`)
	if err != nil {
		return err
	}

	// Read all migration files
	entries, err := migrationFiles.ReadDir(".")
	if err != nil {
		return err
	}

	var filenames []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".sql") {
			filenames = append(filenames, e.Name())
		}
	}
	sort.Strings(filenames)

	// Apply each migration if not already applied
	for _, fname := range filenames {
		version := strings.TrimSuffix(fname, ".sql")

		var exists bool
		err := pool.QueryRow(ctx,
			`SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE version = $1)`, version).Scan(&exists)
		if err != nil {
			return err
		}

		if exists {
			continue
		}

		content, err := migrationFiles.ReadFile(fname)
		if err != nil {
			return err
		}

		log.Printf("[migrate] Applying migration: %s", version)
		_, err = pool.Exec(ctx, string(content))
		if err != nil {
			log.Printf("[migrate] FAILED migration %s: %v", version, err)
			return err
		}

		_, err = pool.Exec(ctx,
			`INSERT INTO schema_migrations (version) VALUES ($1)`, version)
		if err != nil {
			return err
		}

		log.Printf("[migrate] Applied migration: %s", version)
	}

	return nil
}
