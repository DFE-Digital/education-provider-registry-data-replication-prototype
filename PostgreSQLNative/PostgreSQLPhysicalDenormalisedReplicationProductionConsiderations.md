# PostgreSQL Physical Denormalised Replication — Production Considerations

## Purpose

This document records the production considerations identified during the PostgreSQL logical replication spike. It is intended to support the architectural recommendation and identify work that would be required during production implementation.

The spike is not intended to implement or resolve every consideration listed below.

## Proven Approach

The PoC has demonstrated the following architecture:

```text
NORMALISED SOURCE DATABASE
        │
        │ PostgreSQL logical replication
        ▼
NORMALISED READ-SIDE TABLES
        │
        │ ENABLE REPLICA triggers
        │ Shared projection functions
        ▼
PHYSICAL DENORMALISED READ MODEL
        │
        ▼
READ / QUERY APPLICATION
```

The following behaviours have been verified:

* Initial synchronisation and ongoing INSERT, UPDATE and DELETE replication.
* Physical denormalised rows maintained automatically through replica triggers.
* Changes to establishment, site and local authority data updating the projection.
* One shared local authority change updating multiple establishment rows.
* A repeatable, transactional rebuild procedure.
* Recovery from a temporary subscription interruption, including automatic replay and projection updates.

These results establish that the PostgreSQL-only approach is technically viable for the simplified model used in the spike. They do not establish that it is production-ready at the required scale.

## 1. Replication Lag and Availability

PostgreSQL logical replication is asynchronous. The read database may therefore lag behind the source, and the application must tolerate eventual consistency.

A temporary subscription interruption was tested successfully. The source continued accepting changes, and the subscriber replayed the missed changes when replication resumed.

Production considerations include:

* Defining acceptable replication lag and read-model freshness.
* Monitoring subscription worker health and replication progress.
* Alerting when lag exceeds agreed thresholds.
* Determining how the application should behave when the read model is stale or unavailable.
* Establishing recovery procedures for prolonged outages and source failover.

A successful short interruption does not guarantee recovery from every outage scenario.

## 2. Replication Slots and WAL Retention

Logical replication slots retain WAL required by subscribers that have not yet consumed it. This enables recovery after temporary interruptions, but can create storage pressure when a subscriber remains unavailable or falls significantly behind.

Production implementation should consider:

* Monitoring replication-slot health and retained WAL.
* Defining storage limits and alerting thresholds.
* Understanding the consequences of slot invalidation or unavailable WAL.
* Establishing a controlled re-synchronisation process when ordinary replay is no longer possible.
* Considering the effect of source failover on replication continuity.

The spike has proved replay after a temporary pause, but has not tested prolonged outages or WAL exhaustion.

## 3. Projection Failures and Operational Coupling

The trigger experiment demonstrated that an error in projection logic can prevent the subscription apply worker from successfully applying a transaction.

In the PoC, a function-resolution issue caused the worker to repeatedly fail. The raw replicated table remained stale until the projection code was corrected, after which replication caught up automatically.

This is a significant trade-off of subscriber-side triggers: **projection correctness is coupled to replication availability**.

Production implementation should include:

* Versioned and tested database functions and triggers.
* Schema-qualified database object references.
* Monitoring and alerting for subscription apply errors.
* Clear procedures for diagnosing and recovering from projection failures.
* Consideration of whether projection failures should be isolated from the replication transport.

An external projection service may provide different failure-isolation characteristics and should be considered during the final architectural comparison.

## 4. Schema Changes and Deployment Ordering

Native PostgreSQL logical replication does not automatically replicate DDL or transform source schemas into the required denormalised structure.

Changes to source tables, replicated read-side tables, projection functions and physical read-model tables must therefore be coordinated.

Production implementation should define:

* Ownership of source and read-side database schemas.
* How EF Core migrations are used for schema changes.
* How projection SQL, functions and triggers are versioned and deployed.
* The order in which compatible source, subscriber and projection changes are released.
* How deployments avoid breaking active subscriptions.
* How rollback or forward-fix procedures handle incompatible schema changes.

