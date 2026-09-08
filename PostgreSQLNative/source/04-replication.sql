CREATE ROLE epr_real_replicator WITH LOGIN REPLICATION;

GRANT CONNECT ON DATABASE epr_real_source TO epr_real_replicator;

GRANT USAGE ON SCHEMA ref, core TO epr_real_replicator;

GRANT SELECT ON ALL TABLES IN SCHEMA ref, core TO epr_real_replicator;

CREATE PUBLICATION epr_real_publication FOR ALL TABLES;
