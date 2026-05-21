package wg

import (
	"testing"
)

func TestParseWGShow_SingleInterface(t *testing.T) {
	raw := "wg0\tprivate_key_here\tpublic_key_here\t51820\toff\n"

	result, err := ParseWGShow(raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	iface, ok := result["wg0"]
	if !ok {
		t.Fatal("expected wg0 interface")
	}

	if iface.PublicKey != "public_key_here" {
		t.Errorf("expected public_key_here, got %s", iface.PublicKey)
	}
	if iface.ListenPort != 51820 {
		t.Errorf("expected listen port 51820, got %d", iface.ListenPort)
	}
	if iface.Fwmark != 0 {
		t.Errorf("expected fwmark 0, got %d", iface.Fwmark)
	}
	if !iface.Up {
		t.Error("expected interface to be up")
	}
}

func TestParseWGShow_WithPeers(t *testing.T) {
	raw := `wg0	priv_key	pub_key	51820	off
wg0	peer_pub_key	(none)	1.2.3.4:51820	10.0.0.2/32	1714800000	12345	67890	25`

	result, err := ParseWGShow(raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	iface := result["wg0"]
	if len(iface.Peers) != 1 {
		t.Fatalf("expected 1 peer, got %d", len(iface.Peers))
	}

	peer := iface.Peers[0]
	if peer.PublicKey != "peer_pub_key" {
		t.Errorf("expected peer_pub_key, got %s", peer.PublicKey)
	}
	if peer.Endpoint != "1.2.3.4:51820" {
		t.Errorf("expected 1.2.3.4:51820, got %s", peer.Endpoint)
	}
	if len(peer.AllowedIPs) != 1 || peer.AllowedIPs[0] != "10.0.0.2/32" {
		t.Errorf("unexpected allowed IPs: %v", peer.AllowedIPs)
	}
	if peer.TransferRx != 12345 {
		t.Errorf("expected rx 12345, got %d", peer.TransferRx)
	}
	if peer.TransferTx != 67890 {
		t.Errorf("expected tx 67890, got %d", peer.TransferTx)
	}
	if peer.PersistentKeepalive != 25 {
		t.Errorf("expected keepalive 25, got %d", peer.PersistentKeepalive)
	}
	if !peer.Available {
		t.Error("expected peer to be available (handshake > 0)")
	}
}

func TestParseWGShow_MultipleInterfaces(t *testing.T) {
	raw := `wg0	priv1	pub1	51820	off
wg1	priv2	pub2	51821	0xca6c`

	result, err := ParseWGShow(raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(result) != 2 {
		t.Fatalf("expected 2 interfaces, got %d", len(result))
	}

	if result["wg0"].ListenPort != 51820 {
		t.Errorf("wg0 port: expected 51820, got %d", result["wg0"].ListenPort)
	}
	if result["wg1"].ListenPort != 51821 {
		t.Errorf("wg1 port: expected 51821, got %d", result["wg1"].ListenPort)
	}
	if result["wg1"].Fwmark != 0xca6c {
		t.Errorf("wg1 fwmark: expected 0xca6c, got %d", result["wg1"].Fwmark)
	}
}

func TestParseWGShow_EmptyOutput(t *testing.T) {
	result, err := ParseWGShow("")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result) != 0 {
		t.Errorf("expected 0 interfaces, got %d", len(result))
	}
}

func TestFilterInterfaces_RemoveUnmanaged(t *testing.T) {
	ifaces := map[string]*InterfaceInfo{
		"wg0": {Name: "wg0", PrivateKey: "secret1"},
		"wg1": {Name: "wg1", PrivateKey: "secret2"},
		"wg2": {Name: "wg2", PrivateKey: "secret3"},
	}

	result := FilterInterfaces(ifaces, []string{"wg1"}, false)
	if _, ok := result["wg1"]; ok {
		t.Error("wg1 should have been filtered out")
	}
	if len(result) != 2 {
		t.Errorf("expected 2 interfaces, got %d", len(result))
	}
}

func TestFilterInterfaces_RedactSecrets(t *testing.T) {
	ifaces := map[string]*InterfaceInfo{
		"wg0": {Name: "wg0", PrivateKey: "super_secret_key"},
	}

	result := FilterInterfaces(ifaces, nil, true)
	if result["wg0"].PrivateKey != "" {
		t.Errorf("private key should be redacted, got %q", result["wg0"].PrivateKey)
	}
}

func TestNoneToEmpty(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"(none)", ""},
		{"off", ""},
		{"some_value", "some_value"},
		{"", ""},
	}

	for _, tt := range tests {
		result := noneToEmpty(tt.input)
		if result != tt.expected {
			t.Errorf("noneToEmpty(%q) = %q, want %q", tt.input, result, tt.expected)
		}
	}
}

func TestGetVersion(t *testing.T) {
	// Test with a non-existent binary (should return "unknown")
	ver := GetVersion("/nonexistent/wg")
	if ver != "unknown" {
		t.Errorf("expected 'unknown', got %q", ver)
	}
}
