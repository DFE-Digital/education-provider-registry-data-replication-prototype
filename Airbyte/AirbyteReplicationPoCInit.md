# Airbyte connection setup

Start with [the README](./README.md) for prerequisites and `start-spike.ps1`. The following configuration is manual in the Airbyte UI. Database credentials are intentionally disposable local-demo values.

## Check the databases

```powershell
docker compose ps
docker compose exec -T source psql -U postgres -d airbyte_source -c "SELECT slot_name, plugin, database FROM pg_replication_slots;"
docker compose exec -T source psql -U postgres -d airbyte_source -c "SELECT pubname FROM pg_publication;"
```

The source should be published on `127.0.0.1:16432` and the read database on `127.0.0.1:16433`. Expect slot `airbyte_slot` using `pgoutput` for database `airbyte_source`, and publication `airbyte_publication`.

## Source

In the Airbyte UI at `http://localhost:8000`, create a PostgreSQL source:

| Setting | Value |
|---|---|
| Name | EPR Airbyte Spike - Source |
| Host | `host.docker.internal` |
| Port | `16432` |
| Database | `airbyte_source` |
| Username | `airbyte_replication` |
| Password | `airbyte` |
| Schema | `core` |
| SSL | Disabled |
| Update method | Read changes using Change Data Capture (CDC) |
| Replication slot | `airbyte_slot` |
| Publication | `airbyte_publication` |

Choose Test and Save.

## Destination

Create a PostgreSQL destination with the **read database** settings:

| Setting | Value |
|---|---|
| Name | EPR Airbyte Spike - Read |
| Host | `host.docker.internal` |
| Port | `16433` |
| Database | `airbyte_read` |
| Username | `airbyte_writer` |
| Password | `airbyte` |
| Default schema | `airbyte` |
| SSL | Disabled |
| SSH tunnel | No tunnel |

Choose Test and Save. Both connectors use Docker Desktop host networking; DBeaver on Windows uses `localhost` instead. UI wording can differ by connector version.

## Connection and initial sync

1. Create a connection from the source above to the read destination above.
2. Select all three `core` tables: `local_authority`, `establishment` and `site`.
3. Use the CDC-compatible incremental mode offered by the connector. Choose deduplication if available and you want the latest version of each record; an append mode may retain previous versions.
4. Set the schedule to manual and the destination namespace to Destination defined (the `airbyte` schema configured above).
5. Complete setup, run Sync now, and wait for success.

Use [DBeaver](./ConnectingToDBeaver.md) to inspect the read database. To list the created tables:

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
ORDER BY table_schema, table_name;
```

Follow [the README demo](./README.md#configure-and-demonstrate-replication) to update a source row and sync again. The `read_model` schema is empty until a projection is implemented.

For stopping or deleting database volumes, use the separate [stop](./README.md#stop-and-resume) and [reset](./README.md#reset-the-databases) instructions.
