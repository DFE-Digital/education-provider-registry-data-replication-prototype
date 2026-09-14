# Airbyte replication

This spike uses Airbyte to capture PostgreSQL changes through logical replication (CDC).

```text
Source PostgreSQL             Airbyte OSS               Read PostgreSQL
localhost:16432  ---------->   CDC / WAL / pgoutput ---> localhost:16433
core tables                                            airbyte schema
                                                       replicated tables
```

The addresses above are for access from Windows. Airbyte connects to the host using `host.docker.internal` and the same published ports.

A SQL projection into `read_model.establishment` is a proposed next step. The current SQL only creates the empty `read_model` schema; no projection function or establishment table is implemented there.

## Local installation

Follow [the README](./README.md) for prerequisites and startup. The referenced Windows binary is [abctl v0.30.4](https://github.com/airbytehq/abctl/releases/download/v0.30.4/abctl-v0.30.4-windows-amd64.zip). Put `abctl` on PATH before running `start-spike.ps1`.

The startup script installs Airbyte chart `2.2.0` in low-resource mode if its expected local cluster container is absent. Otherwise, it reuses the existing installation. Airbyte is separate from the two PostgreSQL services in Compose.

You can display the local Airbyte login credentials with:

```powershell
abctl local credentials
```

The startup script also displays these credentials for the demo.

## PostgreSQL CDC configuration

Compose configures the source with:

```text
wal_level = logical
max_replication_slots = 10
max_wal_senders = 10
```

The initialization SQL creates the replication user, publication and logical replication slot. See [the connection guide](./AirbyteReplicationPoCInit.md) for the matching Airbyte settings.
