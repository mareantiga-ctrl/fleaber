# Mata processos Maestro/Java presos apos timeout ou FAIL.
$ErrorActionPreference = "Continue"
Get-Process -Name java -ErrorAction SilentlyContinue | Where-Object {
  $_.Path -match 'maestro|\.maestro' -or $_.CommandLine -match 'maestro'
} | Stop-Process -Force -ErrorAction SilentlyContinue
# Fallback: qualquer java com baixo uso apos kill request (Maestro CLI)
Start-Sleep -Seconds 1
Write-Host "stop_maestro_stale: cleanup feito"
