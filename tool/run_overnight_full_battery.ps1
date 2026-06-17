# Bateria nocturna completa — corre sozinha: build APK, BD, Maestro 2 emuladores, cross-surface UX, logs + prints.
#
# Deixar a correr antes de dormir (emuladores 5554+5556 ligados):
#   powershell -ExecutionPolicy Bypass -File tool\run_overnight_full_battery.ps1
#
# Se APK ja instalado:
#   powershell -ExecutionPolicy Bypass -File tool\run_overnight_full_battery.ps1 -SkipBuild
#
# So BD (sem emuladores):
#   powershell -ExecutionPolicy Bypass -File tool\run_overnight_full_battery.ps1 -SkipMaestro
param(
  [string]$SellerDevice = "emulator-5554",
  [string]$BuyerDevice = "emulator-5556",
  [string]$ExternalStamp = "",
  [switch]$SkipBuild,
  [switch]$SkipMaestro,
  [switch]$SkipFlutterTest
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:PATH = "C:\src\flutter\bin;C:\Program Files\Git\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"

$stamp = if ($ExternalStamp -ne "") { $ExternalStamp } else { Get-Date -Format "yyyyMMdd_HHmmss" }
$logDir = Join-Path $root "tool\logs\overnight_$stamp"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$masterLog = Join-Path $logDir "overnight_master.log"
$summaryFile = Join-Path $logDir "overnight_summary.txt"

function Write-Master([string]$Msg) {
  $line = "[$(Get-Date -Format 'HH:mm:ss')] $Msg"
  Write-Host $line
  Add-Content -Path $masterLog -Value $line
  Add-Content -Path $summaryFile -Value $line
}

function Test-EmulatorsReady {
  param([string[]]$Required)
  $adb = Join-Path $env:ANDROID_HOME "platform-tools\adb.exe"
  if (-not (Test-Path $adb)) {
    Write-Master "FAIL: adb nao encontrado"
    return $false
  }
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $out = & $adb devices 2>&1 | Out-String
  $ErrorActionPreference = $prevEap
  $missing = @()
  foreach ($d in $Required) {
    if ($out -notmatch [regex]::Escape($d) + '\s+device') { $missing += $d }
  }
  if ($missing.Count -gt 0) {
    Write-Master "FAIL: emuladores em falta: $($missing -join ', ')"
    Write-Master "adb devices:`n$out"
    return $false
  }
  Write-Master "Emuladores OK: $($Required -join ', ')"
  return $true
}

Write-Master "=== OVERNIGHT BATTERY stamp=$stamp ==="
Write-Master "Logs: $logDir"

if (-not $SkipMaestro) {
  if (-not (Test-EmulatorsReady @($SellerDevice, $BuyerDevice))) { exit 1 }
}

if (-not $SkipBuild -and -not $SkipMaestro) {
  Write-Master ">>> Build debug APK + install nos 2 emuladores"
  $buildLog = Join-Path $logDir "build_apk.log"
  flutter build apk --debug 2>&1 | Tee-Object -FilePath $buildLog
  if ($LASTEXITCODE -ne 0) {
    Write-Master "FAIL: flutter build apk"
    exit 1
  }
  $apk = Join-Path $root "build\app\outputs\flutter-apk\app-debug.apk"
  $adb = Join-Path $env:ANDROID_HOME "platform-tools\adb.exe"
  & $adb -s $SellerDevice install -r $apk 2>&1 | Out-File (Join-Path $logDir "install_seller.log")
  & $adb -s $BuyerDevice install -r $apk 2>&1 | Out-File (Join-Path $logDir "install_buyer.log")
  Write-Master "<<< APK instalado em $SellerDevice e $BuyerDevice"
} elseif ($SkipBuild) {
  Write-Master "SkipBuild - usa APK ja no emulador"
}

Write-Master ""
Write-Master ">>> Fase 1: BD + Maestro classico"
$batteryLog = Join-Path $logDir "battery_phase1.log"
$batteryArgs = @(
  "-File", "tool\run_full_automated_battery.ps1",
  "-SellerDevice", $SellerDevice,
  "-BuyerDevice", $BuyerDevice,
  "-ExternalStamp", $stamp,
  "-SkipInstall"
)
if ($SkipMaestro) { $batteryArgs += "-SkipMaestro" }
if ($SkipFlutterTest) { $batteryArgs += "-SkipFlutterTest" }

& powershell -ExecutionPolicy Bypass @batteryArgs *> $batteryLog
$phase1 = $LASTEXITCODE
Write-Master "<<< Fase 1 exit=$phase1"

if (-not $SkipMaestro) {
  Write-Master ""
  Write-Master ">>> Fase 2: Cross-surface UX CS01 a CS10"
  $csLog = Join-Path $logDir "battery_phase2_cross_surface.log"
  $csArgs = @(
    "-File", "tool\run_cross_surface_ux_battery.ps1",
    "-SellerDevice", $SellerDevice,
    "-BuyerDevice", $BuyerDevice,
    "-ExternalStamp", $stamp,
    "-SkipInstall"
  )
  & powershell -ExecutionPolicy Bypass @csArgs *> $csLog
  $phase2 = $LASTEXITCODE
  Write-Master "<<< Fase 2 exit=$phase2"
} else {
  $phase2 = 0
  Write-Master "SkipMaestro - fase 2 saltada"
}

# Copiar resumos para pasta overnight
$batterySummary = Get-ChildItem (Join-Path $root "tool\logs") -Filter "battery_$stamp.txt" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($batterySummary) { Copy-Item $batterySummary.FullName (Join-Path $logDir "battery_summary.txt") -Force }
$csSummary = Join-Path $root "tool\logs\cross_surface_$stamp\summary.txt"
if (Test-Path $csSummary) { Copy-Item $csSummary (Join-Path $logDir "cross_surface_summary.txt") -Force }

Write-Master ""
Write-Master "=== OVERNIGHT RESUMO ==="
Write-Master "Pasta logs: $logDir"
Write-Master "Prints cross-surface: tool\logs\cross_surface_$stamp\"
Write-Master "Prints maestro classico: tool\logs\screenshots_$stamp\"
Write-Master "Fase1 exit=$phase1 | Fase2 exit=$phase2"

if ($phase1 -ne 0 -or $phase2 -ne 0) { exit 1 }
exit 0
