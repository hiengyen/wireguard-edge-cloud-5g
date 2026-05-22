-- Service-scoped daemon tokens and broker queue leases.

CREATE TABLE IF NOT EXISTS service_tokens (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id       UUID NOT NULL REFERENCES organizations(id),
    token_hash   TEXT NOT NULL UNIQUE,
    token_prefix TEXT NOT NULL,
    kind         TEXT NOT NULL CHECK (kind IN ('agent', 'broker')),
    host_id      UUID REFERENCES hosts(id) ON DELETE CASCADE,
    scopes       TEXT[] NOT NULL DEFAULT '{}',
    expires_at   TIMESTAMPTZ NOT NULL,
    revoked_at   TIMESTAMPTZ,
    last_used_at TIMESTAMPTZ,
    created_by   UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_service_tokens_kind ON service_tokens(kind);
CREATE INDEX IF NOT EXISTS idx_service_tokens_host ON service_tokens(host_id) WHERE host_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_service_tokens_active ON service_tokens(org_id, kind, expires_at)
    WHERE revoked_at IS NULL;

ALTER TABLE queue_events ADD COLUMN IF NOT EXISTS locked_until TIMESTAMPTZ;
ALTER TABLE queue_events ADD COLUMN IF NOT EXISTS locked_by TEXT NOT NULL DEFAULT '';
ALTER TABLE queue_events ADD COLUMN IF NOT EXISTS attempts INT NOT NULL DEFAULT 0;
ALTER TABLE queue_events ADD COLUMN IF NOT EXISTS last_error TEXT NOT NULL DEFAULT '';
ALTER TABLE queue_events ADD COLUMN IF NOT EXISTS acked_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_queue_ready
    ON queue_events(org_id, type, acked, locked_until, created_at);
