// Package wg provides utilities for interacting with the WireGuard
// command-line tools and parsing their output.
package wg

import (
	"fmt"
	"os/exec"
	"strconv"
	"strings"
)

// InterfaceInfo holds parsed data for one WireGuard interface.
type InterfaceInfo struct {
	Name       string     `json:"name"`
	PrivateKey string     `json:"private_key,omitempty"`
	PublicKey  string     `json:"public_key"`
	ListenPort int        `json:"listen_port"`
	Fwmark     int        `json:"fwmark"`
	Up         bool       `json:"up"`
	Peers      []PeerInfo `json:"peers"`
}

// PeerInfo holds parsed data for one remote peer.
type PeerInfo struct {
	PublicKey           string   `json:"public_key"`
	PresharedKeyHash    string   `json:"preshared_key_hash,omitempty"`
	Endpoint            string   `json:"endpoint"`
	AllowedIPs          []string `json:"allowed_ips"`
	LatestHandshake     int64    `json:"latest_handshake"`
	TransferRx          int64    `json:"transfer_rx"`
	TransferTx          int64    `json:"transfer_tx"`
	PersistentKeepalive int      `json:"persistent_keepalive"`
	Available           bool     `json:"available"`
}

// RunWGShow executes `wg show all dump` and returns its raw stdout.
func RunWGShow(wgBinary string) (string, error) {
	cmd := exec.Command(wgBinary, "show", "all", "dump")
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("wg show all dump: %w", err)
	}
	return string(out), nil
}

// ParseWGShow parses the tab-separated output of `wg show all dump`
// into a map of interface name → InterfaceInfo.
func ParseWGShow(raw string) (map[string]*InterfaceInfo, error) {
	result := make(map[string]*InterfaceInfo)

	for _, line := range strings.Split(raw, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		fields := strings.Split(line, "\t")

		switch len(fields) {
		case 5:
			// Interface line: interface private public port fwmark
			iface := &InterfaceInfo{
				Name:       fields[0],
				PrivateKey: noneToEmpty(fields[1]),
				PublicKey:  noneToEmpty(fields[2]),
				ListenPort: parseInt(fields[3]),
				Fwmark:     parseFwmark(fields[4]),
				Up:         true,
				Peers:      []PeerInfo{},
			}
			result[fields[0]] = iface

		case 9:
			// Peer line: interface pubkey psk endpoint allowed-ips handshake rx tx keepalive
			ifaceName := fields[0]
			iface, ok := result[ifaceName]
			if !ok {
				return nil, fmt.Errorf("peer line references unknown interface %q", ifaceName)
			}

			allowedIPs := []string{}
			if fields[4] != "(none)" {
				allowedIPs = strings.Split(fields[4], ",")
			}

			peer := PeerInfo{
				PublicKey:           fields[1],
				PresharedKeyHash:    "", // hash computed separately if needed
				Endpoint:            noneToEmpty(fields[3]),
				AllowedIPs:          allowedIPs,
				LatestHandshake:     parseInt64(fields[5]),
				TransferRx:          parseInt64(fields[6]),
				TransferTx:          parseInt64(fields[7]),
				PersistentKeepalive: parseInt(fields[8]),
				Available:           parseInt64(fields[5]) > 0,
			}
			iface.Peers = append(iface.Peers, peer)

		default:
			// Skip unparseable lines
		}
	}

	return result, nil
}

// FilterInterfaces removes interfaces listed in unmanaged and optionally
// strips secrets.
func FilterInterfaces(ifaces map[string]*InterfaceInfo, unmanaged []string, redactSecrets bool) map[string]*InterfaceInfo {
	for _, name := range unmanaged {
		delete(ifaces, name)
	}
	if redactSecrets {
		for _, iface := range ifaces {
			iface.PrivateKey = ""
		}
	}
	return ifaces
}

// RunWGSet executes `wg set <args...>`.
func RunWGSet(wgBinary string, args ...string) error {
	cmdArgs := append([]string{"set"}, args...)
	cmd := exec.Command(wgBinary, cmdArgs...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("wg set %s: %s (%w)", strings.Join(args, " "), string(out), err)
	}
	return nil
}

// GetVersion returns the WireGuard version string.
func GetVersion(wgBinary string) string {
	cmd := exec.Command(wgBinary, "--version")
	out, err := cmd.Output()
	if err != nil {
		return "unknown"
	}
	parts := strings.Fields(string(out))
	for _, p := range parts {
		if strings.HasPrefix(p, "v") {
			return strings.TrimPrefix(p, "v")
		}
	}
	return strings.TrimSpace(string(out))
}

// ── helpers ──

func noneToEmpty(s string) string {
	if s == "(none)" || s == "off" {
		return ""
	}
	return s
}

func parseInt(s string) int {
	if s == "(none)" || s == "off" {
		return 0
	}
	// Handle hex fwmark like 0xca6c
	if strings.HasPrefix(s, "0x") {
		v, _ := strconv.ParseInt(s, 0, 64)
		return int(v)
	}
	v, _ := strconv.Atoi(s)
	return v
}

func parseInt64(s string) int64 {
	v, _ := strconv.ParseInt(s, 10, 64)
	return v
}

func parseFwmark(s string) int {
	if s == "off" || s == "(none)" {
		return 0
	}
	return parseInt(s)
}
