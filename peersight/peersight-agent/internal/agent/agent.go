// Package agent implements the main ping loop that continuously synchronizes
// the local WireGuard state with the peersight API server.
package agent

import (
	"encoding/json"
	"log"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/peersight/agent/internal/api"
	"github.com/peersight/agent/internal/config"
	"github.com/peersight/agent/internal/wg"
)

const version = "0.1.0"

// Run starts the agent's main loop.
func Run(cfg *config.Config) {
	client := api.NewClient(cfg)

	// Check connectivity first
	if !checkConnectivity(cfg, client) {
		log.Println("[agent] Initial connectivity check failed, will retry...")
	}

	// Set up graceful shutdown
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)

	ticker := time.NewTicker(time.Duration(cfg.LoopInterval) * time.Second)
	defer ticker.Stop()

	log.Printf("[agent] Starting peersight-agent %s (host=%s, interval=%ds)", version, cfg.HostID, cfg.LoopInterval)

	// Execute first ping immediately
	var pending []api.ExecReport
	var ok bool
	var failureCount int
	pending, ok = ping(cfg, client, pending)
	if ok {
		failureCount = 0
	} else {
		failureCount = 1
	}

	for {
		select {
		case <-ticker.C:
			pending, ok = ping(cfg, client, pending)
			if ok {
				failureCount = 0
				continue
			}
			failureCount++
			backoff := backoffDelay(cfg.LoopInterval, failureCount)
			log.Printf("[agent] backing off for %s after %d failed cycle(s)", backoff, failureCount)
			
			// Use select to wait for backoff or immediate stop signal
			select {
			case <-time.After(backoff):
				// Backoff elapsed, continue loop
			case sig := <-stop:
				log.Printf("[agent] Received signal %v during backoff, shutting down", sig)
				return
			}

		case sig := <-stop:
			log.Printf("[agent] Received signal %v, shutting down", sig)
			return
		}
	}
}

// ping performs one full cycle: interrogate WG → send to API → execute changes.
func ping(cfg *config.Config, client *api.Client, previousExecuted []api.ExecReport) ([]api.ExecReport, bool) {
	// 1. Interrogate local WireGuard state
	interfaces, err := interrogate(cfg)
	if err != nil {
		log.Printf("[agent] interrogate failed: %v", err)
		return nil, false
	}

	// 2. Marshal interfaces to JSON
	ifaceJSON, err := json.Marshal(interfacesToSlice(interfaces))
	if err != nil {
		log.Printf("[agent] marshal interfaces: %v", err)
		return nil, false
	}

	// 3. Send ping to API
	resp, err := client.Ping(version, ifaceJSON, previousExecuted)
	if err != nil {
		if api.IsAuthError(err) {
			log.Printf("[agent] authentication rejected; check PEERSIGHT_TOKEN and PEERSIGHT_HOST_ID: %v", err)
		}
		log.Printf("[agent] ping API failed: %v", err)
		return nil, false
	}

	// 4. Execute desired changes (if not read-only)
	if cfg.ReadOnly || len(resp.Data) == 0 {
		return nil, true
	}

	var executed []api.ExecReport
	for _, change := range resp.Data {
		result := executeChange(cfg, change)
		executed = append(executed, result)
	}

	if len(executed) > 0 {
		// Allow time for changes to propagate
		time.Sleep(2 * time.Second)
	}

	return executed, true
}

// interrogate reads the current WireGuard state from the OS.
func interrogate(cfg *config.Config) (map[string]*wg.InterfaceInfo, error) {
	raw, err := wg.RunWGShow(cfg.WgBinary)
	if err != nil {
		return nil, err
	}

	interfaces, err := wg.ParseWGShow(raw)
	if err != nil {
		return nil, err
	}

	interfaces = wg.FilterInterfaces(interfaces, cfg.UnmanagedInterfaces, cfg.RedactSecrets)
	return interfaces, nil
}

