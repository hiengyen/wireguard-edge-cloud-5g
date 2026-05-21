package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/peersight/api/internal/models"
)

// ────────────────────────────────────────────────
// Host queries
// ────────────────────────────────────────────────

// GetHost returns a host by ID.
func (db *DB) GetHost(ctx context.Context, id uuid.UUID) (*models.Host, error) {
	h := &models.Host{}
	err := db.Pool.QueryRow(ctx,
		`SELECT id, org_id, name, last_ping, agent_ver, created_at, updated_at
		   FROM hosts WHERE id = $1`, id).
		Scan(&h.ID, &h.OrgID, &h.Name, &h.LastPing, &h.AgentVer, &h.CreatedAt, &h.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return h, nil
}

// ListHosts returns all hosts for an organization.
func (db *DB) ListHosts(ctx context.Context, orgID uuid.UUID) ([]models.Host, error) {
	rows, err := db.Pool.Query(ctx,
		`SELECT id, org_id, name, last_ping, agent_ver, created_at, updated_at
		   FROM hosts WHERE org_id = $1 ORDER BY name`, orgID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var hosts []models.Host
	for rows.Next() {
		var h models.Host
		if err := rows.Scan(&h.ID, &h.OrgID, &h.Name, &h.LastPing, &h.AgentVer, &h.CreatedAt, &h.UpdatedAt); err != nil {
			return nil, err
		}
		hosts = append(hosts, h)
	}
	return hosts, nil
}

// RecordPing updates the host's last ping time and agent version.
func (db *DB) RecordPing(ctx context.Context, hostID uuid.UUID, agentVer string) error {
	now := time.Now().UTC()
	_, err := db.Pool.Exec(ctx,
		`UPDATE hosts SET last_ping = $1, agent_ver = $2, updated_at = $1 WHERE id = $3`,
		now, agentVer, hostID)
	return err
}

// ────────────────────────────────────────────────
// Peer queries
// ────────────────────────────────────────────────

// FindOrCreatePeer returns existing peer by public key, or inserts a new one.
func (db *DB) FindOrCreatePeer(ctx context.Context, orgID uuid.UUID, publicKey, name string) (*models.Peer, error) {
	p := &models.Peer{}
	err := db.Pool.QueryRow(ctx,
		`SELECT id, org_id, name, public_key, created_at, updated_at
		   FROM peers WHERE org_id = $1 AND public_key = $2`, orgID, publicKey).
		Scan(&p.ID, &p.OrgID, &p.Name, &p.PublicKey, &p.CreatedAt, &p.UpdatedAt)
	if err == nil {
		return p, nil
	}

	// Insert new peer
	id := uuid.New()
	now := time.Now().UTC()
	_, err = db.Pool.Exec(ctx,
		`INSERT INTO peers (id, org_id, name, public_key, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $5)`,
		id, orgID, name, publicKey, now)
	if err != nil {
		return nil, err
	}

	return &models.Peer{ID: id, OrgID: orgID, Name: name, PublicKey: publicKey, CreatedAt: now, UpdatedAt: now}, nil
}

// ListPeers returns all peers for an organization.
func (db *DB) ListPeers(ctx context.Context, orgID uuid.UUID) ([]models.Peer, error) {
	rows, err := db.Pool.Query(ctx,
		`SELECT id, org_id, name, public_key, created_at, updated_at
		   FROM peers WHERE org_id = $1 ORDER BY name`, orgID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var peers []models.Peer
	for rows.Next() {
		var p models.Peer
		if err := rows.Scan(&p.ID, &p.OrgID, &p.Name, &p.PublicKey, &p.CreatedAt, &p.UpdatedAt); err != nil {
			return nil, err
		}
		peers = append(peers, p)
	}
	return peers, nil
}

// DeletePeer removes a peer by ID.
func (db *DB) DeletePeer(ctx context.Context, id uuid.UUID) error {
	_, err := db.Pool.Exec(ctx, `DELETE FROM peers WHERE id = $1`, id)
	return err
}

// ────────────────────────────────────────────────
// Interface queries
// ────────────────────────────────────────────────

// ListInterfaces returns all interfaces for a host.
func (db *DB) ListInterfaces(ctx context.Context, hostID uuid.UUID) ([]models.Interface, error) {
	rows, err := db.Pool.Query(ctx,
		`SELECT id, host_id, peer_id, name, listen_port, fwmark, up, address, dns, mtu, created_at, updated_at
		   FROM interfaces WHERE host_id = $1 ORDER BY name`, hostID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ifaces []models.Interface
	for rows.Next() {
		var i models.Interface
		if err := rows.Scan(&i.ID, &i.HostID, &i.PeerID, &i.Name, &i.ListenPort, &i.Fwmark,
			&i.Up, &i.Address, &i.DNS, &i.MTU, &i.CreatedAt, &i.UpdatedAt); err != nil {
			return nil, err
		}
		ifaces = append(ifaces, i)
	}
	return ifaces, nil
}

// FindOrCreateInterface upserts a WireGuard interface record.
func (db *DB) FindOrCreateInterface(ctx context.Context, iface *models.Interface) (*models.Interface, error) {
	existing := &models.Interface{}
	err := db.Pool.QueryRow(ctx,
		`SELECT id, host_id, peer_id, name, listen_port, fwmark, up, address, dns, mtu, created_at, updated_at
		   FROM interfaces WHERE host_id = $1 AND name = $2`, iface.HostID, iface.Name).
		Scan(&existing.ID, &existing.HostID, &existing.PeerID, &existing.Name,
			&existing.ListenPort, &existing.Fwmark, &existing.Up, &existing.Address,
			&existing.DNS, &existing.MTU, &existing.CreatedAt, &existing.UpdatedAt)
	if err == nil {
		// Update existing
		now := time.Now().UTC()
		_, err = db.Pool.Exec(ctx,
			`UPDATE interfaces SET peer_id=$1, listen_port=$2, fwmark=$3, up=$4,
			        address=$5, dns=$6, mtu=$7, updated_at=$8 WHERE id=$9`,
			iface.PeerID, iface.ListenPort, iface.Fwmark, iface.Up,
			iface.Address, iface.DNS, iface.MTU, now, existing.ID)
		if err != nil {
			return nil, err
		}
		existing.PeerID = iface.PeerID
		existing.ListenPort = iface.ListenPort
		existing.Fwmark = iface.Fwmark
		existing.Up = iface.Up
		existing.Address = iface.Address
		existing.DNS = iface.DNS
		existing.MTU = iface.MTU
		existing.UpdatedAt = now
		return existing, nil
	}

	// Insert new
	iface.ID = uuid.New()
	now := time.Now().UTC()
	iface.CreatedAt = now
	iface.UpdatedAt = now
	_, err = db.Pool.Exec(ctx,
		`INSERT INTO interfaces (id, host_id, peer_id, name, listen_port, fwmark, up, address, dns, mtu, created_at, updated_at)
		 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$11)`,
		iface.ID, iface.HostID, iface.PeerID, iface.Name, iface.ListenPort,
		iface.Fwmark, iface.Up, iface.Address, iface.DNS, iface.MTU, now)
	if err != nil {
		return nil, err
	}
	return iface, nil
}

// MarkDownOtherInterfaces marks all interfaces for a host that are NOT in activeIDs as down.
func (db *DB) MarkDownOtherInterfaces(ctx context.Context, hostID uuid.UUID, activeIDs []uuid.UUID) error {
	_, err := db.Pool.Exec(ctx,
		`UPDATE interfaces SET up = false, updated_at = NOW()
		  WHERE host_id = $1 AND id != ALL($2)`, hostID, activeIDs)
	return err
}

// ────────────────────────────────────────────────
// Endpoint queries
// ────────────────────────────────────────────────

// ListEndpointsByHost returns all endpoints for a host via its interfaces.
func (db *DB) ListEndpointsByHost(ctx context.Context, hostID uuid.UUID) ([]models.Endpoint, error) {
	rows, err := db.Pool.Query(ctx,
		`SELECT e.id, e.interface_id, e.peer_id, e.ip, e.port, e.allowed_ips, e.keepalive,
		        e.available, e.last_handshake, e.rx_bytes, e.tx_bytes, e.created_at, e.updated_at
		   FROM endpoints e
		   JOIN interfaces i ON e.interface_id = i.id
		  WHERE i.host_id = $1
		  ORDER BY e.updated_at DESC`, hostID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var endpoints []models.Endpoint
	for rows.Next() {
		var ep models.Endpoint
		if err := rows.Scan(&ep.ID, &ep.InterfaceID, &ep.PeerID, &ep.IP, &ep.Port, &ep.AllowedIPs,
			&ep.Keepalive, &ep.Available, &ep.LastHandshake, &ep.RxBytes, &ep.TxBytes,
			&ep.CreatedAt, &ep.UpdatedAt); err != nil {
			return nil, err
		}
		endpoints = append(endpoints, ep)
	}
	return endpoints, nil
}

// UpsertEndpoint inserts or updates an endpoint connection.
func (db *DB) UpsertEndpoint(ctx context.Context, ep *models.Endpoint) (*models.Endpoint, error) {
	existing := &models.Endpoint{}
	err := db.Pool.QueryRow(ctx,
		`SELECT id FROM endpoints WHERE interface_id = $1 AND peer_id = $2`,
		ep.InterfaceID, ep.PeerID).Scan(&existing.ID)
	if err == nil {
		now := time.Now().UTC()
		_, err = db.Pool.Exec(ctx,
			`UPDATE endpoints SET ip=$1, port=$2, allowed_ips=$3, keepalive=$4,
			        available=$5, last_handshake=$6, rx_bytes=$7, tx_bytes=$8, updated_at=$9
			  WHERE id=$10`,
			ep.IP, ep.Port, ep.AllowedIPs, ep.Keepalive, ep.Available,
			ep.LastHandshake, ep.RxBytes, ep.TxBytes, now, existing.ID)
		ep.ID = existing.ID
		ep.UpdatedAt = now
		return ep, err
	}

	ep.ID = uuid.New()
	now := time.Now().UTC()
	ep.CreatedAt = now
	ep.UpdatedAt = now
	_, err = db.Pool.Exec(ctx,
		`INSERT INTO endpoints (id, interface_id, peer_id, ip, port, allowed_ips, keepalive,
		        available, last_handshake, rx_bytes, tx_bytes, created_at, updated_at)
		 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$12)`,
		ep.ID, ep.InterfaceID, ep.PeerID, ep.IP, ep.Port, ep.AllowedIPs, ep.Keepalive,
		ep.Available, ep.LastHandshake, ep.RxBytes, ep.TxBytes, now)
	return ep, err
}

// ────────────────────────────────────────────────
// Desired Changes
// ────────────────────────────────────────────────

// ListAllChanges returns all desired changes for a host (any state).
func (db *DB) ListAllChanges(ctx context.Context, hostID uuid.UUID) ([]models.DesiredChange, error) {
	rows, err := db.Pool.Query(ctx,
		`SELECT id, host_id, type, payload, state, message, created_at, executed_at
		   FROM desired_changes WHERE host_id = $1 ORDER BY created_at DESC LIMIT 50`, hostID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var changes []models.DesiredChange
	for rows.Next() {
		var c models.DesiredChange
		if err := rows.Scan(&c.ID, &c.HostID, &c.Type, &c.Payload, &c.State, &c.Message, &c.CreatedAt, &c.ExecutedAt); err != nil {
			return nil, err
		}
		changes = append(changes, c)
	}
	return changes, nil
}

// ListPendingChanges returns pending desired changes for a host.
func (db *DB) ListPendingChanges(ctx context.Context, hostID uuid.UUID) ([]models.DesiredChange, error) {
	rows, err := db.Pool.Query(ctx,
		`SELECT id, host_id, type, payload, state, message, created_at, executed_at
		   FROM desired_changes WHERE host_id = $1 AND state = 'pending' ORDER BY created_at`, hostID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var changes []models.DesiredChange
	for rows.Next() {
		var c models.DesiredChange
		if err := rows.Scan(&c.ID, &c.HostID, &c.Type, &c.Payload, &c.State, &c.Message, &c.CreatedAt, &c.ExecutedAt); err != nil {
			return nil, err
		}
		changes = append(changes, c)
	}
	return changes, nil
}

// MarkChangeExecuted updates the state of a desired change to executed or failed.
func (db *DB) MarkChangeExecuted(ctx context.Context, changeID uuid.UUID, success bool, output string) error {
	state := "executed"
	if !success {
		state = "failed"
	}
	now := time.Now().UTC()
	_, err := db.Pool.Exec(ctx,
		`UPDATE desired_changes SET state=$1, message=$2, executed_at=$3 WHERE id=$4`,
		state, output, now, changeID)
	return err
}

// CreateDesiredChange inserts a new desired change for a host.
func (db *DB) CreateDesiredChange(ctx context.Context, dc *models.DesiredChange) error {
	dc.ID = uuid.New()
	dc.State = "pending"
	dc.CreatedAt = time.Now().UTC()
	_, err := db.Pool.Exec(ctx,
		`INSERT INTO desired_changes (id, host_id, type, payload, state, message, created_at)
		 VALUES ($1,$2,$3,$4,$5,$6,$7)`,
		dc.ID, dc.HostID, dc.Type, dc.Payload, dc.State, dc.Message, dc.CreatedAt)
	return err
}

// ────────────────────────────────────────────────
// Alerts
// ────────────────────────────────────────────────

// ListAlerts returns alerts for an organization.
func (db *DB) ListAlerts(ctx context.Context, orgID uuid.UUID, limit int) ([]models.Alert, error) {
	rows, err := db.Pool.Query(ctx,
		`SELECT id, org_id, host_id, type, level, message, resolved, created_at
		   FROM alerts WHERE org_id = $1 ORDER BY created_at DESC LIMIT $2`, orgID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var alerts []models.Alert
	for rows.Next() {
		var a models.Alert
		if err := rows.Scan(&a.ID, &a.OrgID, &a.HostID, &a.Type, &a.Level, &a.Message, &a.Resolved, &a.CreatedAt); err != nil {
			return nil, err
		}
		alerts = append(alerts, a)
	}
	return alerts, nil
}

// CreateAlert inserts a new alert.
func (db *DB) CreateAlert(ctx context.Context, a *models.Alert) error {
	a.ID = uuid.New()
	a.CreatedAt = time.Now().UTC()
	_, err := db.Pool.Exec(ctx,
		`INSERT INTO alerts (id, org_id, host_id, type, level, message, resolved, created_at)
		 VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
		a.ID, a.OrgID, a.HostID, a.Type, a.Level, a.Message, a.Resolved, a.CreatedAt)
	return err
}

// ResolveAlert marks an alert as resolved.
func (db *DB) ResolveAlert(ctx context.Context, id uuid.UUID) error {
	_, err := db.Pool.Exec(ctx,
		`UPDATE alerts SET resolved = true WHERE id = $1`, id)
	return err
}

// ────────────────────────────────────────────────
// Queue events (for Broker)
// ────────────────────────────────────────────────

// PollQueue returns the next N unacknowledged events of a given type.
// Events are NOT automatically acked — the broker must call AckQueueEvents
// after successfully processing them to prevent event loss.
func (db *DB) PollQueue(ctx context.Context, orgID uuid.UUID, eventType string, max int) ([]models.QueueEvent, error) {
	rows, err := db.Pool.Query(ctx,
		`SELECT id, org_id, type, payload, acked, created_at
		   FROM queue_events WHERE org_id = $1 AND type = $2 AND acked = false
		   ORDER BY created_at LIMIT $3`, orgID, eventType, max)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var events []models.QueueEvent
	for rows.Next() {
		var e models.QueueEvent
		if err := rows.Scan(&e.ID, &e.OrgID, &e.Type, &e.Payload, &e.Acked, &e.CreatedAt); err != nil {
			return nil, err
		}
		events = append(events, e)
	}

	return events, nil
}

// AckQueueEvents marks specific events as acknowledged. The broker calls this
// after it has successfully processed and delivered the events to their pipes.
func (db *DB) AckQueueEvents(ctx context.Context, eventIDs []uuid.UUID) error {
	_, err := db.Pool.Exec(ctx,
		`UPDATE queue_events SET acked = true WHERE id = ANY($1)`, eventIDs)
	return err
}

// EnqueueEvent inserts a new event into the queue.
func (db *DB) EnqueueEvent(ctx context.Context, e *models.QueueEvent) error {
	e.ID = uuid.New()
	e.CreatedAt = time.Now().UTC()
	_, err := db.Pool.Exec(ctx,
		`INSERT INTO queue_events (id, org_id, type, payload, acked, created_at)
		 VALUES ($1,$2,$3,$4,false,$5)`,
		e.ID, e.OrgID, e.Type, e.Payload, e.CreatedAt)
	return err
}

// ────────────────────────────────────────────────
// User / Auth queries
// ────────────────────────────────────────────────

// GetUserByEmail returns a user by email.
func (db *DB) GetUserByEmail(ctx context.Context, email string) (*models.User, error) {
	u := &models.User{}
	err := db.Pool.QueryRow(ctx,
		`SELECT id, email, password_hash, role, created_at, updated_at
		   FROM users WHERE email = $1 AND deleted_at IS NULL`, email).
		Scan(&u.ID, &u.Email, &u.PasswordHash, &u.Role, &u.CreatedAt, &u.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return u, nil
}

// GetUserByID returns a user by UUID.
func (db *DB) GetUserByID(ctx context.Context, id uuid.UUID) (*models.User, error) {
	u := &models.User{}
	err := db.Pool.QueryRow(ctx,
		`SELECT id, email, password_hash, role, created_at, updated_at
		   FROM users WHERE id = $1 AND deleted_at IS NULL`, id).
		Scan(&u.ID, &u.Email, &u.PasswordHash, &u.Role, &u.CreatedAt, &u.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return u, nil
}

// CreateUser inserts a new user.
func (db *DB) CreateUser(ctx context.Context, u *models.User) error {
	u.ID = uuid.New()
	now := time.Now().UTC()
	u.CreatedAt = now
	u.UpdatedAt = now
	_, err := db.Pool.Exec(ctx,
		`INSERT INTO users (id, email, password_hash, role, created_at, updated_at)
		 VALUES ($1,$2,$3,$4,$5,$5)`,
		u.ID, u.Email, u.PasswordHash, u.Role, now)
	return err
}

// ListUsers returns all non-deleted users.
func (db *DB) ListUsers(ctx context.Context) ([]models.User, error) {
	rows, err := db.Pool.Query(ctx,
		`SELECT id, email, password_hash, role, created_at, updated_at
		 FROM users
		 WHERE deleted_at IS NULL
		 ORDER BY created_at DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var users []models.User
	for rows.Next() {
		var u models.User
		if err := rows.Scan(&u.ID, &u.Email, &u.PasswordHash, &u.Role, &u.CreatedAt, &u.UpdatedAt); err != nil {
			return nil, err
		}
		// Strip password hash before returning
		u.PasswordHash = ""
		users = append(users, u)
	}
	return users, rows.Err()
}

// UpdateUserRole updates the role of a user.
func (db *DB) UpdateUserRole(ctx context.Context, id uuid.UUID, role string) error {
	cmd, err := db.Pool.Exec(ctx,
		`UPDATE users SET role = $1, updated_at = NOW() WHERE id = $2 AND deleted_at IS NULL`,
		role, id)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return fmt.Errorf("user not found")
	}
	return nil
}

// DeleteUser soft-deletes a user.
func (db *DB) DeleteUser(ctx context.Context, id uuid.UUID) error {
	cmd, err := db.Pool.Exec(ctx,
		`UPDATE users SET deleted_at = NOW() WHERE id = $1 AND deleted_at IS NULL`, id)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return fmt.Errorf("user not found")
	}
	return nil
}
