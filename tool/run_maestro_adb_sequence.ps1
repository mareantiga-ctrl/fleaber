# Sequência Maestro: login → adb deep link → asserts (openLink Maestro falha em foreground).
# Uso:
#   powershell -File tool/run_maestro_adb_sequence.ps1 `
#     -Device emulator-5554 -DriverHostPort 7001 `
#     -LoginFlow .maestro/subflows/login_seller.yaml `
#     -DeepLink "fleaber://fleaber.com/maestroSellerStudio?liveId=..." `
#     -AssertFlow .maestro/flows/v2_seller_harness_ops.yaml
param(
  [Parameter(Mandatory = $true)]
  [string]$Device,
  [Parameter(Mandatory = $true)]
  [string]$LoginFlow,
  [Parameter(Mandatory = $true)]
  [string]$DeepLink,
  [Parameter(Mandatory = $true)]
  [string]$AssertFlow,
  [int]$DriverHostPort = 7001
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

Write-Host "=== Maestro adb sequence (device=$Device port=$DriverHostPort) ==="

Write-Host "[1/3] Login flow..."
& powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\run_maestro_flow.ps1") `
  -FlowPath $LoginFlow -Device $Device -DriverHostPort $DriverHostPort
if ($LASTEXITCODE -ne 0) {
  Write-Host "FAIL: login (exit $LASTEXITCODE)"
  exit $LASTEXITCODE
}

$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
  Write-Host "FAIL: adb nao encontrado"
  exit 1
}

Write-Host "[2/3] adb deep link..."
$null = & $adb -s $Device shell am start -W -a android.intent.action.VIEW -d $DeepLink com.mycompany.fleaber 2>&1
Start-Sleep -Seconds 15

Write-Host "[3/3] Assert flow..."
& powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\run_maestro_flow.ps1") `
  -FlowPath $AssertFlow -Device $Device -DriverHostPort $DriverHostPort -SkipInstall
$code = $LASTEXITCODE
Write-Host "=== Fim (exit $code) ==="
exit $code
