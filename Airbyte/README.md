# EPR Airbyte replication spike

A local Windows demo of PostgreSQL change data capture (CDC) through Airbyte. The source contains synthetic schools, sites and a local authority. Airbyte copies those tables into a separate PostgreSQL database.

All database passwords in this folder are intentionally disposable demo credentials. The startup script also displays the local Airbyte login credentials for use during the demo.

## Prerequisites

- Windows with PowerShell and Docker Desktop running Linux containers.
- Docker Compose (`docker compose`) and `abctl` available on PATH.
- The notes reference [abctl v0.30.4 for Windows](https://github.com/airbytehq/abctl/releases/download/v0.30.4/abctl-v0.30.4-windows-amd64.zip). Extract it and add its directory to PATH.
- Optional: DBeaver to inspect both databases.

The startup script uses Windows `cmd /c`, expects the Airbyte container name `airbyte-abctl-control-plane`, and opens the UI at `http://localhost:8000`. New Airbyte installations use chart version `2.2.0` with low-resource mode. Existing installations are reused. Custom Airbyte installations may require adjusting the script.

## Start

Open PowerShell in this Airbyte folder and run:

```powershell
.\start-spike.ps1
# Or skip opening the browser:
.\start-spike.ps1 -NoBrowser
```

The script starts both Compose databases, checks the source WAL configuration, publication and replication slot, and starts or installs Airbyte. It prints connection details and Airbyte login credentials. It does not create Airbyte sources, destinations or connections; follow [the connection guide](./AirbyteReplicationPoCInit.md) once the UI is available.

Database ports are bound to `127.0.0.1` for local use. DBeaver connects through `localhost`; Airbyte uses Docker Desktop's `host.docker.internal`. Use Test and Save for both connectors to verify connectivity on your Docker Desktop installation. See [Docker Desktop networking](https://docs.docker.com/desktop/features/networking/networking-how-tos/) and [port publishing](https://docs.docker.com/engine/network/port-publishing/).

## Configure and demonstrate replication

1. Create the source, destination and manual connection using [the connection guide](./AirbyteReplicationPoCInit.md).
2. Run the first sync and wait for success.
3. Open the destination in [DBeaver](./ConnectingToDBeaver.md) and inspect the replicated tables in the `airbyte` schema.
4. Change one synthetic source record:

```powershell
docker compose exec -T source psql -U postgres -d airbyte_source -c "UPDATE core.establishment SET name = 'Alpha Academy Updated' WHERE urn = 1000001;"
```

5. Run another manual sync and wait for success. Inspect the destination establishment data for the updated name. The exact table layout and whether previous versions remain depend on your selected connector sync mode.

The SQL creates an empty `read_model` schema. A projection/function and `read_model.establishment` are future work; this spike currently demonstrates replication into Airbyte-managed tables only.

## Stop and resume

```powershell
# Stop the demo databases, preserving their named volumes:
docker compose stop
# Stop the default local Airbyte cluster container:
docker stop airbyte-abctl-control-plane
```

Stopping that container stops the Airbyte installation reused by this script, including any other connections configured in it. Run `start-spike.ps1` again to resume.

## Reset the databases

**Destructive: the following command deletes both Compose database volumes and all data in them.** Use it only when you want fresh demo databases.

```powershell
docker compose down -v
docker compose up -d
```

Initialization SQL runs when a database volume is first created. Editing those SQL files does not change an existing database automatically. Resetting the databases does not reset Airbyte's saved connection state; recreate the demo connection in the UI before the next initial sync so it does not reuse an old CDC position.

## Files

- `docker-compose.yml`: two PostgreSQL 17.10 services and named data volumes.
- `start-spike.ps1`: local startup and configuration checks.
- `source/init/01-SourceSchemaSmall.sql`: source schema and synthetic seed data.
- `source/init/02-cdc.sql`: replication user, grants, publication and slot.
- `read/init/01-ReadSchemaSmall.sql`: destination writer and schemas.
- [AirbyteReplication.md](./AirbyteReplication.md): architecture and installation notes.
- [AirbyteReplicationPoCInit.md](./AirbyteReplicationPoCInit.md): Airbyte connection settings.
- [ConnectingToDBeaver.md](./ConnectingToDBeaver.md): database inspection settings.

The `.gitignore` excludes local environment files, logs, database dumps/data and common Airbyte/Kubernetes state paths. Keep any future real credentials or exported connection state outside source control.
