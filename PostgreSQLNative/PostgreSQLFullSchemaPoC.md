# Full-schema PostgreSQL replication PoC

**Project:** DfE Education Provider Registry  
**Database:** PostgreSQL 17  
**Status:** Technical feasibility demonstrated

## Purpose and conclusion

This PoC investigates native PostgreSQL logical replication as a mechanism for supplying a denormalised EPR read model. It builds on the earlier toy spike and uses the complete initialization schema from the [education-provider-registry-data repository](https://github.com/DFE-Digital/education-provider-registry-data).

The full relational schema has been successfully replicated, and a representative physical read model has been created and maintained through replica-side triggers. The PoC demonstrates that native PostgreSQL logical replication can support denormalised read models, including related-data changes and reference-data fan-out. Extending the projection to additional EPR modules is implementation work rather than a remaining feasibility concern.

This is a feasibility PoC, not a production deployment design. The remaining spike work is EF Core migration/deployment integration, proportionate production considerations, and a comparison with alternative approaches.

## Environment and isolation

| Component | Docker container | Windows port | Database |
| --- | --- | --- | --- |
| Source | `epr-postgres-source` | `15432` | `epr_real_source` |
| Read | `epr-postgres-read` | `15433` | `epr_real_read` |

The existing toy databases, `epr_spike_publication`, and `epr_spike_subscription` are retained. The real-schema PoC uses separate databases and replication objects on the same two PostgreSQL servers.

**Important:** Always check the active database before running SQL. The default `postgres` database is not the real-schema database. Use `\c epr_real_source` on the source or `\c epr_real_read` on the read server. The prompt should change accordingly.

## 1. Create the databases

Open separate PowerShell terminals for the source and read containers. Connect to the maintenance database to create the new databases.

**Source — PowerShell:**

```powershell
docker exec -it epr-postgres-source psql -U postgres -d postgres
```

```sql
CREATE DATABASE epr_real_source;
```

**Read — PowerShell:**

```powershell
docker exec -it epr-postgres-read psql -U postgres -d postgres
```

```sql
CREATE DATABASE epr_real_read;
```

The two new databases isolate this work from the existing toy spike. The source and read containers remain running throughout.

## 2. Apply the complete initialization schema

Save the supplied initialization script as `epr-real-schema.sql` in the spike folder. The script defines the `ref` and `core` schemas, all tables, foreign keys (including deferred relationships), and indexes. Apply the same file to both new databases because logical replication does not replicate table definitions.

**PowerShell — from the folder containing the SQL file:**

```powershell
docker cp .\epr-real-schema.sql epr-postgres-source:/tmp/epr-real-schema.sql
docker cp .\epr-real-schema.sql epr-postgres-read:/tmp/epr-real-schema.sql

docker exec -it epr-postgres-source psql -U postgres -d epr_real_source -v ON_ERROR_STOP=1 -f /tmp/epr-real-schema.sql
docker exec -it epr-postgres-read psql -U postgres -d epr_real_read -v ON_ERROR_STOP=1 -f /tmp/epr-real-schema.sql
```

`docker cp` copies the file into each container. `-f` executes it, while `ON_ERROR_STOP=1` stops `psql` at the first SQL error. Both schema installations completed successfully.

**Source and read — connect to the respective database:**

```sql
-- Source psql session
\c epr_real_source
```

```sql
-- Read psql session
\c epr_real_read
```

Use `\conninfo` or `SELECT current_database();` whenever you need to confirm the connection. `\dn` lists the schemas in the current database.

## 3. Configure the source publication

**Run the following on the source, connected to `epr_real_source`.**

```sql
CREATE PUBLICATION epr_real_publication
FOR ALL TABLES;
```

`FOR ALL TABLES` publishes the user tables in this database and includes subsequently created tables. It does not publish tables in other databases. The publication is separate from the toy publication.

Verify that the publication exists and inspect its table membership:

```sql
SELECT pubname, puballtables
FROM pg_publication
WHERE pubname = 'epr_real_publication';
```

```sql
SELECT schemaname, tablename
FROM pg_publication_tables
WHERE pubname = 'epr_real_publication'
ORDER BY schemaname, tablename;
```

The complete initialization schema is included. The recorded synchronisation check later in this runbook shows 33 tables ready.

### Replication login

Create a dedicated source-side login for this PoC. This is not another PostgreSQL instance: it is the identity used by the read database to connect to the source. The existing toy subscription uses `postgres`; a separate identity is useful for demonstrating a more realistic setup but is not necessary to prove replication.

**Source server — create the role once:**

```sql
CREATE ROLE epr_real_replicator
WITH LOGIN REPLICATION;
```

Set its password interactively in `psql`:

```text
\password epr_real_replicator
```

**Source database — ensure the connection is `epr_real_source` before granting schema permissions:**

```sql
GRANT CONNECT ON DATABASE epr_real_source TO epr_real_replicator;

GRANT USAGE ON SCHEMA ref, core TO epr_real_replicator;
GRANT SELECT ON ALL TABLES IN SCHEMA ref, core
TO epr_real_replicator;
```

PostgreSQL roles are server-wide, but schema and table privileges are database-specific. `REPLICATION` permits replication connections; `CONNECT`, `USAGE`, and `SELECT` provide the access needed to connect and copy the existing table data. The grants must be executed on the source, not the read database.

## 4. Create the subscription

**Run on the read server, connected to `epr_real_read`.** The destination schema must already exist. The subscription connects to the source using the internal Docker hostname `postgres-source` and port `5432`, not the Windows-mapped port `15432`.

Replace the placeholder with the password set for `epr_real_replicator`. Do not commit a real password to the repository.

```sql
CREATE SUBSCRIPTION epr_real_subscription
CONNECTION 'host=postgres-source port=5432 dbname=epr_real_source user=epr_real_replicator password=<replication-password>'
PUBLICATION epr_real_publication
WITH (
    slot_name = 'epr_real_slot',
    copy_data = true
);
```

`slot_name` creates a separate replication slot on the source. `copy_data = true` copies existing rows before normal change streaming. The subscription is created in the read database and uses the source publication.

### Check the subscription configuration

**Read database:**

```sql
SELECT
    subname,
    subenabled,
    subslotname
FROM pg_subscription
WHERE subname = 'epr_real_subscription';
```

Recorded result:

| Subscription | Enabled | Slot |
| --- | --- | --- |
| `epr_real_subscription` | `t` | `epr_real_slot` |

`pg_subscription` stores the configuration. `subenabled = t` means the subscription is enabled; the slot tracks the subscriber's position in the source WAL.

### Check the replication worker

**Read database:**

```sql
SELECT
    subname,
    pid,
    received_lsn,
    latest_end_lsn
FROM pg_stat_subscription
WHERE subname = 'epr_real_subscription';
```

The recorded result showed a running worker (`pid = 999`) and matching received and reported WAL positions (`0/2068DF0`). These values are observations from that run, not values to expect on subsequent runs.

`pid` is the worker's process ID. An LSN (Log Sequence Number) is a position in the PostgreSQL write-ahead log. Matching positions are consistent with the worker being caught up at that moment, but do not independently prove that every table has finished its initial copy.

### Confirm table synchronisation

**Read database:**

```sql
SELECT
    sr.srrelid::regclass AS table_name,
    sr.srsubstate AS state
FROM pg_subscription_rel AS sr
JOIN pg_subscription AS s
    ON s.oid = sr.srsubid
WHERE s.subname = 'epr_real_subscription'
ORDER BY table_name;
```

For a concise summary:

```sql
SELECT
    sr.srsubstate AS state,
    COUNT(*) AS table_count
FROM pg_subscription_rel AS sr
JOIN pg_subscription AS s
    ON s.oid = sr.srsubid
WHERE s.subname = 'epr_real_subscription'
GROUP BY sr.srsubstate
ORDER BY sr.srsubstate;
```

Recorded result:

| State | Table count |
| --- | ---: |
| `r` | 33 |

State `r` means ready for normal replication. All 33 tables reached the ready state. This is the complete relational-schema synchronisation proof, distinct from the physical read-model projection.

## 5. Prepare representative relational test data

The initialization script creates the schema but does not supply seed records. On a fresh PoC database, the following single statement creates a synthetic establishment with its required reference data, provision, site, and authority. This is included so the runbook can be reproduced from an empty database; it is not intended to be rerun against the populated PoC.

**Source database — `epr_real_source`:**

```sql
WITH family AS (
    INSERT INTO ref.establishment_family (code, name)
    VALUES ('POC_FAMILY', 'PoC School Family')
    RETURNING establishment_family_id
),
establishment_type AS (
    INSERT INTO ref.establishment_type (
        establishment_family_id, code, name, is_school
    )
    SELECT establishment_family_id, 'POC_TYPE', 'PoC Community School', TRUE
    FROM family
    RETURNING establishment_type_id
),
establishment_status AS (
    INSERT INTO ref.establishment_status (code, name)
    VALUES ('POC_OPEN', 'Open')
    RETURNING establishment_status_id
),
phase_group AS (
    INSERT INTO ref.education_phase_group (code, name)
    VALUES ('POC_PHASE_GROUP', 'PoC School Phases')
    RETURNING education_phase_group_id
),
education_phase AS (
    INSERT INTO ref.education_phase (
        education_phase_group_id, code, name
    )
    SELECT education_phase_group_id, 'POC_PRIMARY', 'Primary'
    FROM phase_group
    RETURNING education_phase_id
),
establishment AS (
    INSERT INTO core.establishment (
        urn, uid, name, establishment_number,
        establishment_type_id, establishment_status_id
    )
    SELECT
        'POC100001',
        'POC-UID-001',
        'PoC Riverside Primary School',
        '9001',
        et.establishment_type_id,
        es.establishment_status_id
    FROM establishment_type AS et
    CROSS JOIN establishment_status AS es
    RETURNING establishment_id, urn, name
),
provision AS (
    INSERT INTO core.establishment_provision (
        establishment_id, education_phase_id
    )
    SELECT e.establishment_id, ep.education_phase_id
    FROM establishment AS e
    CROSS JOIN education_phase AS ep
    RETURNING establishment_id
),
site AS (
    INSERT INTO core.site (
        establishment_id, name, address_line_1,
        town, county, postcode
    )
    SELECT
        establishment_id,
        'Main Site',
        '1 Example Road',
        'Cardiff',
        'South Glamorgan',
        'CF10 1AA'
    FROM establishment
    RETURNING site_id
),
authority AS (
    INSERT INTO core.establishment_authority (
        establishment_id, authority_code, authority_name
    )
    SELECT establishment_id, 'POC-LA', 'PoC Local Authority'
    FROM establishment
    RETURNING establishment_authority_id
)
SELECT
    e.establishment_id,
    e.urn,
    e.name
FROM establishment AS e;
```

Each data-modifying CTE uses `RETURNING` to pass generated IDs to dependent inserts. The statement is atomic, so a failure rolls back all its inserts. It uses the actual relationships defined by the supplied schema.

**Read database — verify the related data arrived:**

```sql
SELECT
    e.establishment_id,
    e.urn,
    e.name,
    et.name AS establishment_type,
    es.name AS establishment_status,
    ep.name AS education_phase,
    s.address_line_1,
    s.town,
    s.postcode,
    ea.authority_name
FROM core.establishment AS e
JOIN ref.establishment_type AS et
    ON et.establishment_type_id = e.establishment_type_id
JOIN ref.establishment_status AS es
    ON es.establishment_status_id = e.establishment_status_id
LEFT JOIN core.establishment_provision AS p
    ON p.establishment_id = e.establishment_id
LEFT JOIN ref.education_phase AS ep
    ON ep.education_phase_id = p.education_phase_id
LEFT JOIN core.site AS s
    ON s.establishment_id = e.establishment_id
LEFT JOIN core.establishment_authority AS ea
    ON ea.establishment_id = e.establishment_id
WHERE e.urn = 'POC100001';
```

**Recorded result:** The Riverside establishment and its related type, status, phase, site, and authority arrived successfully. This confirmed replication through the real foreign-key relationships before introducing the physical projection.

## 6. Create the physical read model

All objects in this section are created **only on `epr_real_read`**. The source continues to own the relational data; the read database maintains the projection locally.

The physical table has one row per establishment. It contains common scalar search fields and JSONB arrays for the one-to-many site and authority relationships. The source schema does not define a primary site or authority, so the projection preserves all related records rather than choosing one arbitrarily.

### Create the table

```sql
CREATE SCHEMA IF NOT EXISTS read_model;
CREATE TABLE read_model.establishment (
    establishment_id BIGINT PRIMARY KEY,
    urn TEXT,
    uid TEXT,
    name TEXT NOT NULL,
    establishment_number TEXT,
    establishment_type_id BIGINT,
    establishment_type_name TEXT,
    establishment_status_id BIGINT,
    establishment_status_name TEXT,
    education_phase_id BIGINT,
    education_phase_name TEXT,
    sites JSONB NOT NULL DEFAULT '[]'::jsonb,
    authorities JSONB NOT NULL DEFAULT '[]'::jsonb
);
```

### Create the projection function

The function refreshes one establishment from the current replicated relational data. It inserts a missing row, updates an existing row, or deletes the projection if its parent establishment no longer exists.

The separate JSON aggregations avoid multiplying sites by authorities when both relationships contain multiple rows. Every table reference is schema-qualified, which is important because PostgreSQL 17 logical replication workers use a restricted `search_path`.

**Read database:**

```sql
CREATE OR REPLACE FUNCTION read_model.refresh_establishment(
    p_establishment_id BIGINT
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM core.establishment AS e
        WHERE e.establishment_id = p_establishment_id
    ) THEN
        DELETE FROM read_model.establishment
        WHERE establishment_id = p_establishment_id;
        RETURN;
    END IF;
    INSERT INTO read_model.establishment (
        establishment_id,
        urn,
        uid,
        name,
        establishment_number,
        establishment_type_id,
        establishment_type_name,
        establishment_status_id,
        establishment_status_name,
        education_phase_id,
        education_phase_name,
        sites,
        authorities
    )
    SELECT
        e.establishment_id,
        e.urn,
        e.uid,
        e.name,
        e.establishment_number,
        e.establishment_type_id,
        et.name,
        e.establishment_status_id,
        es.name,
        p.education_phase_id,
        ep.name,
        COALESCE(
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'site_id', s.site_id,
                        'name', s.name,
                        'address_line_1', s.address_line_1,
                        'address_line_2', s.address_line_2,
                        'town', s.town,
                        'county', s.county,
                        'postcode', s.postcode
                    )
                    ORDER BY s.site_id
                )
                FROM core.site AS s
                WHERE s.establishment_id = e.establishment_id
            ),
            '[]'::jsonb
        ),
        COALESCE(
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'establishment_authority_id',
                            ea.establishment_authority_id,
                        'authority_code', ea.authority_code,
                        'authority_name', ea.authority_name
                    )
                    ORDER BY ea.establishment_authority_id
                )
                FROM core.establishment_authority AS ea
                WHERE ea.establishment_id = e.establishment_id
            ),
            '[]'::jsonb
        )
    FROM core.establishment AS e
    JOIN ref.establishment_type AS et
        ON et.establishment_type_id = e.establishment_type_id
    JOIN ref.establishment_status AS es
        ON es.establishment_status_id = e.establishment_status_id
    LEFT JOIN core.establishment_provision AS p
        ON p.establishment_id = e.establishment_id
    LEFT JOIN ref.education_phase AS ep
        ON ep.education_phase_id = p.education_phase_id
    WHERE e.establishment_id = p_establishment_id
    ON CONFLICT (establishment_id)
    DO UPDATE SET
        urn = EXCLUDED.urn,
        uid = EXCLUDED.uid,
        name = EXCLUDED.name,
        establishment_number = EXCLUDED.establishment_number,
        establishment_type_id = EXCLUDED.establishment_type_id,
        establishment_type_name = EXCLUDED.establishment_type_name,
        establishment_status_id = EXCLUDED.establishment_status_id,
        establishment_status_name = EXCLUDED.establishment_status_name,
        education_phase_id = EXCLUDED.education_phase_id,
        education_phase_name = EXCLUDED.education_phase_name,
        sites = EXCLUDED.sites,
        authorities = EXCLUDED.authorities;
END;
$$;
```

### Build the initial projection

**Read database:**

```sql
SELECT read_model.refresh_establishment(establishment_id)
FROM core.establishment;
```

For the small PoC dataset, calling the function once per establishment is sufficient. Inspect the resulting physical row:

```sql
SELECT
    establishment_id,
    urn,
    name,
    establishment_type_name,
    establishment_status_name,
    education_phase_name,
    jsonb_pretty(sites) AS sites,
    jsonb_pretty(authorities) AS authorities
FROM read_model.establishment;
```

**Recorded result:** `POC100001` produced a single physical row containing the Riverside school, its type (`PoC Community School`), status (`Open`), phase (`Primary`), the Main Site address, and the local authority. The JSON arrays each contained one object.

## 7. Maintain the projection with replica triggers

The first set of triggers covers the parent establishment and two one-to-many relationships. This provides the direct-change and related-data tests needed for the real-schema proof.

### Shared trigger function

**Read database:**

```sql
CREATE OR REPLACE FUNCTION read_model.refresh_establishment_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM read_model.refresh_establishment(OLD.establishment_id);
        RETURN OLD;
    END IF;
    IF TG_OP = 'UPDATE'
       AND OLD.establishment_id IS DISTINCT FROM NEW.establishment_id THEN
        PERFORM read_model.refresh_establishment(OLD.establishment_id);
    END IF;
    PERFORM read_model.refresh_establishment(NEW.establishment_id);
    RETURN NEW;
END;
$$;
```

`TG_OP` is PostgreSQL's built-in trigger variable identifying INSERT, UPDATE, or DELETE. The function uses `OLD` for deleted rows and `NEW` for inserted or updated rows. If an UPDATE moves a child record between establishments, both the old and new parent projections are refreshed.

### Attach the triggers

**Read database:**

```sql
CREATE TRIGGER refresh_establishment
AFTER INSERT OR UPDATE OR DELETE ON core.establishment
FOR EACH ROW
EXECUTE FUNCTION read_model.refresh_establishment_trigger();
ALTER TABLE core.establishment
ENABLE REPLICA TRIGGER refresh_establishment;
CREATE TRIGGER refresh_establishment_from_site
AFTER INSERT OR UPDATE OR DELETE ON core.site
FOR EACH ROW
EXECUTE FUNCTION read_model.refresh_establishment_trigger();
ALTER TABLE core.site
ENABLE REPLICA TRIGGER refresh_establishment_from_site;
CREATE TRIGGER refresh_establishment_from_authority
AFTER INSERT OR UPDATE OR DELETE ON core.establishment_authority
FOR EACH ROW
EXECUTE FUNCTION read_model.refresh_establishment_trigger();
ALTER TABLE core.establishment_authority
ENABLE REPLICA TRIGGER refresh_establishment_from_authority;
```

`ENABLE REPLICA TRIGGER` is essential: ordinary triggers do not fire for changes applied by the logical replication worker. These triggers execute on the read database when replicated rows are applied, not when the original write occurs on the source.

The refresh function is invoked within the apply transaction. A projection-function error can therefore prevent that transaction from applying and block replication progress until the problem is corrected. The restricted `search_path` issue was previously observed and resolved in the toy spike by schema-qualifying table and helper-function references.

## 8. Prove related-data change propagation

### Test A — Update an existing site

**Source database:**

```sql
UPDATE core.site
SET
    address_line_1 = '25 Updated Road',
    postcode = 'CF10 2BB'
WHERE establishment_id = (
    SELECT establishment_id
    FROM core.establishment
    WHERE urn = 'POC100001'
);
```

The site update should replicate and invoke the `core.site` replica trigger, which refreshes the physical establishment row.

**Read database — verify:**

```sql
SELECT
    urn,
    name,
    jsonb_pretty(sites) AS sites
FROM read_model.establishment
WHERE urn = 'POC100001';
```

**Recorded result:** The projection changed to `25 Updated Road` and `CF10 2BB` without a manual rebuild.

### Test B — Insert a second site

**Source database:**

```sql
INSERT INTO core.site (
    establishment_id,
    name,
    address_line_1,
    town,
    county,
    postcode
)
SELECT
    e.establishment_id,
    'PoC Additional Site',
    '10 Test Lane',
    'Cardiff',
    'South Glamorgan',
    'CF11 9ZZ'
FROM core.establishment AS e
WHERE e.urn = 'POC100001'
RETURNING site_id, establishment_id, name;
```

`RETURNING` displays the generated site ID. The insert targets the establishment by URN rather than assuming its identity value.

**Read database — verify:**

```sql
SELECT
    e.urn,
    jsonb_array_length(e.sites) AS site_count,
    jsonb_pretty(e.sites) AS sites
FROM read_model.establishment AS e
WHERE e.urn = 'POC100001';
```

**Recorded result:** The JSON array contained both the original and additional site, with `site_count = 2`. This proves the one-to-many projection can grow automatically.

### Test C — Delete the additional site

**Source database:**

```sql
DELETE FROM core.site
WHERE name = 'PoC Additional Site'
  AND establishment_id = (
      SELECT establishment_id
      FROM core.establishment
      WHERE urn = 'POC100001'
  )
RETURNING site_id, name;
```

The predicate targets the synthetic additional site only. `RETURNING` confirms which record was removed.

**Read database — verify:**

```sql
SELECT
    e.urn,
    jsonb_array_length(e.sites) AS site_count,
    jsonb_pretty(e.sites) AS sites
FROM read_model.establishment AS e
WHERE e.urn = 'POC100001';
```

**Recorded result:** The additional site disappeared and `site_count` returned to `1`, leaving the original site intact. This proves the DELETE path removes stale related data from the physical projection.

## 9. Prove reference-data fan-out

The existing triggers respond to establishment, site, and authority changes. A change to a shared establishment-type label needs a separate dependency trigger because the establishment rows themselves do not change.

### Create a second establishment sharing the type

**Source database:**

```sql
INSERT INTO core.establishment (
    urn,
    uid,
    name,
    establishment_type_id,
    establishment_status_id
)
SELECT
    'POC100002',
    'POC-UID-002',
    'PoC Hilltop Primary School',
    e.establishment_type_id,
    e.establishment_status_id
FROM core.establishment AS e
WHERE e.urn = 'POC100001'
RETURNING establishment_id, urn, name;
```

The new establishment reuses the first establishment's type and status IDs. The existing establishment trigger creates its physical read-model row.

### Add the reference-data trigger

**Read database:**

```sql
CREATE OR REPLACE FUNCTION read_model.refresh_establishments_for_type()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    -- Refresh every establishment referencing the changed type.
    PERFORM read_model.refresh_establishment(e.establishment_id)
    FROM core.establishment AS e
    WHERE e.establishment_type_id = NEW.establishment_type_id;
    RETURN NEW;
END;
$$;
CREATE TRIGGER refresh_establishments_from_type
AFTER UPDATE ON ref.establishment_type
FOR EACH ROW
EXECUTE FUNCTION read_model.refresh_establishments_for_type();
ALTER TABLE ref.establishment_type
ENABLE REPLICA TRIGGER refresh_establishments_from_type;
```

This trigger finds every establishment using the changed type and calls the existing refresh function for each one. It covers UPDATE for this specific fan-out proof; it is not a complete dependency implementation for every reference table.

### Update the shared type

**Source database:**

```sql
UPDATE ref.establishment_type
SET name = 'PoC Community Primary School - Updated'
WHERE code = 'POC_TYPE'
RETURNING establishment_type_id, code, name;
```

The single reference-data UPDATE is replicated to the read database. The replica trigger refreshes both establishments using that type.

**Read database — verify:**

```sql
SELECT
    urn,
    name,
    establishment_type_id,
    establishment_type_name
FROM read_model.establishment
WHERE urn IN ('POC100001', 'POC100002')
ORDER BY urn;
```

**Recorded result:**

| URN | Establishment | Type ID | Projected type name |
| --- | --- | ---: | --- |
| `POC100001` | PoC Riverside Primary School | 1 | PoC Community Primary School - Updated |
| `POC100002` | PoC Hilltop Primary School | 1 | PoC Community Primary School - Updated |

Both physical rows updated from one reference-table change, without directly updating either establishment.

## 10. Findings and scope

### Evidence established

| Area | Result |
| --- | --- |
| Full relational schema | Complete initialization schema installed on source and read; 33 tables synchronised and ready. |
| Initial data copy | Synthetic establishment and related foreign-key records arrived successfully. |
| Physical projection | One row per establishment containing scalar fields and JSONB related data. |
| Related UPDATE | Site address changes refreshed the physical row. |
| One-to-many INSERT/DELETE | Adding and removing a second site changed the JSON array correctly. |
| Reference fan-out | One shared type-label change refreshed two establishments. |
| Earlier toy spike | Initial sync, INSERT/UPDATE/DELETE, views, materialised views, replica triggers, related-table and authority fan-out, transactional rebuild, and interruption/recovery were proved. |
| PostgreSQL 17 behaviour | Restricted replication-worker `search_path` requires schema-qualified references; a failing projection trigger can block apply. |

### What the result means

Native logical replication supplies the relational change stream, while replica-side functions and triggers maintain the read-optimised representation. The PoC demonstrates technical feasibility for EPR's denormalised read-model requirement.

The physical projection currently contains establishment identifiers/name, type, status, education phase, sites, and authorities. The full source schema is replicated, but other modules have not been added to this particular projection. That distinction is about the extent of the example, not a reason to continue implementing every module as part of the feasibility spike.

For an actual implementation, each projected field needs its dependency mapping. For example, a phase-label change would require a phase fan-out trigger, and provision changes would need to refresh their establishment. The current PoC does not claim those additional triggers have been written or tested.

### Remaining spike work

1. **EF Core migrations and deployment integration:** Determine how the source and read schemas evolve, how read-model SQL is deployed, and how publication/subscription changes fit into the existing pipeline.
2. **Azure and operational considerations:** Document the required logical replication configuration, identities, connectivity, slot/WAL retention, monitoring, failure recovery, and schema-change coordination proportionately.
3. **Alternatives comparison:** Compare native logical replication with CDC, ETL/ELT, and application-driven approaches against the EPR requirements. The working PoC is evidence for the native option, not a decision that alternatives are automatically unsuitable.

No additional real-schema module implementation is required merely to establish the mechanism's feasibility.

## Reproduction notes

The setup sections are intended for a fresh pair of PoC databases. The CREATE DATABASE, CREATE ROLE, publication, subscription, and trigger statements are not a repeatedly executable deployment script. Do not rerun them against the existing completed PoC without checking what already exists.

The synthetic seed uses unique codes and URNs and is intended for a fresh dataset. The subsequent test mutations intentionally change that dataset. On an existing installation, inspect the current records rather than blindly replaying every insert.

Keep real replication credentials out of committed SQL. The example connection string contains a placeholder; a deployment implementation should obtain credentials from the approved secret-management mechanism. The original schema file remains the source of truth for the relational definitions.
