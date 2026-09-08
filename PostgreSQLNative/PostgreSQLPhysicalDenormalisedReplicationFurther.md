# PostgreSQL Physical Denormalised Replication — Related Tables

## Goal

Extend the trigger-maintained physical read model so that changes to related normalised tables also update the denormalised projection.

The previous experiment proved that changes to `spike_establishment` could automatically rebuild its physical read-model row. This stage extends that behaviour to sites and local authorities.

Every table whose changes can affect the denormalised result must be accounted for by the projection mechanism. This does not necessarily require a separate function for every table, but in this spike each relevant table has a small trigger function that identifies the affected establishments and calls the shared `refresh_spike_establishment` function.

```text
spike_establishment ────────┐
                           │
spike_site ────────────────┼──→ identify affected establishment IDs
                           │                 │
spike_local_authority ─────┘                 ▼
                              refresh_spike_establishment(id)
                                            │
                                            ▼
                              spike_establishment_read_table
```

## Maintain the Projection When a Site Changes

A change to a site may affect the address stored in the denormalised establishment row. The site trigger determines the associated establishment ID and invokes the shared refresh function.

Create the following trigger function on the **read database**:

```sql
CREATE OR REPLACE FUNCTION public.project_spike_site_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM public.refresh_spike_establishment(OLD.establishment_id);
        RETURN OLD;
    END IF;

    IF TG_OP = 'UPDATE'
       AND OLD.establishment_id IS DISTINCT FROM NEW.establishment_id THEN
        PERFORM public.refresh_spike_establishment(OLD.establishment_id);
    END IF;

    PERFORM public.refresh_spike_establishment(NEW.establishment_id);

    RETURN NEW;
END;
$$;
```

For an `INSERT`, the function refreshes the new establishment. For an `UPDATE`, it refreshes the associated establishment and also refreshes the old establishment if the site has moved. For a `DELETE`, it refreshes the establishment that previously owned the site.

The shared refresh function contains the actual join and projection logic, so the site trigger does not duplicate it.

### Attach and enable the site trigger

```sql
CREATE TRIGGER spike_site_projection_trigger
AFTER INSERT OR UPDATE OR DELETE
ON public.spike_site
FOR EACH ROW
EXECUTE FUNCTION public.project_spike_site_change();
```

Enable the trigger for changes applied by logical replication:

```sql
ALTER TABLE public.spike_site
ENABLE REPLICA TRIGGER spike_site_projection_trigger;
```

The `ENABLE REPLICA` command is required because ordinary triggers do not fire for changes applied by the logical replication worker. It only needs to be run when the trigger is created or recreated; replacing the function body does not reset the trigger's enabled mode.

### Verify the site trigger

The trigger mode can be checked using:

```sql
SELECT
    tgname,
    tgenabled
FROM pg_trigger
WHERE tgrelid = 'public.spike_site'::regclass
  AND NOT tgisinternal;
```

The expected value is `R`, indicating that the trigger is enabled for replica-mode changes.

## Maintain the Projection When a Local Authority Changes

A local authority may be referenced by multiple establishments. Therefore, one change to an authority name may require several denormalised rows to be refreshed.

The following function finds all establishments referencing the changed authority and refreshes each one.

Create it on the **read database**:

```sql
CREATE OR REPLACE FUNCTION public.project_spike_local_authority_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_establishment_id integer;
BEGIN
    IF TG_OP = 'DELETE' THEN
        FOR v_establishment_id IN
            SELECT id
            FROM public.spike_establishment
            WHERE local_authority_id = OLD.id
        LOOP
            PERFORM public.refresh_spike_establishment(v_establishment_id);
        END LOOP;

        RETURN OLD;
    END IF;

    FOR v_establishment_id IN
        SELECT id
        FROM public.spike_establishment
        WHERE local_authority_id = NEW.id
    LOOP
        PERFORM public.refresh_spike_establishment(v_establishment_id);
    END LOOP;

    RETURN NEW;
END;
$$;
```

The `FOR ... IN SELECT ... LOOP` statement iterates through the establishments associated with the authority.

For example:

```text
Cardiff Local Authority
        │
        ├── Establishment 1
        ├── Establishment 2
        └── Establishment 3
                  │
                  ▼
    Refresh each affected read-model row
```

This is a simple row-by-row implementation for the spike. A production implementation may need a more efficient set-based or batched approach when an authority is referenced by a large number of establishments.

### Attach and enable the authority trigger

```sql
CREATE TRIGGER spike_local_authority_projection_trigger
AFTER INSERT OR UPDATE OR DELETE
ON public.spike_local_authority
FOR EACH ROW
EXECUTE FUNCTION public.project_spike_local_authority_change();
```

