# PostgreSQL Physical Denormalised Replication

## Goal

The next approach is to investigate maintaining a physically stored denormalised table automatically as replicated changes arrive.

Unlike a materialised view, the goal is not to rebuild the entire result whenever data changes. Instead, the projection logic should identify the affected establishment and rebuild only its denormalised row.

```text
NORMALISED READ TABLES

spike_establishment
spike_local_authority
spike_site
       │
       │ projection logic
       ▼
spike_establishment_read_table
       │
       ▼
PHYSICALLY STORED ROW
```

## Create the Physical Read Table

Create the denormalised table on the **read database**:

```sql
CREATE TABLE public.spike_establishment_read_table (
    urn integer PRIMARY KEY,
    name text NOT NULL,
    local_authority_name text NOT NULL,
    address_line_1 text NOT NULL,
    town text,
    postcode text NOT NULL
);
```

This is a normal PostgreSQL table, rather than an ordinary or materialised view. It physically stores the flattened data and can be indexed for read queries.

## Populate the Initial Projection

The existing replicated data must be used to populate the read table before relying on triggers for subsequent changes.

```sql
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
```

Verify the inserted data:

```sql
SELECT * FROM public.spike_establishment_read_table;
```

Example result:

```text
  urn   |        name         | local_authority_name    | address_line_1 |      town       | postcode
--------+---------------------+-------------------------+----------------+-----------------+----------
 100001 | Test School Updated | Cardiff Local Authority | 1 Test Street  | Cardiff Updated | CF10 1AA
```

## Create the Projection Refresh Function

The following function rebuilds the denormalised row for a given establishment ID.

```sql
CREATE OR REPLACE FUNCTION public.refresh_spike_establishment(
    p_establishment_id integer
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_urn integer;
BEGIN
    SELECT urn
    INTO v_urn
    FROM public.spike_establishment
    WHERE id = p_establishment_id;

    IF v_urn IS NULL THEN
        RETURN;
    END IF;

    DELETE FROM public.spike_establishment_read_table
    WHERE urn = v_urn;

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
        ON s.establishment_id = e.id
    WHERE e.id = p_establishment_id;
END;
$$;
```

The function takes an establishment ID, identifies its URN, removes the existing projection row, and inserts the latest flattened result from the replicated tables.

All table references are explicitly schema-qualified with `public.`. This is important because logical replication workers use a restricted search path, so functions executed during replication should not rely on an interactive session's search path.

The function deliberately uses a simple delete-and-insert strategy for the spike. This is easy to understand and verify, although a production implementation may use a more targeted upsert strategy.

## Test the Refresh Function Manually

First, deliberately change the stored projection on the **read database**:

```sql
UPDATE public.spike_establishment_read_table
SET name = 'WRONG VALUE'
WHERE urn = 100001;
```

Verify the change:

```sql
SELECT * FROM public.spike_establishment_read_table;
```

Then invoke the refresh function:

```sql
SELECT public.refresh_spike_establishment(1);
```

Query the physical table again:

```sql
SELECT * FROM public.spike_establishment_read_table;
```

The correct name should be restored from the normalised replicated data.

This proves that the projection function can rebuild an individual establishment's flattened row.

```text
refresh_spike_establishment(1)
        ↓
reads normalised replicated data
        ↓
joins related tables
        ↓
rebuilds physical projection
```

## Create the Establishment Trigger Function

The next step is to invoke the projection function automatically when a replicated establishment changes.

```sql
CREATE OR REPLACE FUNCTION public.project_spike_establishment_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        DELETE FROM public.spike_establishment_read_table
        WHERE urn = OLD.urn;

        RETURN OLD;
    END IF;

    IF TG_OP = 'UPDATE'
       AND OLD.urn IS DISTINCT FROM NEW.urn THEN
        DELETE FROM public.spike_establishment_read_table
        WHERE urn = OLD.urn;
    END IF;

    PERFORM public.refresh_spike_establishment(NEW.id);

    RETURN NEW;
END;
$$;
```

`TG_OP` identifies the operation that fired the trigger, such as `INSERT`, `UPDATE`, or `DELETE`.

`OLD` represents the previous row during an update or delete, while `NEW` represents the new row during an insert or update.

For deletes, the trigger removes the old projection row. For inserts and updates, it calls the refresh function to rebuild the establishment's current flattened representation.

The call is explicitly schema-qualified:

```sql
PERFORM public.refresh_spike_establishment(NEW.id);
```

## Attach the Trigger

Create the trigger on the **read-side** `spike_establishment` table:

```sql
CREATE TRIGGER spike_establishment_projection_trigger
AFTER INSERT OR UPDATE OR DELETE
ON public.spike_establishment
FOR EACH ROW
EXECUTE FUNCTION public.project_spike_establishment_change();
```

This associates the trigger function with inserts, updates, and deletes on the replicated establishment table.

However, normal PostgreSQL triggers do not fire when changes are applied by a logical replication worker.

Enable the trigger specifically for replica-mode sessions:

```sql
ALTER TABLE public.spike_establishment
ENABLE REPLICA TRIGGER spike_establishment_projection_trigger;
```

`ENABLE REPLICA` means the trigger fires when the session is operating in replica mode, such as when a logical replication apply worker applies changes.

This does **not** mean that the entire read database is in replica mode. The subscriber remains a normal writable PostgreSQL database; the replication apply worker uses a specific session execution mode.

## Test Automatic Projection

On the **source database**, update the establishment:

```sql
UPDATE public.spike_establishment
SET name = 'Trigger Projection Test'
WHERE id = 1;
```

The change is published and applied to the read-side normalised table. The replica trigger then invokes the projection function.

On the **read database**, verify the raw replicated row:

```sql
SELECT id, urn, name
FROM public.spike_establishment
WHERE id = 1;
```

Then verify the physical denormalised table:

```sql
SELECT *
FROM public.spike_establishment_read_table;
```

Result:

```text
  urn   |          name           | local_authority_name    | address_line_1 |      town       | postcode
--------+-------------------------+-------------------------+----------------+-----------------+----------
 100001 | Trigger Projection Test | Cardiff Local Authority | 1 Test Street  | Cardiff Updated | CF10 1AA
```

**Result: Passed**

The physical denormalised row was updated automatically without a manual refresh.

## Current Architecture

```text
SOURCE
UPDATE spike_establishment
        ↓
       WAL
        ↓
    publication
        ↓
    subscription
        ↓
READ spike_establishment
        ↓
ENABLE REPLICA trigger
        ↓
refresh_spike_establishment(1)
        ↓
JOIN current normalised data
        ↓
spike_establishment_read_table
```

## Findings

The experiment demonstrates that PostgreSQL logical replication can be combined with subscriber-side replica triggers to maintain a physically stored denormalised table.

Unlike a materialised view refresh, the projection function rebuilds only the affected establishment row rather than recalculating the entire read model.

The approach requires no additional external CDC infrastructure and allows projection logic to remain within PostgreSQL.

However, the projection logic is executed as part of the replication apply transaction. A failure in the trigger or projection function can therefore prevent the subscription from applying changes and cause replication lag until the issue is resolved.

At this stage, only changes to `spike_establishment` are handled automatically.

## Next Investigation

The next step is to add projection triggers for the related tables:

* `spike_site` — refresh the affected establishment when its address changes.
* `spike_local_authority` — refresh all establishments referencing an authority when its name changes.

This will allow the spike to test whether changes across multiple normalised tables can maintain the same physical denormalised read model automatically.
