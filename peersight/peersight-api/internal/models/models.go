package models

import (
	"time"

	"github.com/google/uuid"
)

// ────────────────────────────────────────────────
// User & Auth
// ────────────────────────────────────────────────

// User represents a system user (admin or operator).
type User struct {
	ID           uuid.UUID  `db:"id"            json:"id"`
	Email        string     `db:"email"         json:"email"`
	PasswordHash string     `db:"password_hash" json:"-"`
	Role         string     `db:"role"          json:"role"` // "admin" | "operator"
	CreatedAt    time.Time  `db:"created_at"    json:"created_at"`
	UpdatedAt    time.Time  `db:"updated_at"    json:"updated_at"`
	DeletedAt    *time.Time `db:"deleted_at"    json:"-"`
}

// Session holds a short-lived JWT session record.
type Session struct {
	ID        uuid.UUID `db:"id"         json:"id"`
	UserID    uuid.UUID `db:"user_id"    json:"user_id"`
	Token     string    `db:"token"      json:"-"`
	ExpiresAt time.Time `db:"expires_at" json:"expires_at"`
	CreatedAt time.Time `db:"created_at" json:"created_at"`
}

// ServiceToken represents an API token issued to a daemon such as an agent or broker.
type ServiceToken struct {
	ID          uuid.UUID  `db:"id"           json:"id"`
	OrgID       uuid.UUID  `db:"org_id"       json:"org_id"`
	TokenHash   string     `db:"token_hash"   json:"-"`
	TokenPrefix string     `db:"token_prefix" json:"token_prefix"`
	Kind        string     `db:"kind"         json:"kind"` // "agent" | "broker"
	HostID      *uuid.UUID `db:"host_id"      json:"host_id,omitempty"`
	Scopes      []string   `db:"scopes"       json:"scopes"`
	ExpiresAt   time.Time  `db:"expires_at"   json:"expires_at"`
	RevokedAt   *time.Time `db:"revoked_at"   json:"revoked_at,omitempty"`
	LastUsedAt  *time.Time `db:"last_used_at" json:"last_used_at,omitempty"`
	CreatedBy   *uuid.UUID `db:"created_by"   json:"created_by,omitempty"`
	CreatedAt   time.Time  `db:"created_at"   json:"created_at"`
}

// ────────────────────────────────────────────────
// WireGuard topology
// ────────────────────────────────────────────────

// Organization groups hosts/peers together (multi-tenant support).
type Organization struct {
	ID        uuid.UUID `db:"id"         json:"id"`
	Name      string    `db:"name"       json:"name"`
	CreatedAt time.Time `db:"created_at" json:"created_at"`
}

// Host represents a physical machine running WireGuard + the agent.
type Host struct {
	ID        uuid.UUID  `db:"id"         json:"id"`
	OrgID     uuid.UUID  `db:"org_id"     json:"org_id"`
	Name      string     `db:"name"       json:"name"`
	LastPing  *time.Time `db:"last_ping"  json:"last_ping"`
	AgentVer  string     `db:"agent_ver"  json:"agent_version"`
	CreatedAt time.Time  `db:"created_at" json:"created_at"`
	UpdatedAt time.Time  `db:"updated_at" json:"updated_at"`
}

// Peer represents a WireGuard keypair identity (may appear on multiple hosts).
type Peer struct {
	ID        uuid.UUID `db:"id"          json:"id"`
	OrgID     uuid.UUID `db:"org_id"      json:"org_id"`
	Name      string    `db:"name"        json:"name"`
	PublicKey string    `db:"public_key"  json:"public_key"`
	CreatedAt time.Time `db:"created_at"  json:"created_at"`
	UpdatedAt time.Time `db:"updated_at"  json:"updated_at"`
}

// Interface represents a wg interface (e.g. wg0) on a Host.
type Interface struct {
	ID         uuid.UUID `db:"id"          json:"id"`
	HostID     uuid.UUID `db:"host_id"     json:"host_id"`
	PeerID     uuid.UUID `db:"peer_id"     json:"peer_id"`
	Name       string    `db:"name"        json:"name"`
	ListenPort int       `db:"listen_port" json:"listen_port"`
	Fwmark     int       `db:"fwmark"      json:"fwmark"`
	Up         bool      `db:"up"          json:"up"`
	Address    string    `db:"address"     json:"address"`
	DNS        string    `db:"dns"         json:"dns"`
	MTU        int       `db:"mtu"         json:"mtu"`
	CreatedAt  time.Time `db:"created_at"  json:"created_at"`
	UpdatedAt  time.Time `db:"updated_at"  json:"updated_at"`
}

