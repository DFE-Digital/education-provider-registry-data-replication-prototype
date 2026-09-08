# PostgreSQL Logical Replication Spike

## Prerequisites

PostgreSQL logical replication requires:

* `wal_level = logical`
* `max_replication_slots = 10`
* `max_wal_senders = 10`

> `WAL` stands for **Write-Ahead Log**.
> See [WAL information](./walinfo.md) for additional details about the required PostgreSQL WAL settings.

Logical replication is not available when `wal_level` is set to `replica`.

---

## Initial Test

Create a Docker environment containing two PostgreSQL instances:

* `source_db` – the source database
* `read_db` – the destination/read database

The required WAL settings are:

```text
wal_level = logical
max_replication_slots = 10
max_wal_senders = 10
```

See the accompanying `docker-compose.yml` file for reference.

PostgreSQL logical replication replicates **data changes**, rather than automatically creating the destination schema.

This means that a compatible destination table must already exist before replication can occur. For this initial test, compatible means that the source and destination tables have equivalent schemas.

A primary key also provides PostgreSQL with a way of identifying individual rows when processing `UPDATE` and `DELETE` operations.

Start the Docker containers with:

```powershell
docker compose up -d
```

Docker Desktop, or another running Docker daemon, is required.

---

## Test Replication

### 1. Create the test table

Create the same test table in both the source and read databases:

```sql
CREATE TABLE replication_test (
    id integer PRIMARY KEY,
    name text NOT NULL
);
```

### 2. Insert initial data into the source

Run the following against `source_db`:

```sql
INSERT INTO replication_test (id, name)
VALUES (1, 'Before replication');
```

### 3. Verify the initial state

Run the following query against both database instances:

```sql
SELECT * FROM replication_test;
```

At this point:

* `source_db` should contain the row.
* `read_db` should contain no rows.

This confirms that the two databases are currently independent.

### 4. Create a publication

On `source_db`, create a publication for the test table:

```sql
CREATE PUBLICATION epr_spike_publication
FOR TABLE replication_test;
```

The publication defines which source tables PostgreSQL should make available for logical replication.

### 5. Create a subscription

On `read_db`, create a subscription to the publication:

```sql
CREATE SUBSCRIPTION epr_spike_subscription
CONNECTION 'host=postgres-source port=5432 dbname=postgres user=postgres password=postgres'
PUBLICATION epr_spike_publication;
```

The subscription connects the read database to the source database and consumes changes published by `epr_spike_publication`.

### 6. Verify the initial data has replicated

On `read_db`, run:

```sql
SELECT * FROM replication_test;
```

The existing row should now be present:

```text
 id |        name
----+--------------------
  1 | Before replication
```

### 7. Verify subsequent changes are replicated

Insert another row into `source_db`:

```sql
INSERT INTO replication_test (id, name)
VALUES (2, 'After replication');
```

Then run the following against `read_db`:

```sql
SELECT * FROM replication_test;
```

The destination should now contain both rows, confirming that logical replication is working:

```text
 id |        name
----+--------------------
  1 | Before replication
  2 | After replication
```

## Next Investigation
 Investigate mechanisms for denormalised replication
