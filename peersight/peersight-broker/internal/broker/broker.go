// Package broker implements the main poll loop that continuously pulls events
// from the peersight API and pushes them to configured output pipes.
package broker

import (
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/peersight/broker/internal/api"
	"github.com/peersight/broker/internal/config"
	"github.com/peersight/broker/internal/pipe"
)

const version = "0.1.0"

// Run starts the broker's main loop.
func Run(cfg *config.Config) {
	client := api.NewClient(cfg)

	// Check connectivity
	if err := client.CheckHealth(); err != nil {
		log.Printf("[broker] Initial health check failed: %v (will retry)", err)
	} else {
		log.Println("[broker] API connectivity OK")
	}

	// Initialize pipes
	pipes := pipe.InitPipes(cfg.Pipes)
	if len(pipes) == 0 {
		log.Fatal("[broker] No pipes initialized, exiting")
	}
	defer func() {
		for _, p := range pipes {
			p.Close()
		}
	}()

	// Collect unique event types to poll
	eventTypes := collectEventTypes(cfg.Pipes)

	// Set up graceful shutdown
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)

	ticker := time.NewTicker(time.Duration(cfg.LoopInterval) * time.Second)
	defer ticker.Stop()

	log.Printf("[broker] Starting peersight-broker %s (interval=%ds, pipes=%d, types=%v)",
		version, cfg.LoopInterval, len(pipes), eventTypes)

	// Execute first poll immediately
	poll(client, pipes, eventTypes, cfg)

	for {
		select {
		case <-ticker.C:
			poll(client, pipes, eventTypes, cfg)

		case sig := <-stop:
			log.Printf("[broker] Received signal %v, shutting down", sig)
			return
		}
	}
}

// poll performs one full cycle: fetch events from API → distribute to pipes.
func poll(client *api.Client, pipes []*pipe.Pipe, eventTypes []string, cfg *config.Config) {
	// 1. Poll each event type from the API
	allEvents := make(map[string][]api.Event)
	for _, et := range eventTypes {
		maxForType := getMaxForType(cfg.Pipes, et)
		resp, err := client.PollQueue(et, maxForType)
		if err != nil {
			log.Printf("[broker] Poll %q failed: %v", et, err)
			continue
		}
		allEvents[et] = resp.Data
		if len(resp.Data) > 0 {
			log.Printf("[broker] Polled %d %s events", len(resp.Data), et)
		}
	}

	// 2. Distribute events to pipes based on their subscription
	for _, p := range pipes {
		var eventsForPipe []api.Event
		for _, from := range p.Config.From {
			if events, ok := allEvents[from]; ok {
				eventsForPipe = append(eventsForPipe, events...)
			}
		}

		if len(eventsForPipe) == 0 {
			continue
		}

		if err := p.Send(eventsForPipe); err != nil {
			log.Printf("[broker] Pipe %q send failed: %v", p.Config.Name, err)
		} else {
			log.Printf("[broker] Pipe %q: sent %d events", p.Config.Name, len(eventsForPipe))

			// Ack successfully delivered events
			var ackIDs []string
			for _, e := range eventsForPipe {
				ackIDs = append(ackIDs, e.ID)
			}
			for _, from := range p.Config.From {
				if err := client.AckEvents(from, ackIDs); err != nil {
					log.Printf("[broker] Failed to ack %d events for type %q: %v", len(ackIDs), from, err)
				}
			}
		}
	}
}

// TestPipe sends a test event to the named pipe.
func TestPipe(cfg *config.Config, pipeName string) {
	for _, pc := range cfg.Pipes {
		if pc.Name == pipeName {
			p, err := pipe.InitPipe(pc)
			if err != nil {
				log.Fatalf("[broker] Failed to init pipe %q: %v", pipeName, err)
			}
			defer p.Close()

			if err := p.SendTest(); err != nil {
				log.Fatalf("[broker] Test failed for pipe %q: %v", pipeName, err)
			}
			log.Printf("[broker] Test event sent to pipe %q successfully", pipeName)
			return
		}
	}
	log.Fatalf("[broker] Pipe %q not found in configuration", pipeName)
}

// collectEventTypes gathers unique event types across all pipes.
func collectEventTypes(pipes []config.PipeConfig) []string {
	seen := make(map[string]bool)
	var types []string
	for _, p := range pipes {
		for _, from := range p.From {
			if !seen[from] {
				seen[from] = true
				types = append(types, from)
			}
		}
	}
	return types
}

// getMaxForType returns the smallest max across all pipes subscribing to eventType.
func getMaxForType(pipes []config.PipeConfig, eventType string) int {
	max := 100
	for _, p := range pipes {
		for _, from := range p.From {
			if from == eventType && p.Max < max {
				max = p.Max
			}
		}
	}
	return max
}
