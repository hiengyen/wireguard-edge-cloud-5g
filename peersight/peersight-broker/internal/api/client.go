// Package api provides the HTTP client for the broker to poll events from the API.
package api

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/peersight/broker/internal/config"
)

const httpTimeout = 16 * time.Second

// Client is the broker's API client.
type Client struct {
	cfg  *config.Config
	http *http.Client
}

// NewClient creates a new broker API client.
func NewClient(cfg *config.Config) *Client {
	return &Client{
		cfg:  cfg,
		http: &http.Client{Timeout: httpTimeout},
	}
}

// Event represents a single event returned from the queue.
type Event struct {
	ID          string          `json:"id"`
	Type        string          `json:"type"`
	Payload     json.RawMessage `json:"payload"`
	Attempts    int             `json:"attempts"`
	LockedUntil string          `json:"locked_until,omitempty"`
	CreatedAt   string          `json:"created_at"`
}

// PollResponse is the response from POST /queues/:type/next.
type PollResponse struct {
	Data []Event `json:"data"`
}

// PollQueue fetches the next batch of events for a given type.
func (c *Client) PollQueue(eventType string, max int) (*PollResponse, error) {
	body := struct {
		Max          int    `json:"max"`
		LeaseSeconds int    `json:"lease_seconds"`
		LockedBy     string `json:"locked_by"`
	}{Max: max, LeaseSeconds: c.cfg.LeaseSeconds, LockedBy: c.cfg.BrokerID}

	data, err := json.Marshal(body)
	if err != nil {
		return nil, fmt.Errorf("marshal poll body: %w", err)
	}

	url := fmt.Sprintf("%s/queues/%s/next", c.cfg.APIURL, eventType)
	resp, err := c.doRequest("POST", url, data)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result PollResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decode poll response: %w", err)
	}
	return &result, nil
}

// AckEvents acknowledges events that have been successfully processed.
func (c *Client) AckEvents(eventType string, eventIDs []string) error {
	body := struct {
		EventIDs []string `json:"event_ids"`
	}{EventIDs: eventIDs}

	data, err := json.Marshal(body)
	if err != nil {
		return fmt.Errorf("marshal ack body: %w", err)
	}

	url := fmt.Sprintf("%s/queues/%s/ack", c.cfg.APIURL, eventType)
	resp, err := c.doRequest("POST", url, data)
	if err != nil {
		return err
	}
	resp.Body.Close()
	return nil
}

// FailEvents releases leased events after delivery failed.
func (c *Client) FailEvents(eventType string, eventIDs []string, message string) error {
	body := struct {
		EventIDs []string `json:"event_ids"`
		Error    string   `json:"error"`
	}{EventIDs: eventIDs, Error: message}

	data, err := json.Marshal(body)
	if err != nil {
		return fmt.Errorf("marshal fail body: %w", err)
	}

	url := fmt.Sprintf("%s/queues/%s/fail", c.cfg.APIURL, eventType)
	resp, err := c.doRequest("POST", url, data)
	if err != nil {
		return err
	}
	resp.Body.Close()
	return nil
}

// CheckHealth verifies the API is reachable.
func (c *Client) CheckHealth() error {
	url := fmt.Sprintf("%s/health", c.cfg.APIURL)
	resp, err := c.doRequest("GET", url, nil)
	if err != nil {
		return err
	}
	resp.Body.Close()
	return nil
}

// Hello says hello to the API to validate broker credentials.
func (c *Client) Hello() error {
	url := fmt.Sprintf("%s/queues/0.1.0/hello", c.cfg.APIURL)
	resp, err := c.doRequest("GET", url, nil)
	if err != nil {
		return err
	}
	resp.Body.Close()
	return nil
}

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
	req.Header.Set("User-Agent", "peersight-broker/0.1.0")

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request to %s: %w", url, err)
	}

	if resp.StatusCode >= 400 {
		respBody, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		return nil, fmt.Errorf("API returned %d: %s", resp.StatusCode, string(respBody))
	}

	return resp, nil
}
