# PostgreSQL Physical Denormalised Replication — Read Projection Creation, Rebuild and Recovery

## Goal

Investigate how a physical denormalised read model can be initialised, rebuilt and recovered while using PostgreSQL logical replication.

The existing replica triggers maintain individual rows as changes arrive. A separate rebuild mechanism is required to recreate the complete projection from the normalised read-side tables.

The rebuild may be needed when creating a new read environment, changing the projection schema, recovering from incorrect projection data, or deploying a new version of the read model.

## Current Architecture

```text
NORMALISED SOURCE
        │
        │ PostgreSQL logical replication
        ▼
NORMALISED READ TABLES
        │
        ├── Incremental replica triggers
        │       → refresh affected rows
        │
        └── Rebuild procedure
                → regenerate the complete projection
                        │
                        ▼
          spike_establishment_read_table
```

The important distinction is that incremental maintenance and full rebuilding are separate operations, even though they use the same underlying normalised data.

## Transactional Rebuild

The first experiment used a transaction to delete and repopulate the physical projection.

A rollback test confirmed that deleting the rows inside a transaction and then executing `ROLLBACK` restored the previous contents.

A successful rebuild then deleted and reinserted the projection rows before committing. The final result contained both establishments with the latest values available in the raw replicated tables.

**Result: Passed**

This established that the projection could be regenerated from its source data without relying on individual trigger events.

## Repeatable Rebuild Procedure

The manual rebuild was converted into a stored procedure so that the operation can be executed consistently.

The procedure is deliberately a **blocking rebuild prototype**. It prevents replicated writes to the relevant raw tables while rebuilding, giving the projection a stable set of input data.

Create the following procedure on the **read database**:

```sql
CREATE OR REPLACE PROCEDURE public.rebuild_spike_establishment_read()
LANGUAGE plpgsql
AS $$
DECLARE
    v_rows bigint;
BEGIN
    SET LOCAL lock_timeout = '5s';

    LOCK TABLE
        public.spike_establishment,
        public.spike_local_authority,
        public.spike_site
    IN SHARE MODE;

    LOCK TABLE public.spike_establishment_read_table
    IN SHARE ROW EXCLUSIVE MODE;

    DELETE FROM public.spike_establishment_read_table;

    INSERT INTO public.spike_establishment_read_table (
        urn,
        name,
        local_authority_name,
        address_line_1,
        town,
        postcode
    )
    SELECT
        e.urn,
        e.name,
        la.name,
        s.address_line_1,
        s.town,
        s.postcode
    FROM public.spike_establishment e
    JOIN public.spike_local_authority la
        ON la.id = e.local_authority_id
    JOIN public.spike_site s
        ON s.establishment_id = e.id;

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    RAISE NOTICE 'Rebuilt % establishment rows.', v_rows;
END;
$$;
```

### How the procedure works

`CREATE OR REPLACE PROCEDURE` creates a reusable database operation that can be executed with `CALL`.

`SET LOCAL lock_timeout = '5s'` limits how long the procedure will wait to acquire a lock. If the timeout is exceeded, the operation fails rather than waiting indefinitely.

The `SHARE` locks on the raw tables allow ordinary reads but prevent concurrent inserts, updates and deletes while the rebuild is running. This means the projection is built from a stable set of replicated rows.

The `SHARE ROW EXCLUSIVE` lock on the physical projection prevents other transactions from writing to it during the rebuild.

The `DELETE` removes the existing projection rows, and the `INSERT INTO ... SELECT` recreates them by joining the current normalised data.

`GET DIAGNOSTICS ... ROW_COUNT` captures the number of rows inserted, and `RAISE NOTICE` prints that count.

The procedure does not contain an explicit `COMMIT`. When called as a standalone statement in autocommit mode, the operation runs in a single transaction. If an error occurs, the transaction is rolled back. The PL/pgSQL `BEGIN` and `END` delimit the procedure body and are not transaction commands.

## Execute the Rebuild

Run the procedure on the **read database**:

```sql
CALL public.rebuild_spike_establishment_read();
```

Verify the result:

```sql
SELECT *
FROM public.spike_establishment_read_table
ORDER BY urn;
```

Observed result:

```text
NOTICE: Rebuilt 2 establishment rows.
CALL

  urn   |          name          |   local_authority_name    | address_line_1 |    town     | postcode
--------+------------------------+---------------------------+----------------+-------------+----------
 100001 | Updated During Rebuild | Cardiff Authority Renamed | 1 Test Street  | Cardiff Bay | CF10 1AA
 100002 | Second Test School     | Cardiff Authority Renamed | 2 Test Street  | Cardiff     | CF10 2BB
(2 rows)
```

**Result: Passed**

The procedure successfully rebuilt the complete physical projection.

