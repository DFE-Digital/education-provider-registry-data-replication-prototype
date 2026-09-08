# PostgreSQL Denormalised Materialised View

## Concept

The key difference between an ordinary PostgreSQL view and a materialised view is how the result is stored.

An ordinary view stores the query definition and executes the underlying joins whenever the view is queried.

A materialised view executes the query and physically stores the resulting rows.

```text
ORDINARY VIEW

Query
  ↓
JOIN tables at query time
  ↓
Result


MATERIALISED VIEW

JOIN tables
  ↓
Stored result
  ↓
Query stored rows
```

This makes a materialised view potentially more suitable for read-heavy workloads where avoiding repeated joins is important.

However, the stored result must be refreshed when the underlying data changes.

## Create the Materialised View

Create the materialised view on the **read database**:

```sql
CREATE MATERIALIZED VIEW spike_establishment_read_materialised AS
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

The materialised view can then be queried using:

```sql
SELECT * FROM spike_establishment_read_materialised;
```

Example result:

```text
  urn   |        name         | local_authority_name    | address_line_1 |  town   | postcode
--------+---------------------+-------------------------+----------------+---------+----------
 100001 | Test School Updated | Cardiff Local Authority | 1 Test Street  | Cardiff | CF10 1AA
```

The result looks the same as the ordinary view, but the important difference is that these rows are physically stored rather than recreated from the joins on every query.

This can improve read performance, particularly where the underlying joins are expensive or the read model is queried frequently.

## Behaviour When Replicated Data Changes

When one of the replicated source tables changes, logical replication continues to update the corresponding normalised table on the read database.

However, the materialised view does **not** automatically update.

For example:

```text
SOURCE DATA CHANGES
        ↓
PostgreSQL logical replication
        ↓
READ TABLE UPDATED
        ↓
MATERIALISED VIEW REMAINS STALE
```

The materialised view must be explicitly refreshed:

```sql
REFRESH MATERIALIZED VIEW spike_establishment_read_materialised;
```

This causes PostgreSQL to rerun the query used to define the materialised view and replace the previously stored result.

Conceptually:

```text
replicated data changed
        ↓
materialised view remains stale
        ↓
REFRESH MATERIALIZED VIEW
        ↓
stored denormalised data rebuilt
        ↓
materialised view current
```

## Comparison with an Ordinary View

| Capability                                | Ordinary View | Materialised View |
| ----------------------------------------- | ------------- | ----------------- |
| Provides a flattened interface            | ✅             | ✅                 |
| Physically stores the result              | ❌             | ✅                 |
| Avoids joins on every read                | ❌             | ✅                 |
| Automatically reflects replicated changes | ✅             | ❌                 |
| Requires explicit refresh                 | ❌             | ✅                 |
| Can have indexes directly on the result   | ❌             | ✅                 |

## Findings

A materialised view moves the approach closer to a genuinely denormalised read model because the flattened result is physically stored.

This provides an important advantage over an ordinary view:

```text
Ordinary View
    → calculate the denormalised result during each read

Materialised View
    → calculate the denormalised result during refresh
    → read the previously calculated rows
```

The main drawback is freshness.

Logical replication may update the read-side tables almost immediately, while the materialised view continues to contain the previous result until it is refreshed.

This introduces a new architectural question:

> What should trigger the materialised view to refresh, and how frequently should that happen?

Frequent refreshes would reduce the period in which the read model is stale, but could become expensive as the volume of data grows.

Less frequent refreshes reduce refresh overhead but increase the amount of time in which the read model may be out of date.

## Current Architecture

```text
NORMALISED SOURCE
       │
       │ PostgreSQL logical replication
       ▼
NORMALISED READ COPY
       │
       │ materialised view refresh
       ▼
PHYSICALLY STORED
DENORMALISED RESULT
```

## Next Investigation

The next approach to investigate is maintaining a real denormalised table as replicated changes arrive.

