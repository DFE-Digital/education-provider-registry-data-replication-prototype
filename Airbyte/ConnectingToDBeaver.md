# Inspect the demo with DBeaver

Create two PostgreSQL connections in DBeaver running on your Windows host:

| Setting | Source | Read destination |
|---|---|---|
| Host | `localhost` | `localhost` |
| Port | `16432` | `16433` |
| Database | `airbyte_source` | `airbyte_read` |
| Username | `postgres` | `postgres` |
| Password | `postgres` | `postgres` |
| SSL | Disabled | Disabled |

These are disposable demo administrator credentials, used here to inspect all schemas. Airbyte itself uses the dedicated accounts listed in [the connection guide](./AirbyteReplicationPoCInit.md).

Test each connection and save it. In the source database, inspect `core.local_authority`, `core.establishment` and `core.site`. In the read database, refresh the schemas after a successful Airbyte sync and inspect the `airbyte` tables.

To discover the actual destination tables, run this against `airbyte_read`:

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
ORDER BY table_schema, table_name;
```

The `read_model` schema is currently empty. Follow [the demo steps](./README.md#configure-and-demonstrate-replication) to change a source record and verify it appears after the next manual sync.
