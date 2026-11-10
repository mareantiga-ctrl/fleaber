# Reinicia adb, prepara emuladores e instala APK para Maestro estável.
# Uso: powershell -File tool\maestro_stabilize_android.ps1 [-SkipBuild] [-Devices emulator-5554,emulator-5556]
param(
  [string[]]$Devices = @("a698f0de", "emulator-5556"),
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:PATH = "C:\src\flutter\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:ANDROID_HOME\emulator;$env:PATH"
$env:MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED = "true"

$adb = Join-Path $env:ANDROID_HOME "platform-tools\adb.exe"
$maestroBat = Join-Path $root ".tools\maestro\maestro\bin\maestro.bat"

function Write-Step([string]$Msg) {
  Write-Host "[stabilize] $Msg"
}

if (-not (Test-Path $adb)) {
  Write-Host "adb nao encontrado em $adb"
  exit 1
}

Write-Step "Reiniciar adb server..."
& $adb kill-server 2>$null
Start-Sleep -Milliseconds 800
& $adb start-server | Out-Null
Start-Sleep -Seconds 2

$online = @()
foreach ($line in (& $adb devices)) {
  $t = $line.Trim()
  if ($t -match '^(\S+)\s+device$') {
    $online += $Matches[1]
  }
}
Write-Step "Devices online: $($online -join ', ')"
if ($online.Count -eq 0) {
  Write-Host "Nenhum emulador online. Abre Android Studio AVDs e volta a correr."
  exit 1
}

foreach ($d in $Devices) {
  if ($online -notcontains $d) {
    Write-Host "AVISO: $d nao esta online - ignorado"
    continue
  }
  Write-Step "Preparar $d ..."
  & $adb -s $d wait-for-device | Out-Null
  & $adb -s $d shell settings put global window_animation_scale 0 | Out-Null
  & $adb -s $d shell settings put global transition_animation_scale 0 | Out-Null
  & $adb -s $d shell settings put global animator_duration_scale 0 | Out-Null
  & $adb -s $d shell am force-stop pt.fleaber.app | Out-Null
  & $adb -s $d shell input keyevent KEYCODE_WAKEUP | Out-Null
}

if (-not $SkipBuild) {
  Write-Step "Build APK debug..."
  flutter build apk --debug
  if ($LASTEXITCODE -ne 0) { exit 1 }
}

$apk = Join-Path $root "build\app\outputs\flutter-apk\app-debug.apk"
if (-not (Test-Path $apk)) {
  Write-Host "APK em falta: $apk"
  exit 1
}

foreach ($d in $Devices) {
  if ($online -notcontains $d) { continue }
  Write-Step "Instalar APK em $d ..."
  & $adb -s $d install -r $apk
  if ($LASTEXITCODE -ne 0) {
    Write-Host "AVISO: install falhou em $d"
  }
}

if (Test-Path $maestroBat) {
  $probe = $Devices | Where-Object { $online -contains $_ } | Select-Object -First 1
  if ($probe) {
    Write-Step "Maestro hierarchy probe em $probe ..."
    & $maestroBat --device $probe hierarchy 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
      Write-Step "Maestro bridge OK em $probe"
    } else {
      Write-Host "AVISO: Maestro bridge falhou em $probe - tenta cold boot do AVD"
    }
  }
}

Write-Step "Pronto."
