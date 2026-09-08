# Normalised Replication with PostgreSQL

## Goal

The next stage of the spike is to investigate how PostgreSQL logical replication could support a **denormalised read model**.

The initial approach is to:

1. Create a small normalised schema on the source database.
2. Replicate those tables unchanged to the read database.
3. Investigate mechanisms for transforming the replicated tables into a denormalised read model.

The intended structure is:

```text
SOURCE
────────────────────────────────

spike_establishment
        │
        ├──── spike_local_authority
        │
        └──── spike_site


                  ↓ logical replication


READ DB
────────────────────────────────

spike_establishment
spike_local_authority
spike_site

                  ↓ projection

spike_establishment_read
────────────────────────
urn
name
local_authority_name
address_line_1
town
postcode
```

At this stage, PostgreSQL logical replication is responsible only for transferring changes between equivalent source and destination tables.

The projection into `spike_establishment_read` will be investigated separately.

## Create the Normalised Source Schema

Create three related tables on the **source database**:

```sql
CREATE TABLE spike_local_authority (
    id integer PRIMARY KEY,
    name text NOT NULL
);

CREATE TABLE spike_establishment (
    id integer PRIMARY KEY,
    urn integer UNIQUE NOT NULL,
    name text NOT NULL,
    local_authority_id integer NOT NULL
        REFERENCES spike_local_authority(id)
);

CREATE TABLE spike_site (
    id integer PRIMARY KEY,
    establishment_id integer NOT NULL
        REFERENCES spike_establishment(id),
    address_line_1 text NOT NULL,
    town text,
    postcode text NOT NULL
);
```

This gives us a simplified normalised model where:

* an establishment references a local authority;
* a site references an establishment;
* local authority and address information are not duplicated directly on the establishment row.

The model is intentionally small but represents the type of relationship that will need to be flattened into the eventual read model.

## Add Source Data

First create a local authority:

```sql
INSERT INTO spike_local_authority (id, name)
VALUES (1, 'Cardiff Council');
```

Then create an establishment referencing that authority:

```sql
INSERT INTO spike_establishment (
    id,
    urn,
    name,
    local_authority_id
)
VALUES (
    1,
    100001,
    'Test School',
    1
);
```

Finally, create a site referencing the establishment:

```sql
INSERT INTO spike_site (
    id,
    establishment_id,
    address_line_1,
    town,
    postcode
)
VALUES (
    1,
    1,
    '1 Test Street',
    'Cardiff',
    'CF10 1AA'
);
```

The insertion order is important because of the foreign-key relationships:

```text
Local Authority
      ↓
Establishment
      ↓
Site
```

## Verify the Source Data

The three normalised tables can be joined to produce the shape required by the read model:

```sql
SELECT
    e.urn,
    e.name,
    la.name AS local_authority_name,
    s.address_line_1,
    s.town,
    s.postcode
FROM spike_establishment e
JOIN spike_local_authority la
    ON la.id = e.local_authority_id
JOIN spike_site s
    ON s.establishment_id = e.id;
```

Expected output:

```text
  urn   |    name     | local_authority_name | address_line_1 |  town   | postcode
--------+-------------+----------------------+----------------+---------+----------
 100001 | Test School | Cardiff Council      | 1 Test Street  | Cardiff | CF10 1AA
```

This demonstrates the key transformation required by the spike.

The source stores the data across several related tables, while a read model could expose the same information as a single flattened row.

## Create the Subscriber-Side Tables

Create compatible tables on the **read database**:

```sql
CREATE TABLE spike_local_authority (
    id integer PRIMARY KEY,
    name text NOT NULL
);

CREATE TABLE spike_establishment (
    id integer PRIMARY KEY,
    urn integer UNIQUE NOT NULL,
    name text NOT NULL,
    local_authority_id integer NOT NULL
);

CREATE TABLE spike_site (
    id integer PRIMARY KEY,
    establishment_id integer NOT NULL,
    address_line_1 text NOT NULL,
    town text,
    postcode text NOT NULL
);
```

The subscriber tables intentionally do not contain the source foreign-key constraints.

For this spike, these tables act primarily as raw replicated copies of the source data.

Keeping the replication layer relatively unconstrained also avoids introducing unnecessary dependencies between table synchronisation operations.

## Add the Tables to the Publication

The existing publication currently contains the original `replication_test` table.

Add the new tables to it:

```sql
ALTER PUBLICATION epr_spike_publication
ADD TABLE
    spike_local_authority,
    spike_establishment,
    spike_site;
```

The publication now contains:

```text
epr_spike_publication
    │
    ├── replication_test
    ├── spike_local_authority
    ├── spike_establishment
    └── spike_site
```

## Verify the Publication

The tables included in the publication can be inspected using:

```sql
SELECT
    pubname,
    schemaname,
    tablename
FROM pg_publication_tables
WHERE pubname = 'epr_spike_publication';
```

Result:

```text
        pubname         | schemaname |        tablename
------------------------+------------+-----------------------
 epr_spike_publication  | public     | replication_test
 epr_spike_publication  | public     | spike_local_authority
 epr_spike_publication  | public     | spike_establishment
 epr_spike_publication  | public     | spike_site
```

## Refresh the Subscription

Adding tables to an existing publication does not automatically cause an existing subscription to start synchronising those tables.

The subscription must therefore be refreshed on the **read database**:

```sql
ALTER SUBSCRIPTION epr_spike_subscription
REFRESH PUBLICATION;
```

`REFRESH PUBLICATION` causes the subscriber to retrieve the current table list from the publication.

Newly discovered tables are then added to the subscription and their existing data is synchronised.

## Verify Replication

On the read database, query the replicated tables:

```sql
SELECT * FROM spike_local_authority;
SELECT * FROM spike_establishment;
SELECT * FROM spike_site;
```

Expected output:

```text
 id |      name
----+-----------------
  1 | Cardiff Council
(1 row)
```

```text
 id |  urn   |    name     | local_authority_id
----+--------+-------------+--------------------
  1 | 100001 | Test School |                  1
(1 row)
```

```text
 id | establishment_id | address_line_1 |  town   | postcode
----+------------------+----------------+---------+----------
  1 |                1 | 1 Test Street  | Cardiff | CF10 1AA
(1 row)
```

This confirms that multiple related normalised tables can be replicated successfully using the existing PostgreSQL publication and subscription.

## Current Architecture

At this point the spike has established the following:

```text
NORMALISED SOURCE
       │
       │ PostgreSQL logical replication
       ▼
NORMALISED READ COPY
       │
       │ transformation / projection mechanism
       ▼
DENORMALISED READ TABLE
```

PostgreSQL logical replication successfully solves the first part of the problem:

> Detecting and transferring changes from the source database to the read database.

The remaining question is how best to perform the second part:

> Transforming changes across several replicated tables into a single denormalised read model.

## Next Investigation

Potential projection mechanisms to investigate include:

* an ordinary PostgreSQL view;
* a materialised view;
* subscriber-side triggers maintaining a denormalised table;
* an external CDC/projection process such as Debezium or an application service.

The next experiment should create `spike_establishment_read` and determine how changes to `spike_establishment`, `spike_local_authority` and `spike_site` can keep that denormalised representation up to date.
