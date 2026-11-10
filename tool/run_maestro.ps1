# Corre flows Maestro com variáveis de .maestro/.env
# Uso: powershell -File tool/run_maestro.ps1
#      powershell -File tool/run_maestro.ps1 -Flow v1_01_login_buyer_home.yaml
param(
  [string]$Flow = "",
  [string]$Device = "",
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
  Write-Host "Maestro nao encontrado em .tools\maestro. Ver docs/maestro-batata.md"
  exit 1
}

$envFile = Join-Path $root ".maestro\.env"
if (-not (Test-Path $envFile)) {
  Write-Host "A correr maestro_prepare_live..."
  dart run tool/maestro_prepare_live.dart
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

$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$apk = Join-Path $root "build\app\outputs\flutter-apk\app-debug.apk"
if (-not $SkipInstall -and (Test-Path $adb) -and (Test-Path $apk)) {
  if ($Device -ne "") {
    & $adb -s $Device install -r $apk 2>&1 | Out-Host
  } else {
    & $adb install -r $apk 2>&1 | Out-Host
  }
  if ($LASTEXITCODE -ne 0) {
    Write-Host "AVISO: install APK falhou (ex. storage). A usar APK ja no emulador."
  }
}

$target = if ($Flow -ne "") {
  Join-Path $root ".maestro\flows\$Flow"
} else {
  Join-Path $root ".maestro\flows"
}

$maestroArgs = @("test", "--config", (Join-Path $root ".maestro\config.yaml"))
if ($Device -ne "") {
  $maestroArgs += "--device"
  $maestroArgs += $Device
  $maestroArgs += "--driver-host-port"
  $maestroArgs += "7003"
}
$maestroArgs += $envArgs
$maestroArgs += $target

Write-Host "Maestro -> $target (device=$Device)"
& $maestroBat @maestroArgs
exit $LASTEXITCODE
