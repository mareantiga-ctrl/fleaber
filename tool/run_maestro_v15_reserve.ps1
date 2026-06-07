# V1.5 cenario 1: buyer reserva -> seller ve em A tratar.
# Requer 2 dispositivos ADB (2 emuladores ou emulador + telemovel).
#
# Configura em tool/live_ops_staging.env (recomendado):
#   MAESTRO_DEVICE_SELLER=emulator-5554
#   MAESTRO_DEVICE_BUYER=emulator-5558
# Nao usar emulator-5556 (AVD flutter_emulator) - Maestro falha login/UI.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File tool\run_maestro_v15_reserve.ps1
param(
  [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:PATH = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:ANDROID_HOME\emulator;$env:PATH"

$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
  Write-Host "adb nao encontrado."
  exit 1
}

Write-Host "=== Dispositivos ADB ==="
& $adb devices -l
$excludeUdids = @('emulator-5556')
$lines = @(& $adb devices | Where-Object { $_ -match "device$" -and $_ -notmatch "List of" })
$onlineUdids = @($lines | ForEach-Object { ($_ -split '\s+')[0] } | Where-Object { $_ -notin $excludeUdids })
if ($onlineUdids.Count -lt 2) {
  Write-Host ""
  Write-Host "ERRO: V1.5 precisa de 2 dispositivos ligados (seller + buyer)."
  Write-Host "  - Segundo emulador: Android Studio > Device Manager > Create/Start outro AVD"
  Write-Host "  - Ou telemovel USB com depuracao USB (adb devices deve listar 2 linhas device)"
  Write-Host "  - Define MAESTRO_DEVICE_SELLER/BUYER em tool/live_ops_staging.env"
  Write-Host "  - Recomendado: seller=emulator-5554 buyer=emulator-5558 (Pixel 10)"
  Write-Host "  - Evitar emulator-5556 (flutter_emulator)"
  exit 1
}

function Get-StagingValue([string]$key) {
  $p = Join-Path $root "tool\live_ops_staging.env"
  if (-not (Test-Path $p)) { return "" }
  foreach ($line in Get-Content $p) {
    if ($line -match "^$key=") {
      return ($line -split '=', 2)[1].Trim()
    }
  }
  return ""
}

function Set-MaestroEnvDevices([string]$sellerUdid, [string]$buyerUdid) {
  $p = Join-Path $root ".maestro\.env"
  $keep = @()
  if (Test-Path $p) {
    $skipKeys = @(
      'MAESTRO_DEVICE_SELLER', 'MAESTRO_DEVICE_BUYER',
      'MAESTRO_DRIVER_PORT_SELLER', 'MAESTRO_DRIVER_PORT_BUYER'
    )
    foreach ($line in Get-Content $p) {
      $t = $line.Trim()
      if ($t -eq "" -or $t.StartsWith("#")) { $keep += $line; continue }
      $k = ($t -split '=', 2)[0].Trim()
      if ($skipKeys -contains $k) { continue }
      $keep += $line
    }
  }
  $keep += "MAESTRO_DEVICE_SELLER=$sellerUdid"
  $keep += "MAESTRO_DEVICE_BUYER=$buyerUdid"
  $keep += "MAESTRO_DRIVER_PORT_SELLER=7001"
  $keep += "MAESTRO_DRIVER_PORT_BUYER=7002"
  Set-Content -Path $p -Value ($keep -join "`n") -Encoding utf8
}

Write-Host ""
Write-Host "=== Preparar env (--multi) ==="
dart run tool/maestro_prepare_live.dart --multi
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$deviceSeller = Get-StagingValue "MAESTRO_DEVICE_SELLER"
$deviceBuyer = Get-StagingValue "MAESTRO_DEVICE_BUYER"
if ($deviceSeller -eq "" -or $deviceSeller -in $excludeUdids) {
  if ($onlineUdids -contains 'emulator-5558') { $deviceSeller = 'emulator-5558' }
  elseif ($onlineUdids -contains 'emulator-5554') { $deviceSeller = 'emulator-5554' }
  else { $deviceSeller = $onlineUdids[0] }
}
if ($deviceBuyer -eq "" -or $deviceBuyer -in $excludeUdids) {
  if ($onlineUdids -contains 'emulator-5554' -and $deviceSeller -ne 'emulator-5554') {
    $deviceBuyer = 'emulator-5554'
  }
  elseif ($onlineUdids -contains 'emulator-5558' -and $deviceSeller -ne 'emulator-5558') {
    $deviceBuyer = 'emulator-5558'
  }
  else {
    $deviceBuyer = ($onlineUdids | Where-Object { $_ -ne $deviceSeller } | Select-Object -First 1)
  }
}
Set-MaestroEnvDevices $deviceSeller $deviceBuyer
Write-Host "Devices: seller=$deviceSeller buyer=$deviceBuyer (5556/flutter_emulator excluido)"

function Get-EnvValue([string]$key) {
  $p = Join-Path $root ".maestro\.env"
  $val = ""
  foreach ($line in Get-Content $p) {
    if ($line -match "^$key=") {
      $val = ($line -split '=', 2)[1].Trim()
    }
  }
  return $val
}

$deviceSeller = Get-EnvValue "MAESTRO_DEVICE_SELLER"
$deviceBuyer = Get-EnvValue "MAESTRO_DEVICE_BUYER"
$portSeller = [int](Get-EnvValue "MAESTRO_DRIVER_PORT_SELLER")
$portBuyer = [int](Get-EnvValue "MAESTRO_DRIVER_PORT_BUYER")
if ($portSeller -le 0) { $portSeller = 7001 }
if ($portBuyer -le 0) { $portBuyer = 7002 }

if ($deviceSeller -eq "" -or $deviceBuyer -eq "") {
  Write-Host "ERRO: nao foi possivel resolver MAESTRO_DEVICE_SELLER/BUYER."
  exit 1
}
if ($deviceSeller -eq $deviceBuyer) {
  Write-Host "ERRO: seller e buyer no mesmo dispositivo ($deviceSeller)."
  exit 1
}

$flowScript = Join-Path $root "tool\run_maestro_flow.ps1"

Write-Host ""
Write-Host "=== [1/3] Seller: iniciar directo + Operacao (device=$deviceSeller port=$portSeller) ==="
if ($SkipInstall) {
  & powershell -ExecutionPolicy Bypass -File $flowScript `
    -FlowPath ".maestro/multidevice/seller_studio_live.yaml" `
    -Device $deviceSeller `
    -DriverHostPort $portSeller `
    -SkipInstall
} else {
  & powershell -ExecutionPolicy Bypass -File $flowScript `
    -FlowPath ".maestro/multidevice/seller_studio_live.yaml" `
    -Device $deviceSeller `
    -DriverHostPort $portSeller
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "=== Sync live_id + catalogo na live activa do seller ==="
dart run tool/maestro_sync_seller_live.dart --wait-seconds=60
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Aguardar 2s antes do buyer..."
Start-Sleep -Seconds 2

Write-Host ""
Write-Host "=== [2/3] Buyer: reservar (device=$deviceBuyer port=$portBuyer) ==="
& powershell -ExecutionPolicy Bypass -File $flowScript `
  -FlowPath ".maestro/multidevice/buyer_login_and_reserve.yaml" `
  -Device $deviceBuyer `
  -DriverHostPort $portBuyer `
  -SkipInstall
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "=== [3/3] Seller: ver reserva em A tratar (device=$deviceSeller) ==="
& powershell -ExecutionPolicy Bypass -File $flowScript `
  -FlowPath ".maestro/multidevice/seller_sees_reservation.yaml" `
  -Device $deviceSeller `
  -DriverHostPort $portSeller `
  -SkipInstall
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "V1.5 cenario 1 PASS (buyer reserva -> seller A tratar)."
