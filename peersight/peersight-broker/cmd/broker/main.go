package main

import (
	"flag"
	"log"

	"github.com/peersight/broker/internal/broker"
	"github.com/peersight/broker/internal/config"
)

func main() {
	testPipe := flag.String("test-pipe", "", "Send a test event to the named pipe and exit")
	flag.Parse()

	cfg := config.Load()

	if err := cfg.Validate(); err != nil {
		log.Fatalf("[broker] Configuration error: %v", err)
	}

	if *testPipe != "" {
		broker.TestPipe(cfg, *testPipe)
		return
	}

	log.Println("[broker] peersight-broker starting...")
	broker.Run(cfg)
}
