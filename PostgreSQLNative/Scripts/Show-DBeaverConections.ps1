Write-Host "`nDBeaver connection details" -ForegroundColor Cyan

Write-Host "`nSource database"
Write-Host "Host:     localhost"
Write-Host "Port:     15432"
Write-Host "Database: source_db"
Write-Host "Username: postgres"
Write-Host 'Password: postgres'

Write-Host "`nRead database"
Write-Host "Host:     localhost"
Write-Host "Port:     15433"
Write-Host "Database: read_db"
Write-Host "Username: postgres"
Write-Host 'Password: postgres'

Write-Host "`nReal EPR databases use the same respective host, port and password:"
Write-Host "Source: epr_real_source"
Write-Host "Read:   epr_real_read"
