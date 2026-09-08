# Quick Guide to Connecting to DBeaver from the Docker Instances

Go to **Database > New Database Connection**.

Add the following details:

| Setting | Value |
|---|---|
| Host | `localhost` |
| Port | `15432` |
| Database | `epr_real_source` |
| Username | `postgres` |
| Password | `postgres` |

Repeat for the read database:

| Setting | Value |
|---|---|
| Host | `localhost` |
| Port | `15433` |
| Database | `epr_real_read` |
| Username | `postgres` |
| Password | `postgres` |