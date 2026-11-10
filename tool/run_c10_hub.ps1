# Corrida 10 - Hub ponta-a-ponta (TCL, sem directo). Maestro + prints ADB + snapshot BD.
param(
  [string]$Device = "a698f0de"
)

$ErrorActionPreference = "Continue"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:PATH = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"
$env:MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED = "true"

$maestro = Join-Path $root ".tools\maestro\maestro\bin\maestro.bat"
$adb = Join-Path $env:ANDROID_HOME "platform-tools\adb.exe"
$config = Join-Path $root ".maestro\config.yaml"
$dest = Join-Path $root "tool\reports\battery_c10_2026-08-18"
$shotDir = Join-Path $dest "screenshots"
$logDir = Join-Path $dest "logs"
New-Item -ItemType Directory -Force -Path $shotDir, $logDir, (Join-Path $dest "evidence") | Out-Null
$journal = Join-Path $logDir "c10_run.jsonl"
$runLog = Join-Path $logDir "c10_run.log"

function Write-C10Log([string]$msg) {
  $line = "[$(Get-Date -Format 'HH:mm:ss')] $msg"
  Write-Host $line
  Add-Content -Path $runLog -Value $line
}

function Write-C10Journal($obj) {
  ($obj | ConvertTo-Json -Compress) | Add-Content -Path $journal
}

function Save-C10Shot([string]$name) {
  $path = Join-Path $shotDir "$name.png"
  & $adb -s $Device shell screencap -p /sdcard/c10_run.png 2>$null | Out-Null
  & $adb -s $Device pull /sdcard/c10_run.png $path 2>$null | Out-Null
  Write-C10Log "print $name"
}

function Invoke-C10Maestro([string]$id, [string]$flowRel) {
  $flow = Join-Path $root $flowRel
  $outLog = Join-Path $logDir "$id.log"
  Write-C10Log "correr $id"
  Write-C10Journal @{ ts = (Get-Date).ToUniversalTime().ToString("o"); event = "start"; id = $id }
  & $maestro test --config $config --device $Device --driver-host-port 7010 $flow 2>&1 |
    Tee-Object -FilePath $outLog | Out-Host
  $code = $LASTEXITCODE
  Save-C10Shot "${id}_adb"
  Write-C10Journal @{ ts = (Get-Date).ToUniversalTime().ToString("o"); event = "end"; id = $id; exit = $code }
  Write-C10Log "$id exit $code"
  return $code
}

Write-C10Log "Corrida 10 - Z1 (voltar ao Perfil) + Hub, sem login novo, sem directo"
& $adb -s $Device devices
$codeZ1 = Invoke-C10Maestro "c10_z1" ".maestro\flows\_ronda_c10_z1_back.yaml"
if ($codeZ1 -ne 0) {
  Write-C10Log "PARAR no voltar ao Perfil (NAV-004)"
  exit 2
}
$code300 = Invoke-C10Maestro "c10_300" ".maestro\flows\_ronda_c10_300_sheet.yaml"
if ($code300 -ne 0) {
  Write-C10Log "PARAR no sheet FleaHub"
  exit 2
}
$codeTour = Invoke-C10Maestro "c10_tour" ".maestro\flows\_ronda_c10_hub_tour.yaml"
if ($codeTour -ne 0) {
  Write-C10Log "tour Hub falhou - snapshot BD na mesma"
}
Write-C10Log "snapshot BD"
dart run tool/c10_hub_snapshot.dart 2>&1 | Tee-Object -FilePath (Join-Path $logDir "c10_snapshot.log") | Out-Host
Write-C10Log "fim runner"
if ($codeTour -ne 0) { exit 2 }
exit 0
