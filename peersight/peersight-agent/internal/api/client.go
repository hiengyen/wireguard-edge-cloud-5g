// Package api provides the HTTP client for communicating with the peersight API.
package api

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/peersight/agent/internal/config"
)

const httpTimeout = 16 * time.Second

// Client talks to the peersight API server.
type Client struct {
	cfg  *config.Config
	http *http.Client
}

// Error describes a non-2xx API response.
type Error struct {
	StatusCode int
	Body       string
}

func (e *Error) Error() string {
	return fmt.Sprintf("API returned %d: %s", e.StatusCode, e.Body)
}

// IsAuthError reports whether the API rejected the agent token.
func IsAuthError(err error) bool {
	apiErr, ok := err.(*Error)
	return ok && (apiErr.StatusCode == http.StatusUnauthorized || apiErr.StatusCode == http.StatusForbidden)
}

// NewClient creates a new API client.
func NewClient(cfg *config.Config) *Client {
	return &Client{
		cfg:  cfg,
		http: &http.Client{Timeout: httpTimeout},
	}
}

// PingRequest is the body sent by the agent on each heartbeat.
type PingRequest struct {
	AgentVersion string          `json:"agent_version"`
	ReadOnly     bool            `json:"read_only"`
	Interfaces   json.RawMessage `json:"interfaces"`
	Executed     []ExecReport    `json:"executed,omitempty"`
}

// ExecReport reports the result of a previously issued desired change.
type ExecReport struct {
	ChangeID string `json:"change_id"`
	Success  bool   `json:"success"`
	Output   string `json:"output"`
}

// DesiredChange is a pending command returned from the API.
type DesiredChange struct {
	ID      string `json:"id"`
	Type    string `json:"type"`
	Payload string `json:"payload"`
	State   string `json:"state"`
}

// PingResponse is what the API returns after a ping.
type PingResponse struct {
	Data []DesiredChange `json:"data"`
}

// HealthResponse is the API health check response.
type HealthResponse struct {
	Status string `json:"status"`
}

// Ping sends a heartbeat to the API with current interface state.
func (c *Client) Ping(version string, interfaces json.RawMessage, executed []ExecReport) (*PingResponse, error) {
	body := PingRequest{
		AgentVersion: version,
		ReadOnly:     c.cfg.ReadOnly,
		Interfaces:   interfaces,
		Executed:     executed,
	}

	data, err := json.Marshal(body)
	if err != nil {
		return nil, fmt.Errorf("marshal ping body: %w", err)
	}

	url := fmt.Sprintf("%s/hosts/%s/ping/%s", c.cfg.APIURL, c.cfg.HostID, version)
	resp, err := c.doRequest("POST", url, data)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result PingResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decode ping response: %w", err)
	}
	return &result, nil
}

// CheckHealth calls the /health endpoint.
func (c *Client) CheckHealth() (*HealthResponse, error) {
	url := fmt.Sprintf("%s/health", c.cfg.APIURL)
	resp, err := c.doRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result HealthResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decode health response: %w", err)
	}
	return &result, nil
}

// doRequest sends an HTTP request with authentication.
func (c *Client) doRequest(method, url string, body []byte) (*http.Response, error) {
	var bodyReader io.Reader
	if body != nil {
		bodyReader = bytes.NewReader(body)
	}

	req, err := http.NewRequest(method, url, bodyReader)
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+c.cfg.Token)
	req.Header.Set("User-Agent", "peersight-agent/0.1.0")

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("send request to %s: %w", url, err)
	}

	if resp.StatusCode >= 400 {
		respBody, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		return nil, &Error{StatusCode: resp.StatusCode, Body: string(respBody)}
	}

	return resp, nil
}
