. "$PSScriptRoot/Invoke-Docker.ps1"
# Deletes the real-schema PoC. Leaves the toy databases and subscription alone.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Run-Sql($container, $database, $sql) {
    $sql | Invoke-Docker exec -i $container psql -X -U postgres -d $database -v ON_ERROR_STOP=1
    if ($LASTEXITCODE -ne 0) { throw 'Reset stopped. See the PostgreSQL error above.' }
}

Write-Host 'Removing the real-schema subscription and its source slot...'
$readExists = Invoke-Docker exec epr-postgres-read psql -X -U postgres -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname = 'epr_real_read';"
if ($LASTEXITCODE -ne 0) { throw 'Could not connect to the read server.' }

if ($readExists -eq '1') {
    Run-Sql epr-postgres-read epr_real_read @'
SELECT 'DROP SUBSCRIPTION epr_real_subscription;'
WHERE EXISTS (
    SELECT 1 FROM pg_subscription
    WHERE subname = 'epr_real_subscription'
      AND subdbid = (SELECT oid FROM pg_database WHERE datname = current_database())
)
\gexec
'@
}

Write-Host 'Deleting the real-schema databases...'
Run-Sql epr-postgres-read postgres 'DROP DATABASE IF EXISTS epr_real_read WITH (FORCE);'
Run-Sql epr-postgres-source postgres 'DROP DATABASE IF EXISTS epr_real_source WITH (FORCE);'
Run-Sql epr-postgres-source postgres 'DROP ROLE IF EXISTS epr_real_replicator;'

Write-Host 'Reset complete. Run Scripts/Run-Spike.ps1 to create the real-schema PoC again.'
