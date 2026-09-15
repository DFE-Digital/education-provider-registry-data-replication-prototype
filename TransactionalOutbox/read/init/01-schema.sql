CREATE SCHEMA read_model;
CREATE SCHEMA inbox;

CREATE TABLE read_model.establishment (
    urn integer PRIMARY KEY,
    name text NOT NULL,
    local_authority_name text NOT NULL,
    display_name text NOT NULL,
    version bigint NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE inbox.processed_messages (
    message_id uuid PRIMARY KEY,
    processed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
