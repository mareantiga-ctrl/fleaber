# Automação Maestro V2 — sem Stripe, sem câmara no seller.
# Uso: powershell -File tool/run_maestro_automation.ps1
#      powershell -File tool/run_maestro_automation.ps1 -SkipMaestro  (só prepare + testes)
param(
  [string]$SellerDevice = "",
  [string]$BuyerDevice = "",
  [switch]$SkipMaestro,
  [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

Write-Host 'Step 1/4: Prepare staging (live + rifa + reserva pending)'
dart run tool/maestro_prepare_live.dart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host 'Step 2/4: Flutter unit tests (raffle + chat)'
flutter test test/live_raffle_service_test.dart test/live_public_chat_line_test.dart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($SkipMaestro) {
  Write-Host 'SkipMaestro — a saltar flows UI.'
  dart run tool/maestro_verify_automation.dart --pending-only
  exit $LASTEXITCODE
}

$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:ANDROID_HOME = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$adbDir = Join-Path $env:ANDROID_HOME 'platform-tools'
$env:PATH = "$env:JAVA_HOME\bin;$adbDir;$env:PATH"

function Read-MaestroEnv {
  param([string]$Key)
  $envFile = Join-Path $root ".maestro\.env"
  if (-not (Test-Path $envFile)) { return "" }
  foreach ($line in Get-Content $envFile) {
    $t = $line.Trim()
    if ($t -match "^$Key=(.+)$") { return $Matches[1].Trim() }
  }
  return ""
}

$sellerDev = $SellerDevice
$buyerDev = $BuyerDevice
if ($sellerDev -eq "") { $sellerDev = Read-MaestroEnv 'MAESTRO_DEVICE_SELLER' }
if ($buyerDev -eq "") { $buyerDev = Read-MaestroEnv 'MAESTRO_DEVICE_BUYER' }
if ($sellerDev -eq "") { $sellerDev = 'emulator-5554' }
if ($buyerDev -eq "") { $buyerDev = 'emulator-5556' }

function Invoke-MaestroFlow {
  param([string]$Flow, [string]$Device, [int]$DriverPort)
  $flowArgs = @("-File", "tool\run_maestro_flow.ps1", "-FlowPath", $Flow)
  if ($Device -ne "") { $flowArgs += @("-Device", $Device) }
  if ($DriverPort -gt 0) { $flowArgs += @("-DriverHostPort", "$DriverPort") }
  if ($SkipInstall) { $flowArgs += "-SkipInstall" }
  & powershell -ExecutionPolicy Bypass @flowArgs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host "Step 3/4: Maestro seller harness + stock (device=$sellerDev, sessão única)"
Invoke-MaestroFlow -Flow ".maestro/flows/v2_seller_automation_chain.yaml" -Device $sellerDev -DriverPort 7001

& powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\maestro_cooldown.ps1") -Device $sellerDev -Seconds 5

& powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\maestro_cooldown.ps1") -Device $buyerDev -Seconds 8

Write-Host "Step 4/4: Maestro buyer rifa+saco (device=$buyerDev)"
Invoke-MaestroFlow -Flow ".maestro/flows/v2_buyer_raffle_bag.yaml" -Device $buyerDev -DriverPort 7002

Write-Host 'Step verify: BD'
dart run tool/maestro_verify_automation.dart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host 'AUTOMATION PASS (sem Stripe)'
