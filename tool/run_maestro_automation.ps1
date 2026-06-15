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

Write-Host 'Step 2/4: Flutter unit tests (raffle + chat)'
flutter test test/live_raffle_service_test.dart test/live_public_chat_line_test.dart

if ($SkipMaestro) {
  Write-Host 'SkipMaestro — a saltar flows UI.'
  dart run tool/maestro_verify_automation.dart --pending-only
  exit $LASTEXITCODE
}

$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:ANDROID_HOME = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$adbDir = Join-Path $env:ANDROID_HOME 'platform-tools'
$env:PATH = "$env:JAVA_HOME\bin;$adbDir;$env:PATH"

$sellerDev = $SellerDevice
$buyerDev = $BuyerDevice
if ($sellerDev -eq "" -or $buyerDev -eq "") {
  $envFile = Join-Path $root ".maestro\.env"
  Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -match '^MAESTRO_DEVICE_SELLER=(.+)$' -and $sellerDev -eq "") {
      $sellerDev = $Matches[1].Trim()
    }
    if ($line -match '^MAESTRO_DEVICE_BUYER=(.+)$' -and $buyerDev -eq "") {
      $buyerDev = $Matches[1].Trim()
    }
  }
}

function Invoke-MaestroFlow {
  param([string]$Flow, [string]$Device, [int]$DriverPort)
  $args = @("-File", "tool\run_maestro_flow.ps1", "-FlowPath", $Flow)
  if ($Device -ne "") { $args += @("-Device", $Device) }
  if ($DriverPort -gt 0) { $args += @("-DriverHostPort", "$DriverPort") }
  if ($SkipInstall) { $args += "-SkipInstall" }
  & powershell @args
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host "Step 3/4: Maestro seller harness (device=$sellerDev)"
Invoke-MaestroFlow -Flow ".maestro/flows/v2_seller_harness_accept.yaml" -Device $sellerDev -DriverPort 7001

Write-Host "Step 4/4: Maestro buyer rifa+saco (device=$buyerDev)"
Invoke-MaestroFlow -Flow ".maestro/flows/v2_buyer_raffle_bag.yaml" -Device $buyerDev -DriverPort 7002

Write-Host 'Step verify: BD'
dart run tool/maestro_verify_automation.dart

Write-Host 'AUTOMATION PASS (sem Stripe)'
