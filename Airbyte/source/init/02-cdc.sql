CREATE USER airbyte_replication
WITH PASSWORD 'airbyte';

ALTER USER airbyte_replication
WITH REPLICATION;

GRANT CONNECT
ON DATABASE airbyte_source
TO airbyte_replication;

GRANT USAGE
ON SCHEMA core
TO airbyte_replication;

GRANT SELECT
ON ALL TABLES IN SCHEMA core
TO airbyte_replication;

ALTER DEFAULT PRIVILEGES
IN SCHEMA core
GRANT SELECT ON TABLES
TO airbyte_replication;


ALTER TABLE core.local_authority
REPLICA IDENTITY DEFAULT;

ALTER TABLE core.establishment
REPLICA IDENTITY DEFAULT;

ALTER TABLE core.site
REPLICA IDENTITY DEFAULT;


CREATE PUBLICATION airbyte_publication
FOR TABLE
    core.local_authority,
    core.establishment,
    core.site;


SELECT *
FROM pg_create_logical_replication_slot(
    'airbyte_slot',
    'pgoutput'
);