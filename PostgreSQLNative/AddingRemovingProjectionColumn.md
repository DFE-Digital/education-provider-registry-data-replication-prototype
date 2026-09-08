# Adding or removing a projection column

This guide covers changes to `read_model.establishment` in the real-schema spike. The projection is maintained locally on READ, while the underlying `core` tables are populated by PostgreSQL logical replication.

## Add a column from an existing replicated table

Example: add `laestab`, which already exists on `core.establishment` on both servers.

### 1. Add the projection column

On READ (`epr_real_read`):

```sql
ALTER TABLE read_model.establishment
ADD COLUMN laestab TEXT;
```

### 2. Update the refresh function

In `read/08-projection.sql`, update `read_model.refresh_establishment` to include the new field in three places:

* INSERT column list: `laestab`
* Corresponding SELECT expression: `e.laestab`
* ON CONFLICT update: `laestab = EXCLUDED.laestab`

Apply the complete updated `CREATE OR REPLACE FUNCTION` statement on READ.

For an existing installation, do not rerun the whole setup file because it also creates the table. Update its saved CREATE TABLE definition so fresh installations include the new column.

Apply the ALTER TABLE and function replacement in one transaction:

```sql
BEGIN;

ALTER TABLE read_model.establishment
ADD COLUMN laestab TEXT;

-- Apply the complete updated CREATE OR REPLACE FUNCTION here.

COMMIT;
```

If the transaction fails, use `ROLLBACK;`.

### 3. Backfill existing rows

Run the existing rebuild script on READ:

```text
read/11-rebuild.sql
```

The rebuild calls the refresh function, so there is no second mapping to maintain. It briefly blocks replication writes while rebuilding.

### 4. Test replication

On SOURCE (`epr_real_source`):

```sql
UPDATE core.establishment
SET laestab = 'POC-LAESTAB'
WHERE urn = 'POC100001';
```

Then check READ, allowing time for replication:

```sql
SELECT urn, laestab
FROM read_model.establishment
WHERE urn = 'POC100001';
```

The existing establishment trigger already handles this update. No new trigger or subscription change is required.

### 5. Update verification SQL

Update `tests/13-projection-equality-read.sql` to include the new field. Its expected SELECT compares columns by position, so match the physical projection table order. Since ALTER TABLE appends the column, add it last in the expected SELECT and fresh CREATE TABLE definition.

The refresh function uses an explicit INSERT column list, so that list only needs to match the corresponding SELECT expressions.

## Remove a projection column

Removing a column follows the same process in reverse:

1. Remove the field from application queries and mapping.
2. Remove it from the refresh function's INSERT, SELECT, and ON CONFLICT sections.
3. Apply the function replacement and DROP COLUMN in one transaction.
4. Update the saved CREATE TABLE definition and verification SQL.

```sql
BEGIN;

-- Apply the complete updated CREATE OR REPLACE FUNCTION here.

ALTER TABLE read_model.establishment
DROP COLUMN laestab;

COMMIT;
```

A rebuild is not required when only removing a column, unless the remaining projection logic has also changed.

Removing a projection column does not require removing the source column or changing the subscription.

## When is more work required?

Most projection changes only need the steps above. Additional work is required when the data source or dependencies change.

| Change                                                          | Additional work                                                                                                           |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Add a field from a table already covered by projection triggers | Usually none; extend the refresh function.                                                                                |
| Use a new child table                                           | Add a trigger that refreshes the affected establishment.                                                                  |
| Use a shared reference table                                    | Add a trigger that refreshes every establishment affected by that reference.                                              |
| Add a new source column                                         | Apply a compatible schema change to the raw READ table before SOURCE starts writing the new field. DDL is not replicated. |
| Add a new source table                                          | Create the raw READ table, ensure it is published and subscribed, then add the projection mapping and triggers.           |

### New child-table example

If admissions data is introduced and the table has the same `establishment_id` relationship, the existing trigger helper can be reused:

```sql
CREATE TRIGGER refresh_establishment_from_admissions
AFTER INSERT OR UPDATE OR DELETE
ON core.establishment_admissions
FOR EACH ROW
EXECUTE FUNCTION read_model.refresh_establishment_trigger();

ALTER TABLE core.establishment_admissions
ENABLE REPLICA TRIGGER refresh_establishment_from_admissions;
```

This is not required for `laestab`. The helper handles deletes and refreshes both parents when a child moves. Shared lookup tables need their own fan-out logic.

### Adding a new replicated table

The current `FOR ALL TABLES` publication includes newly created source tables, but the subscription must discover them.

After creating the compatible raw READ table and SOURCE table, and ensuring the replication login has the required SELECT and schema USAGE permissions, run on READ:

```sql
ALTER SUBSCRIPTION epr_real_subscription
REFRESH PUBLICATION;
```

Wait for the new table to reach state `r` in `pg_subscription_rel` before relying on it or rebuilding. Update the spike's hardcoded 33-table synchronisation check if the table count changes.

If the publication uses an explicit table list instead, add the table to that publication first.

## Rules of thumb

* Projection-only changes do not require publication or subscription changes.
* Existing triggers can be reused when they already cover the data dependency.
* Every table that can change a projected value must have a route to refresh the affected establishment.
* Keep table and helper-function references schema-qualified.
* Do not remove a trigger while it still maintains other projection fields.
* Avoid `CASCADE` when dropping columns; inspect dependencies instead.

For this spike, the normal workflow is simply: **change the projection schema, update the refresh function, rebuild if needed, and verify the result.**
