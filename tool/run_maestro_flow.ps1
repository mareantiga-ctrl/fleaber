# Corre um flow Maestro com .maestro/.env e device/port opcionais.
# Uso:
#   powershell -File tool/run_maestro_flow.ps1 -FlowPath .maestro/multidevice/buyer_reserve_item.yaml
#   powershell -File tool/run_maestro_flow.ps1 -FlowPath .maestro/multidevice/seller_studio_live.yaml -Device emulator-5554 -DriverHostPort 7001
param(
  [Parameter(Mandatory = $true)]
  [string]$FlowPath,
  [string]$Device = "",
  [int]$DriverHostPort = 0,
  [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:PATH = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:ANDROID_HOME\emulator;$env:PATH"
$env:MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED = "true"

$maestroBat = Join-Path $root ".tools\maestro\maestro\bin\maestro.bat"
if (-not (Test-Path $maestroBat)) {
  Write-Host "Maestro nao encontrado em .tools/maestro. Ver docs/maestro-batata.md"
  exit 1
}

$envFile = Join-Path $root ".maestro\.env"
if (-not (Test-Path $envFile)) {
  Write-Host "Falta .maestro/.env - corre: dart run tool/maestro_prepare_live.dart --multi"
  exit 1
}

$envArgs = @()
Get-Content $envFile | ForEach-Object {
  $line = $_.Trim()
  if ($line -eq "" -or $line.StartsWith("#")) { return }
  $i = $line.IndexOf("=")
  if ($i -lt 1) { return }
  $key = $line.Substring(0, $i).Trim()
  $val = $line.Substring($i + 1).Trim()
  $envArgs += "-e"
  $envArgs += "${key}=${val}"
}

if ($Device -eq "") {
  $deviceFromEnv = (Get-Content $envFile | Where-Object { $_ -match '^MAESTRO_DEVICE_DEFAULT=' } | Select-Object -First 1)
  if ($deviceFromEnv) {
    $Device = ($deviceFromEnv -split '=', 2)[1].Trim()
  }
}

if (-not $SkipInstall) {
  $adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
  $apk = Join-Path $root "build\app\outputs\flutter-apk\app-debug.apk"
  if ((Test-Path $adb) -and (Test-Path $apk)) {
    if ($Device -ne "") {
      & $adb -s $Device install -r $apk 2>&1 | Out-Host
    } else {
      & $adb install -r $apk 2>&1 | Out-Host
    }
    if ($LASTEXITCODE -ne 0) {
      Write-Host "AVISO: install APK falhou (ex. storage). A usar APK ja no dispositivo."
    }
  }
}

$flowFull = if ([System.IO.Path]::IsPathRooted($FlowPath)) {
  $FlowPath
} else {
  Join-Path $root $FlowPath
}
if (-not (Test-Path $flowFull)) {
  Write-Host "Flow nao encontrado: $flowFull"
  exit 1
}

$maestroArgs = @(
  "test",
  "--config", (Join-Path $root ".maestro\config.yaml")
)
if ($DriverHostPort -gt 0) {
  $maestroArgs += "--driver-host-port"
  $maestroArgs += "$DriverHostPort"
}
if ($Device -ne "") {
  $maestroArgs += "--device"
  $maestroArgs += $Device
}
$maestroArgs += $envArgs
$maestroArgs += $flowFull

Write-Host "Maestro -> $flowFull (device=$Device port=$DriverHostPort)"
& $maestroBat @maestroArgs
exit $LASTEXITCODE
