package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

// Config holds all broker configuration.
type Config struct {
	// API connection
	APIURL   string
	BrokerID string
	Token    string

	// Polling behavior
	LoopInterval int // seconds between polls

	// Pipe configurations
	Pipes []PipeConfig
}

// PipeConfig defines how events are forwarded.
type PipeConfig struct {
	Name     string   // pipe name (e.g. "alerts-file")
	To       string   // destination type: "file" | "syslog"
	From     []string // event types to subscribe: ["alerts", "changes"]
	Max      int      // max events per poll

	// File pipe settings
	FilePath string

	// Syslog pipe settings
	SyslogAddress  string // e.g. "localhost:514" or "/dev/log"
	SyslogFacility string // e.g. "local0"
	SyslogPriority string // e.g. "info"
	SyslogTag      string // e.g. "peersight"
}

// Load reads broker configuration from environment variables.
func Load() *Config {
	cfg := &Config{
		APIURL:       getEnv("PEERSIGHT_API_URL", "https://api.peersight.local:4000"),
		BrokerID:     getEnv("PEERSIGHT_BROKER_ID", ""),
		Token:        getEnv("PEERSIGHT_TOKEN", ""),
		LoopInterval: getEnvInt("PEERSIGHT_LOOP_INTERVAL", 30),
	}

	// Parse pipe configurations from environment
	// Format: PEERSIGHT_PIPE_<N>_TO, PEERSIGHT_PIPE_<N>_FROM, etc.
	for i := 1; i <= 10; i++ {
		prefix := fmt.Sprintf("PEERSIGHT_PIPE_%d_", i)
		to := getEnv(prefix+"TO", "")
		if to == "" {
			break
		}

		pipe := PipeConfig{
			Name:           getEnv(prefix+"NAME", fmt.Sprintf("pipe-%d", i)),
			To:             to,
			From:           strings.Split(getEnv(prefix+"FROM", "alerts"), ","),
			Max:            getEnvInt(prefix+"MAX", 100),
			FilePath:       getEnv(prefix+"FILE", ""),
			SyslogAddress:  getEnv(prefix+"SYSLOG_ADDRESS", "localhost:514"),
			SyslogFacility: getEnv(prefix+"SYSLOG_FACILITY", "local0"),
			SyslogPriority: getEnv(prefix+"SYSLOG_PRIORITY", "info"),
			SyslogTag:      getEnv(prefix+"SYSLOG_TAG", "peersight"),
		}
		cfg.Pipes = append(cfg.Pipes, pipe)
	}

	// Default pipe if none configured
	if len(cfg.Pipes) == 0 {
		cfg.Pipes = append(cfg.Pipes, PipeConfig{
			Name:     "default",
			To:       "file",
			From:     []string{"alerts"},
			Max:      100,
			FilePath: "/var/log/peersight/events.jsonl",
		})
	}

	return cfg
}

// Validate checks required fields.
func (c *Config) Validate() error {
	if c.APIURL == "" {
		return fmt.Errorf("PEERSIGHT_API_URL is required")
	}
	if c.BrokerID == "" {
		return fmt.Errorf("PEERSIGHT_BROKER_ID is required")
	}
	if c.Token == "" {
		return fmt.Errorf("PEERSIGHT_TOKEN is required")
	}
	return nil
}

func getEnv(key, defaultVal string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return defaultVal
}

func getEnvInt(key string, defaultVal int) int {
	if val := os.Getenv(key); val != "" {
		if i, err := strconv.Atoi(val); err == nil {
			return i
		}
	}
	return defaultVal
}
