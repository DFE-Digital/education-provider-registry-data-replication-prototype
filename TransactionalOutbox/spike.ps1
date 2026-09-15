param(
    [ValidateSet('start', 'run', 'stop', 'reset')]
    [string]$Action = 'start'
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Push-Location $PSScriptRoot
try {
    if (Test-Path .env) {
        foreach ($line in Get-Content .env) {
            if ($line -match '^\s*([A-Z][A-Z0-9_]*)=(.*)$' -and
                -not [Environment]::GetEnvironmentVariable($Matches[1])) {
                [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2].Trim())
            }
        }
    }

    if ($Action -eq 'reset') {
        Write-Host 'Deleting local demo containers and database volumes.'
        docker compose --profile emulator down -v
        $Action = 'start'
    }

    switch ($Action) {
        'start' {
            dotnet build OutboxDemo/OutboxDemo.csproj --nologo
            docker compose --profile emulator up -d --wait --wait-timeout 120

            Write-Host 'Waiting for Service Bus...'
            $ready = $false
            for ($attempt = 0; $attempt -lt 90; $attempt++) {
                try {
                    $response = Invoke-WebRequest http://127.0.0.1:5301/health -TimeoutSec 5
                    if ($response.StatusCode -eq 200) { $ready = $true; break }
                } catch { }
                Start-Sleep -Seconds 2
            }
            if (-not $ready) { throw 'Service Bus did not start. Check: docker compose logs servicebus mssql' }
            Write-Host 'Ready. Run: .\spike.ps1 run'
        }
        'run'  { dotnet run --project OutboxDemo/OutboxDemo.csproj }
        'stop' { docker compose --profile emulator stop }
    }
} finally {
    Pop-Location
}
