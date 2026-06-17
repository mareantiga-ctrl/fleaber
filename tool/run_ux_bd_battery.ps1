# Bateria completa BD + UX Android (Maestro nos 2 emuladores + logs + prints).
#
# Cada cenario: Maestro mexe nos emuladores -> screenshots -> BD confirma servidor.
# PASS so se UX E BD passam. Ver terminal: linhas "UX [emulator-...] maestro ->".
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File tool\run_ux_bd_battery.ps1
#   powershell -ExecutionPolicy Bypass -File tool\run_ux_bd_battery.ps1 -SkipBuild
#   powershell -ExecutionPolicy Bypass -File tool\run_ux_bd_battery.ps1 -Scenario CS02,CS08
#
param(
  [string]$SellerDevice = "emulator-5554",
  [string]$BuyerDevice = "emulator-5556",
  [string]$Scenario = "",
  [switch]$SkipBuild,
  [switch]$SkipFlutterTest,
  [switch]$BdOnly
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = Join-Path $root "tool\logs\ux_bd_$stamp"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$masterLog = Join-Path $logDir "master.log"

function Write-Master([string]$Msg) {
  $line = "[$(Get-Date -Format 'HH:mm:ss')] $Msg"
  Write-Host $line
  Add-Content -Path $masterLog -Value $line
}

Write-Master "=== UX+BD BATTERY stamp=$stamp ==="
Write-Master "Logs: $logDir"
Write-Master "Seller=$SellerDevice Buyer=$BuyerDevice"

if ($BdOnly) {
  Write-Master ">>> So BD (sem emuladores)"
  $bdLog = Join-Path $logDir "bd_only.log"
  $bdArgs = @("-File", "tool\run_full_automated_battery.ps1", "-SkipMaestro", "-ExternalStamp", $stamp)
  if ($SkipFlutterTest) { $bdArgs += "-SkipFlutterTest" }
  & powershell -ExecutionPolicy Bypass @bdArgs *> $bdLog
  $code = $LASTEXITCODE
  Write-Master "<<< BD exit=$code"
  exit $code
}

$overnightArgs = @(
  "-File", "tool\run_overnight_full_battery.ps1",
  "-SellerDevice", $SellerDevice,
  "-BuyerDevice", $BuyerDevice,
  "-ExternalStamp", $stamp
)
if ($SkipBuild) { $overnightArgs += "-SkipBuild" }
if ($SkipFlutterTest) { $overnightArgs += "-SkipFlutterTest" }

if ($Scenario -ne "") {
  Write-Master "Cenarios filtrados: $Scenario (fase cross-surface)"
  if (-not $SkipBuild) {
    Write-Master ">>> Build APK (cenario parcial)"
    flutter build apk --debug 2>&1 | Tee-Object -FilePath (Join-Path $logDir "build.log")
    if ($LASTEXITCODE -ne 0) { exit 1 }
  }
  $csLog = Join-Path $logDir "cross_surface.log"
  $csArgs = @(
    "-File", "tool\run_cross_surface_ux_battery.ps1",
    "-SellerDevice", $SellerDevice,
    "-BuyerDevice", $BuyerDevice,
    "-ExternalStamp", $stamp,
    "-Scenario", $Scenario,
    "-SkipInstall"
  )
  & powershell -ExecutionPolicy Bypass @csArgs *> $csLog
  exit $LASTEXITCODE
}

& powershell -ExecutionPolicy Bypass @overnightArgs *> $masterLog
exit $LASTEXITCODE
