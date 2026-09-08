. "$PSScriptRoot/Invoke-Docker.ps1"
# Run after setup, before making other changes to the sample data.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Push-Location (Split-Path $PSScriptRoot -Parent)

function Run-Sql($server, $database, $file) {
    Invoke-Docker compose exec -T $server psql -X -U postgres -d $database -v ON_ERROR_STOP=1 -f "/spike/$file"
    if ($LASTEXITCODE -ne 0) { throw "Stopped at $file. See the error above." }
}

function Check-Read($file) {
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        Invoke-Docker compose exec -T postgres-read psql -X -U postgres -d epr_real_read -v ON_ERROR_STOP=1 -f "/spike/$file" *> $null
        if ($LASTEXITCODE -eq 0) { return }
        Start-Sleep -Seconds 2
    }
    Run-Sql postgres-read epr_real_read $file
}

try {
    Write-Host 'Checking the starting data...'
    Run-Sql postgres-source epr_real_source tests/check-start-source.sql
    Check-Read tests/00-baseline-read.sql

    $tests = @(
        @('Update a site', '01-update-site-source.sql', '02-update-site-read.sql'),
        @('Add a site', '03-insert-site-source.sql', '04-insert-site-read.sql'),
        @('Delete the added site', '05-delete-site-source.sql', '06-delete-site-read.sql'),
        @('Add a second school', '07-second-establishment-source.sql', '08-second-establishment-read.sql'),
        @('Update the shared type', '09-type-fanout-source.sql', '10-type-fanout-read.sql'),
        @('Update status, phase and site ownership', '11-coverage-source.sql', '12-coverage-read.sql')
    )

    foreach ($test in $tests) {
        Write-Host $test[0]
        Run-Sql postgres-source epr_real_source "tests/$($test[1])"
        Check-Read "tests/$($test[2])"
        Write-Host 'Passed.'
    }

    Write-Host 'Checking the projection before and after a rebuild...'
    Run-Sql postgres-read epr_real_read tests/13-projection-equality-read.sql
    Run-Sql postgres-read epr_real_read read/11-rebuild.sql
    Run-Sql postgres-read epr_real_read tests/13-projection-equality-read.sql
    Run-Sql postgres-read epr_real_read read/12-verify.sql
    Write-Host 'All real-schema tests passed.'
} finally {
    Pop-Location
}