## Rebuild While Replication Continues

A further experiment tested the locking behaviour while the subscription remained enabled.

The rebuild was executed inside an explicit transaction and left uncommitted. A source update was then performed while the read-side transaction held its locks.

The source update succeeded, while the subscriber could not apply the corresponding write to the locked raw table until the rebuild transaction committed.

A separate read-side connection was able to query the previously committed projection. After the rebuild transaction committed, the subscription applied the pending change and the replica trigger updated the physical projection.

The final establishment name became:

```text
Updated During Rebuild
```

**Result: Passed**

This demonstrates that the blocking rebuild can maintain a consistent input set and allow ordinary readers to continue seeing committed projection data. It also demonstrates that the rebuild can delay replication writes until its locks are released.

## Recovery After a Temporary Replication Interruption

The next experiment tested whether the subscription and projection could recover automatically after replication was temporarily paused.

### Pause the subscription

On the **read database**:

```sql
ALTER SUBSCRIPTION epr_spike_subscription DISABLE;
```

Verify that it is disabled:

```sql
SELECT subname, subenabled
FROM pg_subscription
WHERE subname = 'epr_spike_subscription';
```

Expected value:

```text
subenabled = f
```

### Make a source change

While replication is paused, update the establishment on the **source database**:

```sql
UPDATE public.spike_establishment
SET name = 'Updated While Replication Paused'
WHERE id = 1;
```

The source transaction completes normally.

Querying the read-side raw table and physical projection at this stage shows the previous value, because the change has not yet been applied by the subscriber.

### Resume the subscription

On the **read database**:

```sql
ALTER SUBSCRIPTION epr_spike_subscription ENABLE;
```

Check the subscription status:

```sql
SELECT
    subname,
    pid,
    received_lsn,
    latest_end_lsn
FROM pg_stat_subscription
WHERE subname = 'epr_spike_subscription';
```

The subscription resumes consuming changes from its retained replication position.

### Verify recovery

Query both the raw replicated table and the physical projection:

```sql
SELECT id, urn, name
FROM public.spike_establishment
WHERE id = 1;

SELECT urn, name
FROM public.spike_establishment_read_table
WHERE urn = 100001;
```

Both returned:

```text
Updated While Replication Paused
```

**Result: Passed**

The subscription replayed the change made during the pause, and the existing replica trigger automatically updated the physical denormalised row. No manual rebuild or subscription recreation was required.

## Rebuild Versus Recovery

These experiments demonstrate two different mechanisms:

```text
REBUILD
Raw replicated tables
        ↓
Re-run the complete projection query
        ↓
Replace the physical read-model contents
```

```text
RECOVERY
Subscription resumes
        ↓
Previously missed changes are applied
        ↓
Replica triggers execute
        ↓
Affected physical rows are updated
```

A rebuild regenerates the projection from the data currently available on the read database. It does not, by itself, recover source changes that the subscriber has not yet received.

Recovery depends on the subscription being able to continue from its retained replication position and the required WAL still being available.

## Findings

The spike has demonstrated that:

* The physical projection can be rebuilt transactionally from normalised replicated tables.
* The rebuild can be encapsulated in a reusable stored procedure.
* A blocking rebuild can prevent concurrent raw-table writes while producing a consistent projection.
* Ordinary readers can continue to see previously committed data during the rebuild transaction.
* A temporary subscription interruption can recover automatically when replication resumes.
* Replica triggers continue to maintain the physical projection as missed changes are replayed.
* A manual rebuild is not required for every temporary replication outage.

## Production Considerations

The rebuild procedure is a working prototype, not yet a production-ready online rebuild.

The main limitations are:

* **Replication lag:** raw-table locks prevent the subscriber from applying writes while the rebuild is running.
* **Scale:** deleting and reinserting a large projection may generate substantial WAL, consume resources and take significant time.
* **Locking and deadlocks:** lock acquisition order, timeouts and concurrent maintenance operations require further review.
* **Validation:** a production rebuild should validate row counts and data integrity before treating the result as complete.
* **Model assumptions:** the current projection assumes one site per establishment and uses inner joins that exclude incomplete relationships.
* **Recovery limits:** prolonged outages may cause WAL growth, storage pressure or replication-slot invalidation.
* **Deployment:** projection schema changes, function changes and rebuilds need a controlled migration and release process.

A production-scale online rebuild may instead use a shadow table, populate it separately, validate it, and perform a controlled cutover. That approach has not yet been implemented or proven in this spike.

## Next Investigation

The next phase should focus on production suitability rather than adding more basic trigger examples. In particular, it should investigate replication-slot health and lag, schema-change deployment, representative performance, and whether a PostgreSQL-only projection remains preferable to an external CDC or application-driven mechanism.
