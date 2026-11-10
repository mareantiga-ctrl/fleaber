# Abre o painel vendedor usado nos testes (navegacao UX, sem deep link).
# Uso: powershell -ExecutionPolicy Bypass -File tool\open_seller_test_studio.ps1
param(
  [string]$Device = "emulator-5554",
  [string]$ExpandCategory = "catalog",
  [switch]$SkipPrepare,
  [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:PATH = "C:\src\flutter\bin;C:\Program Files\Git\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"

if (-not $SkipPrepare) {
  Write-Host ">>> Preparar live staging + .maestro/.env"
  dart run tool/maestro_prepare_live.dart
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$envFile = Join-Path $root ".maestro\.env"
if (-not (Test-Path $envFile)) {
  Write-Host "FAIL: .maestro/.env em falta"
  exit 1
}

Write-Host ""
Write-Host ">>> Login vendedor + navegacao UX ate painel operacional" -ForegroundColor Cyan
Write-Host "    Device: $Device"
Write-Host ""

$flowArgs = @(
  "-File", "tool\run_maestro_flow.ps1",
  "-FlowPath", ".maestro/flows/open_seller_studio_ux.yaml",
  "-Device", $Device,
  "-DriverHostPort", "7001"
)
if ($SkipInstall) { $flowArgs += "-SkipInstall" }

& powershell -ExecutionPolicy Bypass @flowArgs
$code = $LASTEXITCODE

Write-Host ""
Write-Host "Log apos reproduzir bug:"
Write-Host "  powershell -File tool\pull_maestro_studio_logs.ps1 -Device $Device"

exit $code
