param([switch] $ContinueFromSubscription)

. "$PSScriptRoot/Invoke-Docker.ps1"

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$spikeRoot = Split-Path $PSScriptRoot -Parent
Push-Location $spikeRoot

function Run-Sql($server, $database, $file) {
    Write-Host "Running $file"

    Invoke-Docker compose exec -T $server `
        psql -X -U postgres -d $database `
        -v ON_ERROR_STOP=1 `
        -f "/spike/$file"

    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw "Stopped at $file (exit code $exitCode)."
    }
}

function Wait-Database($server) {
    Write-Host "Waiting for $server..."

    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        Invoke-Docker compose exec -T $server `
            psql -X -U postgres -d postgres -c 'SELECT 1;' *> $null

        if ($LASTEXITCODE -eq 0) {
            return
        }

        Start-Sleep -Seconds 2
    }

    throw "$server did not become ready."
}

try {
    if (-not $ContinueFromSubscription) {
    Write-Host 'Starting PostgreSQL containers...'

    Invoke-Docker compose up -d

    if ($LASTEXITCODE -ne 0) {
        throw 'Could not start Docker containers.'
    }

    Wait-Database postgres-source
    Wait-Database postgres-read

    Write-Host 'Creating the real-schema databases (fresh setup only)...'

    Run-Sql postgres-source postgres setup/01-source-database.sql
    Run-Sql postgres-read postgres setup/02-read-database.sql

    Write-Host 'Creating schemas...'

    Run-Sql postgres-source epr_real_source schema/epr-real-schema.sql
    Run-Sql postgres-read epr_real_read schema/epr-real-schema.sql

    Write-Host 'Setting up replication...'

    Run-Sql postgres-source epr_real_source source/04-replication.sql

    $password = [Guid]::NewGuid().ToString('N')
    "ALTER ROLE epr_real_replicator PASSWORD '$password';" |
        Invoke-Docker compose exec -T postgres-source psql -X -U postgres -d epr_real_source -v ON_ERROR_STOP=1 *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Could not set the replication password.' }

    Run-Sql postgres-source epr_real_source source/07-seed.sql

    $subscription = (Get-Content 'read/05-subscription.sql' -Raw).Replace('<replication-password>', $password)

    $subscription |
        Invoke-Docker compose exec -T postgres-read `
            psql -X -U postgres -d epr_real_read `
            -v ON_ERROR_STOP=1 *> $null

    if ($LASTEXITCODE -ne 0) {
        throw 'Could not create subscription.'
    }

    }

    Write-Host 'Waiting for all 33 tables to finish copying...'
    $synced = $false
    for ($attempt = 0; $attempt -lt 90; $attempt++) {
        Invoke-Docker compose exec -T postgres-read psql -X -U postgres -d epr_real_read -v ON_ERROR_STOP=1 -f /spike/read/06-sync-check.sql *> $null
        if ($LASTEXITCODE -eq 0) { $synced = $true; break }
        Start-Sleep -Seconds 2
    }
    if (-not $synced) {
        Run-Sql postgres-read epr_real_read read/06-sync-check.sql
        throw 'Initial copy timed out. Check replication before continuing.'
    }

    Write-Host 'Creating read projection...'

    Run-Sql postgres-read epr_real_read read/08-projection.sql
    Run-Sql postgres-read epr_real_read read/09-original-triggers.sql
    Run-Sql postgres-read epr_real_read read/10-coverage-corrections.sql
    Run-Sql postgres-read epr_real_read read/11-rebuild.sql

    Write-Host 'Running checks...'

    Run-Sql postgres-read epr_real_read tests/00-baseline-read.sql
    Run-Sql postgres-read epr_real_read tests/13-projection-equality-read.sql
    Run-Sql postgres-read epr_real_read read/12-verify.sql

    Write-Host 'Spike setup complete.'
}
finally {
    Pop-Location
}
