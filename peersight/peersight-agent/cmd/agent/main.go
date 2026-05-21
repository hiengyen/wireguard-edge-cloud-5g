package main

import (
	"log"

	"github.com/peersight/agent/internal/agent"
	"github.com/peersight/agent/internal/config"
)

func main() {
	cfg := config.Load()

	if err := cfg.Validate(); err != nil {
		log.Fatalf("[agent] Configuration error: %v", err)
	}

	log.Println("[agent] peersight-agent starting...")
	agent.Run(cfg)
}
