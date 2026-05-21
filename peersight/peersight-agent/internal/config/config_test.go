package config

import (
	"os"
	"testing"
)

func TestLoad_Defaults(t *testing.T) {
	// Clear env vars to test defaults
	os.Unsetenv("PEERSIGHT_API_URL")
	os.Unsetenv("PEERSIGHT_LOOP_INTERVAL")
	os.Unsetenv("PEERSIGHT_READ_ONLY")

	cfg := Load()

	if cfg.APIURL != "https://api.peersight.local:4000" {
		t.Errorf("expected default API URL, got %s", cfg.APIURL)
	}
	if cfg.LoopInterval != 30 {
		t.Errorf("expected default interval 30, got %d", cfg.LoopInterval)
	}
	if cfg.ReadOnly {
		t.Error("expected ReadOnly to be false by default")
	}
	if cfg.WgBinary != "wg" {
		t.Errorf("expected default wg binary, got %s", cfg.WgBinary)
	}
}

func TestLoad_EnvOverride(t *testing.T) {
	os.Setenv("PEERSIGHT_API_URL", "http://test:8080")
	os.Setenv("PEERSIGHT_HOST_ID", "test-host-123")
	os.Setenv("PEERSIGHT_LOOP_INTERVAL", "10")
	os.Setenv("PEERSIGHT_READ_ONLY", "true")
	defer func() {
		os.Unsetenv("PEERSIGHT_API_URL")
		os.Unsetenv("PEERSIGHT_HOST_ID")
		os.Unsetenv("PEERSIGHT_LOOP_INTERVAL")
		os.Unsetenv("PEERSIGHT_READ_ONLY")
	}()

	cfg := Load()

	if cfg.APIURL != "http://test:8080" {
		t.Errorf("expected http://test:8080, got %s", cfg.APIURL)
	}
	if cfg.HostID != "test-host-123" {
		t.Errorf("expected test-host-123, got %s", cfg.HostID)
	}
	if cfg.LoopInterval != 10 {
		t.Errorf("expected 10, got %d", cfg.LoopInterval)
	}
	if !cfg.ReadOnly {
		t.Error("expected ReadOnly to be true")
	}
}

func TestLoad_UnmanagedInterfaces(t *testing.T) {
	os.Setenv("PEERSIGHT_UNMANAGED_INTERFACES", "docker0,br-lan")
	defer os.Unsetenv("PEERSIGHT_UNMANAGED_INTERFACES")

	cfg := Load()
	if len(cfg.UnmanagedInterfaces) != 2 {
		t.Fatalf("expected 2 unmanaged interfaces, got %d", len(cfg.UnmanagedInterfaces))
	}
	if cfg.UnmanagedInterfaces[0] != "docker0" {
		t.Errorf("expected docker0, got %s", cfg.UnmanagedInterfaces[0])
	}
}

func TestValidate_MissingRequired(t *testing.T) {
	cfg := &Config{
		APIURL: "http://test",
		HostID: "",
		Token:  "",
	}

	if err := cfg.Validate(); err == nil {
		t.Error("expected error for missing HostID")
	}

	cfg.HostID = "host-1"
	if err := cfg.Validate(); err == nil {
		t.Error("expected error for missing Token")
	}

	cfg.Token = "token-1"
	if err := cfg.Validate(); err != nil {
		t.Errorf("unexpected error: %v", err)
	}
}
