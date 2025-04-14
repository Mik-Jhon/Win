param (
    [string]$arg1,
    [string]$arg2
)

Write-Host "Simulating download of program 1..." -ForegroundColor Gray
Start-Sleep -Seconds 1
Write-Host "Simulating download of program 2..." -ForegroundColor Gray
Start-Sleep -Seconds 1

# Create output file
$user = [Environment]::UserName
Set-Content -Path ".\results.txt" -Value @"
Username: $user
Argument 1: $arg1
Argument 2: $arg2
"@

Write-Host "`nArguments written to results.txt"

# Optionally simulate running the first argument
Write-Host "`n[SIMULATED] Running: $arg1" -ForegroundColor DarkYellow
Start-Sleep -Seconds 1

# Optionally delete the script itself (disabled here for safety)
# Remove-Item -Path $MyInvocation.MyCommand.Path -Force

Write-Host "`nDone."