The EF Core integration and deployment sequence will be investigated separately as the remaining focused part of the spike.

## 5. Projection Correctness and Data Modelling

The current PoC uses a simplified model and assumes one site per establishment. It also uses inner joins, meaning an establishment without all required related records may not appear in the physical projection.

Before production implementation, the read-model contract should define:

* Whether one establishment can have multiple sites and which site data should be projected.
* How optional or missing relationships are represented.
* How deletes, reassignments and primary-key changes affect the projection.
* How changes to shared entities are propagated to all affected rows.
* How duplicate or conflicting projection keys are prevented.
* How the read model is validated against the source-of-truth data.

The projection should be designed around the actual read/query requirements rather than simply flattening every available source table.

## 6. Rebuild and Initialisation

The PoC includes a repeatable transactional rebuild procedure that regenerates the physical projection from the normalised read-side tables.

The procedure uses locks to establish a consistent input set and therefore deliberately blocks replication writes while the rebuild is running.

Production considerations include:

* Initial population of a new read environment.
* Rebuilding after projection schema changes or data-quality issues.
* Validation of row counts and projection correctness.
* Ensuring ongoing changes are not lost or overwritten during a rebuild.
* The effect of rebuild duration on replication lag.
* Whether a shadow-table build and controlled cutover is required for larger datasets.

The current procedure is a **blocking prototype**. A production-scale online rebuild has not been implemented or tested.

## 7. Performance and Fan-Out

The trigger-based approach performs projection work as part of the replication apply process. A change to a shared entity, such as a local authority, may require many establishment rows to be rebuilt.

The PoC proved this behaviour with two establishments, but did not establish performance at production scale.

Production implementation should assess:

* Representative source table and read-model sizes.
* Typical and peak change volumes.
* The number of affected rows for shared-entity updates.
* Indexing requirements on raw and denormalised tables.
* The cost of repeated joins, deletes and inserts.
* The impact of projection processing on replication lag.
* Whether set-based, batched or asynchronous projection strategies are required.

No throughput or latency claims should be made from the current small-scale experiment.

## 8. Security and Operational Ownership

The production solution will require clear ownership of the replication and projection components.

Considerations include:

* Separate database roles and least-privilege access for replication, migrations and read applications.
* Secure management of connection strings and credentials.
* Restricting application writes to the physical read model.
* Monitoring, logging and alerting ownership.
* Backup and recovery responsibilities.
* Runbooks for subscription failures, schema mismatches and rebuilds.

These concerns should be incorporated into the existing infrastructure and deployment practices rather than introducing an independent operational process unnecessarily.

## Summary of Trade-Offs

| Area                         | PostgreSQL-only approach                                         |
| ---------------------------- | ---------------------------------------------------------------- |
| Replication transport        | Native PostgreSQL logical replication                            |
| Denormalisation              | Subscriber-side SQL functions and triggers                       |
| Additional infrastructure    | Minimal                                                          |
| Read-model freshness         | Asynchronous, dependent on replication and projection processing |
| Initialisation               | Requires a separate population/rebuild process                   |
| Projection failure isolation | Limited; trigger failures can block replication apply            |
| Schema management            | Requires coordinated migrations and deployment ordering          |
| Operational complexity       | Database-centric, increasing with projection complexity          |
| Production-scale performance | Not yet established                                              |

## Conclusion

The spike has demonstrated that a PostgreSQL-only solution can replicate normalised source data and maintain a physically denormalised read model.

The main advantage is that the approach can use existing PostgreSQL capabilities without introducing an additional CDC platform. The main concerns are the coupling between projection logic and replication, schema/deployment coordination, rebuild complexity, and the potential performance impact of large or complex projections.

These considerations do not invalidate the approach. They identify the areas that would need to be addressed during production implementation.

The remaining spike work should focus on **EF Core migration and deployment integration**, followed by a proportionate comparison with alternative mechanisms such as Airbyte or an application-driven projection service. The final recommendation should distinguish the capabilities demonstrated by the PoC from the production work that remains outstanding.
