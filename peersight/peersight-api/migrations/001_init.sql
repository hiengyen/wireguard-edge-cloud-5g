-- peersight database schema
-- Run: psql -U peersight -d peersight -f 001_init.sql

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ── Organizations ──
CREATE TABLE IF NOT EXISTS organizations (
    id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name       TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Default org for single-tenant setups
INSERT INTO organizations (id, name)
VALUES ('00000000-0000-0000-0000-000000000001', 'Default')
ON CONFLICT DO NOTHING;

-- ── Users ──
CREATE TABLE IF NOT EXISTS users (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email         TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role          TEXT NOT NULL DEFAULT 'operator',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at    TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE deleted_at IS NULL;

-- ── Hosts ──
CREATE TABLE IF NOT EXISTS hosts (
    id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id     UUID NOT NULL REFERENCES organizations(id),
    name       TEXT NOT NULL,
    last_ping  TIMESTAMPTZ,
    agent_ver  TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_hosts_org ON hosts(org_id);

-- ── Peers ──
CREATE TABLE IF NOT EXISTS peers (
    id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id     UUID NOT NULL REFERENCES organizations(id),
    name       TEXT NOT NULL,
    public_key TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(org_id, public_key)
);

CREATE INDEX IF NOT EXISTS idx_peers_org ON peers(org_id);
CREATE INDEX IF NOT EXISTS idx_peers_pubkey ON peers(org_id, public_key);

-- ── Interfaces ──
CREATE TABLE IF NOT EXISTS interfaces (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    host_id     UUID NOT NULL REFERENCES hosts(id) ON DELETE CASCADE,
    peer_id     UUID NOT NULL REFERENCES peers(id),
    name        TEXT NOT NULL,
    listen_port INT NOT NULL DEFAULT 0,
    fwmark      INT NOT NULL DEFAULT 0,
    up          BOOLEAN NOT NULL DEFAULT false,
    address     TEXT NOT NULL DEFAULT '',
    dns         TEXT NOT NULL DEFAULT '',
    mtu         INT NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(host_id, name)
);

CREATE INDEX IF NOT EXISTS idx_ifaces_host ON interfaces(host_id);

-- ── Endpoints ──
CREATE TABLE IF NOT EXISTS endpoints (
    id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    interface_id   UUID NOT NULL REFERENCES interfaces(id) ON DELETE CASCADE,
    peer_id        UUID NOT NULL REFERENCES peers(id),
    ip             TEXT NOT NULL DEFAULT '',
    port           INT NOT NULL DEFAULT 0,
    allowed_ips    TEXT NOT NULL DEFAULT '',
    keepalive      INT NOT NULL DEFAULT 0,
    available      BOOLEAN NOT NULL DEFAULT false,
    last_handshake TIMESTAMPTZ,
    rx_bytes       BIGINT NOT NULL DEFAULT 0,
    tx_bytes       BIGINT NOT NULL DEFAULT 0,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(interface_id, peer_id)
);

CREATE INDEX IF NOT EXISTS idx_endpoints_iface ON endpoints(interface_id);

-- ── Desired Changes ──
CREATE TABLE IF NOT EXISTS desired_changes (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    host_id     UUID NOT NULL REFERENCES hosts(id) ON DELETE CASCADE,
    type        TEXT NOT NULL,
    payload     JSONB NOT NULL DEFAULT '{}',
    state       TEXT NOT NULL DEFAULT 'pending',
    message     TEXT NOT NULL DEFAULT '',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    executed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_changes_host ON desired_changes(host_id, state);

-- ── Alerts ──
CREATE TABLE IF NOT EXISTS alerts (
    id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id     UUID NOT NULL REFERENCES organizations(id),
    host_id    UUID REFERENCES hosts(id) ON DELETE SET NULL,
    type       TEXT NOT NULL,
    level      TEXT NOT NULL DEFAULT 'info',
    message    TEXT NOT NULL,
    resolved   BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_alerts_org ON alerts(org_id, created_at DESC);

-- ── Queue Events (for Broker) ──
CREATE TABLE IF NOT EXISTS queue_events (
    id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id     UUID NOT NULL REFERENCES organizations(id),
    type       TEXT NOT NULL,
    payload    JSONB NOT NULL DEFAULT '{}',
    acked      BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_queue_org_type ON queue_events(org_id, type, acked, created_at);
