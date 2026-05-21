// Package pipe implements output destinations for broker events.
// Supported pipes: file (JSON Lines) and syslog.
package pipe

import (
	"encoding/json"
	"fmt"
	"log"
	"log/syslog"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/peersight/broker/internal/api"
	"github.com/peersight/broker/internal/config"
)

// Pipe represents an initialized output destination.
type Pipe struct {
	Config config.PipeConfig
	writer *syslog.Writer // only set for syslog pipes
}

// InitPipes initializes all configured pipes.
func InitPipes(pipes []config.PipeConfig) []*Pipe {
	result := make([]*Pipe, 0, len(pipes))
	for _, cfg := range pipes {
		p, err := InitPipe(cfg)
		if err != nil {
			log.Printf("[pipe] Failed to initialize pipe %q: %v", cfg.Name, err)
			continue
		}
		result = append(result, p)
	}
	return result
}

// InitPipe initializes a single pipe based on its config.
func InitPipe(cfg config.PipeConfig) (*Pipe, error) {
	p := &Pipe{Config: cfg}

	switch cfg.To {
	case "file":
		return initFilePipe(p)
	case "syslog":
		return initSyslogPipe(p)
	default:
		return nil, fmt.Errorf("unknown pipe type %q", cfg.To)
	}
}

func initFilePipe(p *Pipe) (*Pipe, error) {
	if p.Config.FilePath == "" {
		return nil, fmt.Errorf("pipe %q: file path is required", p.Config.Name)
	}

	// Ensure directory exists
	dir := filepath.Dir(p.Config.FilePath)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, fmt.Errorf("pipe %q: create directory %s: %w", p.Config.Name, dir, err)
	}

	// Test that we can open the file for writing
	f, err := os.OpenFile(p.Config.FilePath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return nil, fmt.Errorf("pipe %q: cannot write to %s: %w", p.Config.Name, p.Config.FilePath, err)
	}
	f.Close()

	log.Printf("[pipe] Initialized file pipe %q → %s", p.Config.Name, p.Config.FilePath)
	return p, nil
}

func initSyslogPipe(p *Pipe) (*Pipe, error) {
	addr := p.Config.SyslogAddress
	tag := p.Config.SyslogTag
	if tag == "" {
		tag = "peersight"
	}

	priority := parseSyslogPriority(p.Config.SyslogPriority, p.Config.SyslogFacility)

	var w *syslog.Writer
	var err error

	if strings.HasPrefix(addr, "/") {
		// Unix domain socket
		w, err = syslog.Dial("unixgram", addr, priority, tag)
	} else if addr != "" {
		w, err = syslog.Dial("udp", addr, priority, tag)
	} else {
		w, err = syslog.New(priority, tag)
	}

	if err != nil {
		return nil, fmt.Errorf("pipe %q: connect to syslog %s: %w", p.Config.Name, addr, err)
	}

	p.writer = w
	log.Printf("[pipe] Initialized syslog pipe %q → %s", p.Config.Name, addr)
	return p, nil
}

// Send forwards a batch of events to this pipe's destination.
func (p *Pipe) Send(events []api.Event) error {
	switch p.Config.To {
	case "file":
		return p.sendToFile(events)
	case "syslog":
		return p.sendToSyslog(events)
	default:
		return fmt.Errorf("unknown pipe type %q", p.Config.To)
	}
}

func (p *Pipe) sendToFile(events []api.Event) error {
	f, err := os.OpenFile(p.Config.FilePath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return fmt.Errorf("open file: %w", err)
	}
	defer f.Close()

	for _, e := range events {
		line, err := json.Marshal(e)
		if err != nil {
			log.Printf("[pipe] Marshal event %s: %v", e.ID, err)
			continue
		}
		fmt.Fprintln(f, string(line))
	}
	return nil
}

func (p *Pipe) sendToSyslog(events []api.Event) error {
	if p.writer == nil {
		return fmt.Errorf("syslog writer not initialized")
	}
	for _, e := range events {
		line, err := json.Marshal(e)
		if err != nil {
			log.Printf("[pipe] Marshal event %s: %v", e.ID, err)
			continue
		}
		if err := p.writer.Info(string(line)); err != nil {
			log.Printf("[pipe] Syslog write failed for %s: %v", e.ID, err)
		}
	}
	return nil
}

// SendTest sends a synthetic test event to validate the pipe.
func (p *Pipe) SendTest() error {
	testEvent := api.Event{
		ID:        "test-" + p.Config.Name,
		Type:      "test",
		Payload:   json.RawMessage(`{"message":"pipe test"}`),
		CreatedAt: time.Now().UTC().Format(time.RFC3339),
	}
	return p.Send([]api.Event{testEvent})
}

// Close releases resources held by the pipe.
func (p *Pipe) Close() {
	if p.writer != nil {
		p.writer.Close()
	}
}

// SubscribesTo checks if this pipe subscribes to the given event type.
func (p *Pipe) SubscribesTo(eventType string) bool {
	for _, from := range p.Config.From {
		if from == eventType {
			return true
		}
	}
	return false
}

func parseSyslogPriority(priority, facility string) syslog.Priority {
	var p syslog.Priority

	switch strings.ToLower(facility) {
	case "local0":
		p = syslog.LOG_LOCAL0
	case "local1":
		p = syslog.LOG_LOCAL1
	case "local2":
		p = syslog.LOG_LOCAL2
	case "local3":
		p = syslog.LOG_LOCAL3
	case "local4":
		p = syslog.LOG_LOCAL4
	case "local5":
		p = syslog.LOG_LOCAL5
	case "local6":
		p = syslog.LOG_LOCAL6
	case "local7":
		p = syslog.LOG_LOCAL7
	default:
		p = syslog.LOG_LOCAL0
	}

	switch strings.ToLower(priority) {
	case "emerg":
		p |= syslog.LOG_EMERG
	case "alert":
		p |= syslog.LOG_ALERT
	case "crit":
		p |= syslog.LOG_CRIT
	case "err", "error":
		p |= syslog.LOG_ERR
	case "warning", "warn":
		p |= syslog.LOG_WARNING
	case "notice":
		p |= syslog.LOG_NOTICE
	case "debug":
		p |= syslog.LOG_DEBUG
	default:
		p |= syslog.LOG_INFO
	}

	return p
}