// executeChange applies a single desired change from the API.
func executeChange(cfg *config.Config, change api.DesiredChange) api.ExecReport {
	log.Printf("[agent] Executing change %s (type=%s)", change.ID, change.Type)

	var err error
	switch change.Type {
	case "add_peer":
		err = executeAddPeer(cfg, change.Payload)
	case "remove_peer":
		err = executeRemovePeer(cfg, change.Payload)
	case "update_interface":
		err = executeUpdateInterface(cfg, change.Payload)
	default:
		log.Printf("[agent] Unknown change type: %s", change.Type)
		return api.ExecReport{ChangeID: change.ID, Success: false, Output: "unknown change type"}
	}

	if err != nil {
		log.Printf("[agent] Change %s failed: %v", change.ID, err)
		return api.ExecReport{ChangeID: change.ID, Success: false, Output: err.Error()}
	}

	log.Printf("[agent] Change %s executed successfully", change.ID)
	return api.ExecReport{ChangeID: change.ID, Success: true, Output: "ok"}
}

// executeAddPeer adds a new peer to a WireGuard interface.
func executeAddPeer(cfg *config.Config, payload string) error {
	var p struct {
		Interface  string `json:"interface"`
		PublicKey  string `json:"public_key"`
		AllowedIPs string `json:"allowed_ips"`
		Endpoint   string `json:"endpoint"`
		Keepalive  int    `json:"keepalive"`
	}
	if err := json.Unmarshal([]byte(payload), &p); err != nil {
		return err
	}

	args := []string{p.Interface, "peer", p.PublicKey, "allowed-ips", p.AllowedIPs}
	if p.Endpoint != "" {
		args = append(args, "endpoint", p.Endpoint)
	}
	if p.Keepalive > 0 {
		args = append(args, "persistent-keepalive", intToStr(p.Keepalive))
	}

	return wg.RunWGSet(cfg.WgBinary, args...)
}

// executeRemovePeer removes a peer from a WireGuard interface.
func executeRemovePeer(cfg *config.Config, payload string) error {
	var p struct {
		Interface string `json:"interface"`
		PublicKey string `json:"public_key"`
	}
	if err := json.Unmarshal([]byte(payload), &p); err != nil {
		return err
	}
	return wg.RunWGSet(cfg.WgBinary, p.Interface, "peer", p.PublicKey, "remove")
}

// executeUpdateInterface updates an interface configuration.
func executeUpdateInterface(cfg *config.Config, payload string) error {
	var p struct {
		Interface  string `json:"interface"`
		ListenPort int    `json:"listen_port"`
	}
	if err := json.Unmarshal([]byte(payload), &p); err != nil {
		return err
	}
	if p.ListenPort > 0 {
		return wg.RunWGSet(cfg.WgBinary, p.Interface, "listen-port", intToStr(p.ListenPort))
	}
	return nil
}

// checkConnectivity verifies the agent can reach the API.
func checkConnectivity(cfg *config.Config, client *api.Client) bool {
	health, err := client.CheckHealth()
	if err != nil {
		log.Printf("[agent] Health check failed: %v", err)
		return false
	}
	if health.Status != "healthy" {
		log.Printf("[agent] API is unhealthy: %s", health.Status)
		return false
	}
	log.Println("[agent] API connectivity OK")
	return true
}

// interfacesToSlice converts the interface map to a slice for JSON serialization.
func interfacesToSlice(ifaces map[string]*wg.InterfaceInfo) []*wg.InterfaceInfo {
	result := make([]*wg.InterfaceInfo, 0, len(ifaces))
	for _, iface := range ifaces {
		result = append(result, iface)
	}
	return result
}

func intToStr(i int) string {
	return strconv.Itoa(i)
}

func backoffDelay(loopInterval int, failures int) time.Duration {
	if failures < 1 {
		failures = 1
	}
	seconds := loopInterval * (1 << min(failures-1, 4))
	if seconds < loopInterval {
		seconds = loopInterval
	}
	if seconds > 300 {
		seconds = 300
	}
	return time.Duration(seconds) * time.Second
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
