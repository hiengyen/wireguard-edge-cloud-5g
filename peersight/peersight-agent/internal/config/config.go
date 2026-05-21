package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

// Config holds all agent configuration.
type Config struct {
	// API connection
	APIURL  string
	HostID  string
	Token   string

	// Agent behavior
	LoopInterval    int    // seconds between pings
	ReadOnly        bool   // if true, agent reports but does not execute changes
	RedactSecrets   bool   // if true, private keys are stripped before sending
	WgBinary        string // path to wg binary
	ConfigDir       string // path to WireGuard config directory
	CredentialsFile string // path to credentials file

	// Unmanaged interfaces to skip
	UnmanagedInterfaces []string
}

// Load reads agent config from environment variables or config file.
func Load() *Config {
	cfg := &Config{
		APIURL:       getEnv("PEERSIGHT_API_URL", "https://api.peersight.local:4000"),
		HostID:       getEnv("PEERSIGHT_HOST_ID", ""),
		Token:        getEnv("PEERSIGHT_TOKEN", ""),
		LoopInterval: getEnvInt("PEERSIGHT_LOOP_INTERVAL", 30),
		ReadOnly:     getEnvBool("PEERSIGHT_READ_ONLY", false),
		RedactSecrets: getEnvBool("PEERSIGHT_REDACT_SECRETS", false),
		WgBinary:     getEnv("PEERSIGHT_WG_BINARY", "wg"),
		ConfigDir:    getEnv("PEERSIGHT_CONFIG_DIR", "/etc/wireguard"),
		CredentialsFile: getEnv("PEERSIGHT_CREDENTIALS_FILE", "/etc/peersight/credentials.conf"),
	}

	if unmanaged := getEnv("PEERSIGHT_UNMANAGED_INTERFACES", ""); unmanaged != "" {
		cfg.UnmanagedInterfaces = strings.Split(unmanaged, ",")
	}

	return cfg
}

// Validate checks that required fields are set.
func (c *Config) Validate() error {
	if c.APIURL == "" {
		return fmt.Errorf("PEERSIGHT_API_URL is required")
	}
	if c.HostID == "" {
		return fmt.Errorf("PEERSIGHT_HOST_ID is required")
	}
	if c.Token == "" {
		return fmt.Errorf("PEERSIGHT_TOKEN is required; run peersight-agent setup first")
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

func getEnvBool(key string, defaultVal bool) bool {
	if val := os.Getenv(key); val != "" {
		b, err := strconv.ParseBool(val)
		if err == nil {
			return b
		}
	}
	return defaultVal
}
