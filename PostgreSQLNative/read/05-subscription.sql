CREATE SUBSCRIPTION epr_real_subscription
CONNECTION 'host=postgres-source port=5432 dbname=epr_real_source user=epr_real_replicator password=<replication-password>'
PUBLICATION epr_real_publication
WITH (
    slot_name = 'epr_real_slot',
    copy_data = true
);