// Endpoint represents a peer connection slot on an Interface.
type Endpoint struct {
	ID            uuid.UUID  `db:"id"               json:"id"`
	InterfaceID   uuid.UUID  `db:"interface_id"     json:"interface_id"`
	PeerID        uuid.UUID  `db:"peer_id"          json:"peer_id"`
	IP            string     `db:"ip"               json:"ip"`
	Port          int        `db:"port"             json:"port"`
	AllowedIPs    string     `db:"allowed_ips"      json:"allowed_ips"`
	Keepalive     int        `db:"keepalive"        json:"keepalive"`
	Available     bool       `db:"available"        json:"available"`
	LastHandshake *time.Time `db:"last_handshake"   json:"last_handshake"`
	RxBytes       int64      `db:"rx_bytes"         json:"rx_bytes"`
	TxBytes       int64      `db:"tx_bytes"         json:"tx_bytes"`
	CreatedAt     time.Time  `db:"created_at"       json:"created_at"`
	UpdatedAt     time.Time  `db:"updated_at"       json:"updated_at"`
	InterfaceName string     `db:"-"                json:"interface_name,omitempty"`
	HostName      string     `db:"-"                json:"host_name,omitempty"`
	HostID        *uuid.UUID `db:"-"                json:"host_id,omitempty"`
}

// ────────────────────────────────────────────────
// Alerts & Desired Changes
// ────────────────────────────────────────────────

// Alert is a security/operational event generated by the system.
type Alert struct {
	ID        uuid.UUID  `db:"id"         json:"id"`
	OrgID     uuid.UUID  `db:"org_id"     json:"org_id"`
	HostID    *uuid.UUID `db:"host_id"    json:"host_id,omitempty"`
	Type      string     `db:"type"       json:"type"`  // "peer_connected" | "peer_dropped" | "auth_failed" ...
	Level     string     `db:"level"      json:"level"` // "info" | "warning" | "critical"
	Message   string     `db:"message"    json:"message"`
	Resolved  bool       `db:"resolved"   json:"resolved"`
	CreatedAt time.Time  `db:"created_at" json:"created_at"`
}

// DesiredChange represents a pending configuration change to push to an Agent.
type DesiredChange struct {
	ID         uuid.UUID  `db:"id"           json:"id"`
	HostID     uuid.UUID  `db:"host_id"      json:"host_id"`
	Type       string     `db:"type"         json:"type"`    // "add_peer" | "remove_peer" | "update_interface"
	Payload    string     `db:"payload"      json:"payload"` // JSON
	State      string     `db:"state"        json:"state"`   // "pending" | "executed" | "failed"
	Message    string     `db:"message"      json:"message"`
	CreatedAt  time.Time  `db:"created_at"   json:"created_at"`
	ExecutedAt *time.Time `db:"executed_at"  json:"executed_at,omitempty"`
	HostName   string     `db:"-"            json:"host_name,omitempty"`
}

// ────────────────────────────────────────────────
// Agent Ping request/response types
// ────────────────────────────────────────────────

// PingRequest is sent by the agent every cycle.
type PingRequest struct {
	AgentVersion string          `json:"agent_version"`
	ReadOnly     bool            `json:"read_only"`
	Interfaces   []PingInterface `json:"interfaces"`
	Executed     []PingExecuted  `json:"executed,omitempty"`
}

// PingInterface describes a WireGuard interface reported by an agent.
type PingInterface struct {
	Name       string     `json:"name"`
	PublicKey  string     `json:"public_key"`
	PrivateKey string     `json:"private_key,omitempty"`
	ListenPort int        `json:"listen_port"`
	Fwmark     int        `json:"fwmark"`
	Up         bool       `json:"up"`
	Address    string     `json:"address"`
	DNS        string     `json:"dns,omitempty"`
	MTU        int        `json:"mtu,omitempty"`
	Peers      []PingPeer `json:"peers"`
}

// PingPeer describes a WireGuard peer seen by an agent.
type PingPeer struct {
	PublicKey           string   `json:"public_key"`
	Endpoint            string   `json:"endpoint"`
	AllowedIPs          []string `json:"allowed_ips"`
	LatestHandshake     int64    `json:"latest_handshake"`
	TransferRx          int64    `json:"transfer_rx"`
	TransferTx          int64    `json:"transfer_tx"`
	PersistentKeepalive int      `json:"persistent_keepalive"`
	Available           bool     `json:"available"`
}

// PingExecuted reports completion of a previously issued DesiredChange.
type PingExecuted struct {
	ChangeID string `json:"change_id"`
	Success  bool   `json:"success"`
	Output   string `json:"output"`
}

// PingResponse is returned to the agent after each ping.
type PingResponse struct {
	Data []DesiredChange `json:"data"`
}

// ────────────────────────────────────────────────
// Broker queue types
// ────────────────────────────────────────────────

// QueueEvent is an item stored in the broker event queue.
type QueueEvent struct {
	ID          uuid.UUID  `db:"id"           json:"id"`
	OrgID       uuid.UUID  `db:"org_id"       json:"org_id"`
	Type        string     `db:"type"         json:"type"`
	Payload     string     `db:"payload"      json:"payload"`
	Acked       bool       `db:"acked"        json:"acked"`
	LockedUntil *time.Time `db:"locked_until" json:"locked_until,omitempty"`
	LockedBy    string     `db:"locked_by"    json:"locked_by,omitempty"`
	Attempts    int        `db:"attempts"     json:"attempts"`
	LastError   string     `db:"last_error"   json:"last_error,omitempty"`
	AckedAt     *time.Time `db:"acked_at"     json:"acked_at,omitempty"`
	CreatedAt   time.Time  `db:"created_at"   json:"created_at"`
}
