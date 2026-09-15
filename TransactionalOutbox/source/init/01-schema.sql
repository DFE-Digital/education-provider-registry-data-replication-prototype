CREATE SCHEMA core;
CREATE SCHEMA outbox;

CREATE TABLE core.local_authority (
    id integer PRIMARY KEY,
    name text NOT NULL
);
CREATE TABLE core.establishment (
    urn integer PRIMARY KEY,
    name text NOT NULL,
    local_authority_id integer NOT NULL REFERENCES core.local_authority(id),
    version bigint NOT NULL CHECK (version > 0)
);
CREATE TABLE outbox.messages (
    id uuid PRIMARY KEY,
    aggregate_id integer NOT NULL,
    aggregate_version bigint NOT NULL,
    payload jsonb NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    published_at timestamptz,
    UNIQUE (aggregate_id, aggregate_version)
);
CREATE INDEX ix_outbox_pending ON outbox.messages (occurred_at) WHERE published_at IS NULL;

INSERT INTO core.local_authority VALUES (1, 'Test Local Authority');
-- Establishments are created by the application, together with their first event.
