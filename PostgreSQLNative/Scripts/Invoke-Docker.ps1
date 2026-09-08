function Invoke-Docker {
    # PostgreSQL NOTICE messages use stderr. Check the exit code, not the stream.
    $ErrorActionPreference = 'Continue'
    $lines = @($input)
    if ($lines.Count) { $output = $lines | & docker @args 2>&1 }
    else { $output = & docker @args 2>&1 }
    $code = $LASTEXITCODE
    $output | ForEach-Object { $_.ToString() }
    $global:LASTEXITCODE = $code
}
