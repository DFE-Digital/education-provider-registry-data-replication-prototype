> Return to [Main File](./PostgreSQLLogicalReplicationSpike.md)

# WAL Configuration

## `wal_level = logical`

* **What it does:** Tells PostgreSQL to write additional information to the Write-Ahead Log (WAL).

* **Why you need it:** The default WAL information is sufficient for physical replication, backups, and crash recovery. Setting `wal_level` to `logical` adds the information required to extract logical data changes such as inserts, updates, and deletes.

* **Use case:** PostgreSQL logical replication and Change Data Capture (CDC) tools such as Debezium require `wal_level = logical` to consume database changes.

---

## `max_replication_slots = 10`

* **What it does:** Sets the maximum number of replication slots that can exist at the same time.

* **Why you need it:** A replication slot tracks how much WAL data a replication consumer has processed. PostgreSQL retains the WAL required by that consumer until it is no longer needed.

* **Use case:** Setting this to `10` allows up to 10 replication slots to exist. These may be used by logical subscribers, CDC consumers, or physical replicas depending on the replication setup.

> **Note:** An inactive or stalled replication slot can cause PostgreSQL to retain WAL indefinitely, potentially consuming significant disk space.

---

## `max_wal_senders = 10`

* **What it does:** Sets the maximum number of concurrent WAL sender processes.

* **Why you need it:** Each active replication connection that streams WAL from the source PostgreSQL instance requires a WAL sender process.

* **Use case:** Setting this to `10` allows up to 10 concurrent WAL streaming connections, including physical replicas and logical replication subscribers.

`max_wal_senders` should be configured high enough to support the expected number of concurrent replication connections.
