# Overview

# Overview

| Approach | Change mechanism | Typical behaviour |
|---|---|---|
| PostgreSQL native | Logical replication / WAL | Continuous |
| Transactional outbox | Application events / message broker | Near real time |
| Airbyte | CDC / WAL | Sync based |
| Azure Data Factory | Watermark / incremental query | Scheduled ETL |

## Recommendation summary

| Choice | Best fit |
|---|---|
| **1. PostgreSQL replication + triggers** | PostgreSQL → PostgreSQL denormalised read model |
| **2. Transactional outbox** | Event-driven architecture / multiple consumers |
| **3. Airbyte** | Cross-platform data movement |
| **4. Azure Data Factory** | Scheduled ETL / Azure data integration |

## Transactional outbox

| Pros                                                               | Cons                                                               |
| ------------------------------------------------------------------ | ------------------------------------------------------------------ |
| Projection logic can be written in C#                              | More infrastructure to maintain                                    |
| Source change and event can be saved atomically                    | Every relevant write path must create an event                     |
| Multiple consumers can use the same events                         | Direct SQL changes bypass the outbox                               |
| Consumers can process independently                                | Must handle duplicates and ordering                                |
| Events can represent business actions rather than raw data changes | Shared-reference changes need explicit handling                    |
| Pending events survive publisher downtime                          | Backlogs, retries and dead letters need monitoring                 |
| Can feed different databases and services                          | Rebuilding requires retained events or a separate backfill process |

## PostgreSQL logical replication + triggers

| Pros                                                        | Cons                                                            |
| ----------------------------------------------------------- | --------------------------------------------------------------- |
| Fewer moving parts                                          | Projection logic lives in SQL and triggers                      |
| Captures changes from any writer to published tables        | Every projection dependency needs trigger coverage              |
| No event-writing code required in the application           | Trigger failures can stop subscriber transactions               |
| PostgreSQL manages replication and transaction ordering     | Heavy projection work can increase replication lag              |
| Projection updates occur in the same subscriber transaction | Schema changes need coordinating between source and destination |
| Projection can be rebuilt from the replicated source tables | Destination stores source tables as well as the projection      |
| Well suited to keeping a PostgreSQL read database current   | Less suited to business events and non-PostgreSQL consumers     |

## Airbyte

| Pros                                                      | Cons                                                         |
| --------------------------------------------------------- | ------------------------------------------------------------ |
| Little application code required                          | Another platform to deploy and maintain                      |
| CDC captures changes from any writer to configured tables | PostgreSQL CDC still requires replication configuration      |
| UI for configuring connections and viewing syncs          | Connector settings and upgrades need managing                |
| Supports many source and destination systems              | Behaviour varies between connectors                          |
| Handles initial copying and subsequent syncs              | Freshness depends on sync frequency and duration             |
| Application write paths remain unchanged                  | Denormalised projection logic still needs solving separately |
| Useful when moving data between different platforms       | More infrastructure than native PostgreSQL replication       |
| Built-in sync history and error reporting                 | Failed syncs and replication-slot backlog need monitoring    |

## Azure Data Factory

| Pros                                                     | Cons                                                         |
| -------------------------------------------------------- | ------------------------------------------------------------ |
| Managed Azure service                                    | Primarily scheduled rather than continuous                   |
| Integrates well with Azure services                      | Requires Azure infrastructure to properly evaluate           |
| Good for batch and ETL-style transformations             | Incremental loading needs watermark or change-tracking logic |
| Built-in monitoring and operational tooling              | More configuration than native PostgreSQL replication        |
| Transformation logic can be kept outside the application | Less suitable where near-real-time freshness is required     |

## Ranking

| Choice                                   | When I’d use it                                                                        | Freshness                                                                                |
| ---------------------------------------- | -------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| **1. PostgreSQL replication + triggers** | Keeping a PostgreSQL read model synchronised with a PostgreSQL source                  | Continuous; usually near real time, depending on replication lag and projection workload |
| **2. Transactional outbox**              | Driving services, workflows or read models when we control the application write paths | Near real time; depends on publisher frequency and message backlog                       |
| **3. Airbyte**                           | Moving data between different systems where some delay is acceptable                   | Depends on sync schedule and duration                                                    |
| **4. Azure Data Factory**                | Batch-oriented integration or ETL where scheduled updates are acceptable               | Scheduled; typically minutes or longer                                                   |

## Recommendation

For the current requirement — maintaining a denormalised PostgreSQL read model from a PostgreSQL source — **native PostgreSQL logical replication with a locally maintained projection is the strongest fit**.

It has the fewest moving parts, captures changes regardless of which application performs the write, and keeps the replicated source data available so the read projection can be rebuilt if necessary.

The **transactional outbox** becomes more attractive if the requirement expands beyond database replication into application events, multiple consumers, other services, or non-PostgreSQL destinations.

**Airbyte** is useful where interoperability between different platforms is more important than having the smallest possible solution.

**Azure Data Factory** is better suited to scheduled data integration and ETL than to maintaining a near-real-time read model.
