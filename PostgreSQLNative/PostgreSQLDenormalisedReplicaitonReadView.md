# PostgreSQL Denormalised Read View

## Goal

The next step is to investigate how the replicated normalised tables can be exposed as a denormalised read model.

A simple starting point is to create a PostgreSQL view on the read database.

## Create a Denormalised View

On the **read database**, create the following view:

```sql
CREATE VIEW spike_establishment_read AS
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

Conceptually, this gives us:

```text
spike_establishment
       │
       ├────────── spike_local_authority
       │
       └────────── spike_site
       │
       ▼
spike_establishment_read
```

The view exposes a flattened representation of data held across the three replicated tables.

## Query the View

The denormalised view can be queried using:

```sql
SELECT * FROM spike_establishment_read;
```

Result:

```text
  urn   |    name     | local_authority_name | address_line_1 |  town   | postcode
--------+-------------+----------------------+----------------+---------+----------
 100001 | Test School | Cardiff Council      | 1 Test Street  | Cardiff | CF10 1AA
```

This produces the shape expected from a denormalised read model.

However, an ordinary PostgreSQL view does **not** physically store this flattened row.

Instead, PostgreSQL evaluates the underlying joins when the view is queried:

```text
VIEW

spike_establishment_read
        │
        │ executes JOINs
        ▼
spike_establishment
spike_local_authority
spike_site
```

This means the approach gives us a convenient denormalised interface, but does not remove the cost of joining the normalised tables.

## Test Replicated Establishment Changes

Update the establishment on the **source database**:

```sql
UPDATE spike_establishment
SET name = 'Test School Updated'
WHERE id = 1;
```

The change is replicated to the read database through the existing logical replication publication and subscription.

Query the view again on the **read database**:

```sql
SELECT * FROM spike_establishment_read;
```

Result:

```text
  urn   |        name         | local_authority_name | address_line_1 |  town   | postcode
--------+---------------------+----------------------+----------------+---------+----------
 100001 | Test School Updated | Cardiff Council      | 1 Test Street  | Cardiff | CF10 1AA
```

The view immediately reflects the updated replicated data without requiring any changes to the view itself.

## Test Changes to Related Data

It is also important to verify that changes to related tables are reflected in the denormalised result.

On the **source database**, update the local authority:

```sql
UPDATE spike_local_authority
SET name = 'Cardiff Local Authority'
WHERE id = 1;
```

Then query the view on the **read database**:

```sql
SELECT * FROM spike_establishment_read;
```

The `local_authority_name` value is updated automatically because the view joins against the latest replicated version of `spike_local_authority`.

This demonstrates that changes across multiple normalised source tables can be reflected through a single denormalised query model.

## Current Architecture

The architecture now looks like:

```text
NORMALISED SOURCE
       │
       │ PostgreSQL logical replication
       ▼
NORMALISED READ COPY
       │
       │ ordinary PostgreSQL view
       ▼
DENORMALISED QUERY MODEL
```

## Findings

An ordinary PostgreSQL view provides a very simple way to expose replicated normalised data in a denormalised shape.

Advantages include:

* very little additional implementation;
* no additional infrastructure;
* automatically reflects replicated changes;
* changes to related entities are immediately visible through the view;
* no separate synchronisation process is required.

However, the data is **not physically denormalised**.

Each query against the view still requires PostgreSQL to execute the joins between the underlying replicated tables.

Therefore, this approach may be useful if the main objective is to isolate read workloads from the source database, but it does not fully satisfy a requirement where the purpose of denormalisation is to avoid joins and optimise read performance.

## Next Investigation

The next step is to investigate a **physically stored denormalised model**.

The first option to test is a PostgreSQL materialised view, which stores the result of the join rather than recalculating it for every query.

This will allow the spike to compare:

```text
Ordinary View
    → always current
    → joins evaluated at query time

Materialised View
    → physically stores the flattened result
    → requires a mechanism to refresh it
```

The key question will then become how the stored denormalised representation can be kept up to date as replicated source data changes.
