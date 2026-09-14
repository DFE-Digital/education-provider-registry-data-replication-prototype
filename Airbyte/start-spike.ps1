param(
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$projectRoot = $PSScriptRoot
$airbyteControlPlane = "airbyte-abctl-control-plane"
$airbyteChartVersion = "2.2.0"

if ([string]::IsNullOrWhiteSpace($projectRoot)) {
    $projectRoot = (Get-Location).Path
}

Push-Location $projectRoot

function Require-Command($command) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "'$command' was not found on PATH."
    }
}

function Wait-ForPostgres($service) {
    Write-Host "Waiting for PostgreSQL service '$service'..."

    for ($attempt = 1; $attempt -le 30; $attempt++) {
        cmd /c "docker compose exec -T $service pg_isready -U postgres >nul 2>&1"

        if ($LASTEXITCODE -eq 0) {
            Write-Host "$service is ready."
            return
        }

        Start-Sleep -Seconds 2
    }

    throw "PostgreSQL service '$service' did not become ready."
}

function Get-PortMapping($service) {
    $mapping = docker compose port $service 5432 2>$null

    if ($LASTEXITCODE -eq 0) {
        return ($mapping | Select-Object -First 1)
    }

    return "Not published"
}

function Get-AirbyteControlPlaneState {
    cmd /c "docker inspect $airbyteControlPlane >nul 2>&1"

    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    $state = docker inspect `
        --format "{{.State.Status}}" `
        $airbyteControlPlane 2>$null

    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    return ($state | Select-Object -First 1).Trim()
}

function Wait-ForAirbyte {
    Write-Host "Waiting for Airbyte..."

    for ($attempt = 1; $attempt -le 30; $attempt++) {
        cmd /c "abctl local status >nul 2>&1"

        if ($LASTEXITCODE -eq 0) {
            Write-Host "Airbyte is ready."
            return
        }

        Start-Sleep -Seconds 2
    }

    throw "Airbyte did not become ready."
}

function Start-Airbyte {
    Write-Host ""
    Write-Host "Checking Airbyte..."

    $state = Get-AirbyteControlPlaneState

    # Airbyte's kind cluster does not exist.
    if ($null -eq $state) {
        Write-Host "Airbyte Kubernetes cluster was not found."
        Write-Host "Creating Airbyte cluster..."

        abctl local install `
            --chart-version $airbyteChartVersion `
            --low-resource-mode `
            --no-browser

        if ($LASTEXITCODE -ne 0) {
            throw "Airbyte installation failed."
        }

        Wait-ForAirbyte
        return
    }

    # Cluster exists but Docker has it stopped.
    if ($state -ne "running") {
        Write-Host "Airbyte Kubernetes cluster is '$state'."
        Write-Host "Starting Airbyte Kubernetes cluster..."

        docker start $airbyteControlPlane *> $null

        if ($LASTEXITCODE -ne 0) {
            throw "Unable to start the Airbyte Kubernetes cluster."
        }

        Wait-ForAirbyte
        return
    }

    # Container is running. Make sure Kubernetes/Airbyte is actually ready.
    Write-Host "Airbyte Kubernetes cluster is running."

    Wait-ForAirbyte
}

try {
    Require-Command docker
    Require-Command abctl

    Write-Host ""
    Write-Host "=== EPR Airbyte Replication Spike ==="
    Write-Host ""

    # ------------------------------------------------------------
    # Docker
    # ------------------------------------------------------------

    Write-Host "Checking Docker..."

    cmd /c "docker info >nul 2>&1"

    if ($LASTEXITCODE -ne 0) {
        throw "Docker is not running. Start Docker Desktop and try again."
    }

    Write-Host "Docker is running."

    # ------------------------------------------------------------
    # PostgreSQL
    # ------------------------------------------------------------

    Write-Host ""
    Write-Host "Starting spike containers..."

    docker compose up -d

    if ($LASTEXITCODE -ne 0) {
        throw "docker compose up failed."
    }

    Wait-ForPostgres "source"
    Wait-ForPostgres "read"

    # ------------------------------------------------------------
    # PostgreSQL CDC sanity checks
    # ------------------------------------------------------------

    Write-Host ""
    Write-Host "Checking source replication configuration..."

    $walLevel = docker compose exec -T source `
        psql -U postgres -d airbyte_source -Atc `
        "SHOW wal_level;"

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to check wal_level."
    }

    if ($walLevel -ne "logical") {
        throw "Expected wal_level to be 'logical' but found '$walLevel'."
    }

    Write-Host "wal_level       : $walLevel"

    $publication = docker compose exec -T source `
        psql -U postgres -d airbyte_source -Atc `
        "SELECT pubname FROM pg_publication WHERE pubname = 'airbyte_publication';"

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to check Airbyte publication."
    }

    if (-not $publication) {
        throw "airbyte_publication was not found."
    }

    Write-Host "Publication     : $publication"

    $replicationSlot = docker compose exec -T source `
        psql -U postgres -d airbyte_source -Atc `
        "SELECT slot_name FROM pg_replication_slots WHERE slot_name = 'airbyte_slot';"

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to check Airbyte replication slot."
    }

    if (-not $replicationSlot) {
        throw "airbyte_slot was not found."
    }

    Write-Host "Replication slot: $replicationSlot"

    # ------------------------------------------------------------
    # Airbyte
    # ------------------------------------------------------------

    Start-Airbyte

    # ------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------

    $sourcePort = Get-PortMapping "source"
    $readPort = Get-PortMapping "read"

    Write-Host ""
    Write-Host "=== Ready ==="
    Write-Host ""
    Write-Host "Source PostgreSQL : $sourcePort"
    Write-Host "Read PostgreSQL   : $readPort"
    Write-Host "Airbyte           : http://localhost:8000"
    Write-Host ""

    Write-Host "Airbyte source connection:"
    Write-Host "  Host     : host.docker.internal"
    Write-Host "  Port     : 16432"
    Write-Host "  Database : airbyte_source"
    Write-Host "  Username : airbyte_replication"
    Write-Host "  Password : airbyte"
    Write-Host "  Schema   : core"
    Write-Host ""

    Write-Host "Airbyte destination connection:"
    Write-Host "  Host     : host.docker.internal"
    Write-Host "  Port     : 16433"
    Write-Host "  Database : airbyte_read"
    Write-Host "  Username : airbyte_writer"
    Write-Host "  Password : airbyte"
    Write-Host ""

    Write-Host "Airbyte credentials:"
    abctl local credentials

    Write-Host ""

    docker compose ps

    if (-not $NoBrowser) {
        Start-Process "http://localhost:8000"
    }
}
finally {
    Pop-Location
}