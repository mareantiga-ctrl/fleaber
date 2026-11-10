# Corrida 22 — Auth E2E (APP-002 / APP-003)
param(
  [string]$Device = "d6pnqgz5jvnnbm9x",
  [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$ts = Get-Date -Format "yyyyMMdd.HHmm"
$regEmail = "qa.c22.registo.$ts@axinoquaa.pt"
$regPass = "Qac22!23456"
$regName = "QA C22 Registo"
$resetEmail = "axinoqua@axinoquaa.pt"

$reportDir = Join-Path $root "tool\reports\battery_c22_2026-08-19"
New-Item -ItemType Directory -Path (Join-Path $reportDir "screenshots") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $reportDir "bd") -Force | Out-Null

$meta = @{
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  device = $Device
  registo_email = $regEmail
  reset_email = $resetEmail
}
$meta | ConvertTo-Json | Set-Content (Join-Path $reportDir "bd\c22_auth_run_meta.json")

$env:C22_REGISTO_EMAIL = $regEmail
$env:C22_REGISTO_PASSWORD = $regPass
$env:C22_RESET_EMAIL = $resetEmail

# Append to maestro .env for -e passthrough
$envFile = Join-Path $root ".maestro\.env"
$extra = @(
  "C22_REGISTO_EMAIL=$regEmail",
  "C22_REGISTO_PASSWORD=$regPass",
  "C22_RESET_EMAIL=$resetEmail"
)
foreach ($line in $extra) {
  $key = ($line -split '=')[0]
  $content = if (Test-Path $envFile) { Get-Content $envFile -Raw } else { "" }
  if ($content -match "(?m)^$key=") {
    $content = [regex]::Replace($content, "(?m)^$key=.*", $line)
  } else {
    if ($content -and -not $content.EndsWith("`n")) { $content += "`n" }
    $content += "$line`n"
  }
  Set-Content -Path $envFile -Value $content -NoNewline
}

Write-Host "=== APP-002 Registo E2E === email=$regEmail"
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb -s $Device shell pm clear pt.fleaber.app | Out-Null
Start-Sleep 2
$maestroArgs = @("-Flow", "_ronda_c22_app002_registo_e2e.yaml", "-Device", $Device)
if ($SkipInstall) { $maestroArgs += "-SkipInstall" }
& powershell -File (Join-Path $root "tool\run_maestro.ps1") @maestroArgs
$code002 = $LASTEXITCODE
if ($code002 -ne 0) {
  Write-Host "APP-002 Maestro FAIL exit=$code002"
  exit $code002
}

dart run tool/c22_auth_verify.dart registo $regEmail $regPass $regName
$code002bd = $LASTEXITCODE
if ($code002bd -ne 0) {
  Write-Host "APP-002 BD verify FAIL exit=$code002bd"
  exit $code002bd
}

Write-Host "=== APP-003 Reset senha (app action) === email=$resetEmail"
& $adb -s $Device shell pm clear pt.fleaber.app | Out-Null
Start-Sleep 2
$maestroArgs = @("-Flow", "_ronda_c22_app003_reset_e2e.yaml", "-Device", $Device, "-SkipInstall")
& powershell -File (Join-Path $root "tool\run_maestro.ps1") @maestroArgs
$code003 = $LASTEXITCODE
if ($code003 -ne 0) {
  Write-Host "APP-003 Maestro FAIL exit=$code003"
  exit $code003
}

dart run tool/c22_auth_verify.dart reset $resetEmail
$code003bd = $LASTEXITCODE

Write-Host "APP-002: PASS E2E"
if ($code003bd -eq 0) {
  Write-Host "APP-003: app action OK; nova senha via email continua PENDENTE"
} else {
  Write-Host "APP-003: BD verify FAIL"
}
exit 0
