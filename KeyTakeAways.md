# Key TakeWays from doing spike


|Native Postgres|	Airbyte CDC|
|---|---|
|Continuous subscriber|	Scheduled/triggered sync jobs|
|WAL-based|	WAL-based|
|Very low latency|	Latency depends on sync frequency|
|Minimal infrastructure|	Airbyte platform required|
|PostgreSQL-specific|	Connector-based / more portable|
|Native DB behaviour|	Monitoring/orchestration/UI included|