Enable it for replication-applied changes:

```sql
ALTER TABLE public.spike_local_authority
ENABLE REPLICA TRIGGER spike_local_authority_projection_trigger;
```

The trigger must be created before it can be enabled. As with the site trigger, the `ALTER TABLE` command changes the trigger's execution mode rather than modifying the function.

## Test a Local Authority Update

Update the authority name on the **source database**:

```sql
UPDATE public.spike_local_authority
SET name = 'Cardiff Council Updated'
WHERE id = 1;
```

Then query the physical projection on the **read database**:

```sql
SELECT *
FROM public.spike_establishment_read_table;
```

Result:

```text
  urn   |          name           | local_authority_name    | address_line_1 |    town     | postcode
--------+-------------------------+-------------------------+----------------+-------------+----------
 100001 | Trigger Projection Test | Cardiff Council Updated | 1 Test Street  | Cardiff Bay | CF10 1AA
(1 row)
```

**Result: Passed**

The authority name changed in the denormalised table without a manual refresh.

## Test One Authority Updating Multiple Establishments

Create a second establishment on the **source database**, referencing the same local authority:

```sql
INSERT INTO public.spike_establishment (
    id, urn, name, local_authority_id
)
VALUES (
    2, 100002, 'Second Test School', 1
);
```

Create its site:

```sql
INSERT INTO public.spike_site (
    id, establishment_id, address_line_1, town, postcode
)
VALUES (
    2, 2, '2 Test Street', 'Cardiff', 'CF10 2BB'
);
```

The establishment and site triggers create and maintain the second physical projection row automatically.

Query the **read database**:

```sql
SELECT *
FROM public.spike_establishment_read_table;
```

Result:

```text
  urn   |          name           | local_authority_name    | address_line_1 |    town     | postcode
--------+-------------------------+-------------------------+----------------+-------------+----------
 100001 | Trigger Projection Test | Cardiff Council Updated | 1 Test Street  | Cardiff Bay | CF10 1AA
 100002 | Second Test School      | Cardiff Council Updated | 2 Test Street  | Cardiff     | CF10 2BB
(2 rows)
```

Now update the shared authority on the **source**:

```sql
UPDATE public.spike_local_authority
SET name = 'Cardiff Authority Renamed'
WHERE id = 1;
```

Query the physical projection again:

```sql
SELECT *
FROM public.spike_establishment_read_table;
```

Result:

```text
  urn   |          name           |  local_authority_name    | address_line_1 |    town     | postcode
--------+-------------------------+--------------------------+----------------+-------------+----------
 100001 | Trigger Projection Test | Cardiff Authority Renamed | 1 Test Street  | Cardiff Bay | CF10 1AA
 100002 | Second Test School      | Cardiff Authority Renamed | 2 Test Street  | Cardiff     | CF10 2BB
(2 rows)
```

**Result: Passed**

A single update to a shared local authority successfully caused both affected denormalised establishment rows to be rebuilt.

## Current Architecture

```text
NORMALISED SOURCE
        │
        │ PostgreSQL logical replication
        ▼
NORMALISED READ COPY
        │
        ├── Establishment trigger
        ├── Site trigger
        └── Local authority trigger
                    │
                    ▼
       Identify affected establishment IDs
                    │
                    ▼
       Shared projection refresh function
                    │
                    ▼
       PHYSICALLY STORED DENORMALISED TABLE
```

## Findings

The experiment demonstrates that subscriber-side triggers can maintain a physical denormalised read model when changes occur across multiple related source tables.

The approach supports both direct changes to an establishment and changes to related entities. It also supports one-to-many fan-out, where a change to a shared local authority affects several establishments.

The design reuses a single projection function, while table-specific trigger functions determine which establishment rows need refreshing.

However, several limitations remain before this could be considered production-ready. The current projection assumes one site per establishment, uses inner joins that exclude incomplete relationships, and performs row-by-row refreshes for shared authority changes. It has not yet been tested for all deletion, reassignment, primary-key change, or large-scale update scenarios.

## Next Investigation

The next stage should move beyond the basic proof of concept and assess production suitability, including:

* Initial population and rebuilding the projection safely.
* Replication lag and the performance impact of large fan-out updates.
* Failure recovery and the effect of projection errors on the subscription.
* Schema changes and deployment ordering.
* Comparison with an external CDC or application-driven projection mechanism.

These findings will help determine whether subscriber-side triggers are a suitable production approach or whether a separate projection service would provide a better balance of reliability, performance, and maintainability.
