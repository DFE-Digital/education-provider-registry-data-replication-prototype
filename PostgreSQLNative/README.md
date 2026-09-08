# PostgreSQL replication spike

Requires Docker Desktop and PowerShell 7.2 or newer. From this folder:

```powershell
.\Scripts\Run-Spike.ps1
.\Scripts\Run-Tests.ps1
```

Setup creates fresh `epr_real_source` and `epr_real_read` databases on the two existing PostgreSQL services. It installs the schema, loads sample data, sets up replication, waits for all 33 tables, then creates the projection. It does not drop or reset databases. If the real-schema databases already exist, don't repeat setup; inspect them and continue with individual SQL files.

The tests run once against the original sample data. They change sites, add a second school, test shared reference changes, and check a rebuild. A failed read assertion is retried while replication catches up. Source changes are not retried.

Both containers use the local development password `postgres`. For manual Compose commands, use:

```powershell
docker compose ps
.\Scripts\Show-DBeaverConections.ps1
```

Existing PostgreSQL volumes keep the password set when they were first initialized. Changing `compose.yaml` does not change that database password. Recreate the volumes if the existing containers were initialized with a different password.

The SQL is mounted read-only at `/spike`. The original schema also remains in `Scripts/epr-real-schema.sql`; the setup copy is in `schema/`.

Changes checked offline: SQL parsing, script paths, PowerShell syntax and simulated Docker calls. No database setup or tests were run while fixing these files.

## Reset the real-schema PoC

This deletes the data in `epr_real_source` and `epr_real_read`. The toy databases are kept. Both containers must be running so PostgreSQL can remove the subscription and its source slot.

```powershell
.\Scripts\Reset-Spike.ps1
.\Scripts\Run-Spike.ps1
```

Only run setup if reset completes successfully. The dedicated real-schema replication role is also removed and recreated by setup. Reset does not remove Docker volumes or the toy publication/subscription.
