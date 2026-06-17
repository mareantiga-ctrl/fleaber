# Fase 1 completa -> Fase 2 cross-surface (automatico, sem pausas).
# Uso: powershell -File tool\run_phase1_then_phase2.ps1 -SkipBuild
param(
  [string]$SellerDevice = "emulator-5554",
  [string]$BuyerDevice = "emulator-5556",
  [switch]$SkipBuild,
  [switch]$SkipFlutterTest,
  [int]$FailFastPauseSec = 75,
  [switch]$NoFailFast
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:PATH = "C:\src\flutter\bin;C:\Program Files\Git\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = Join-Path $root "tool\logs\chain_$stamp"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$masterLog = Join-Path $logDir "chain_master.log"

function Write-Chain([string]$Msg) {
  $line = "[$(Get-Date -Format 'HH:mm:ss')] $Msg"
  Write-Host $line
  Add-Content -Path $masterLog -Value $line
}

Write-Chain "=== CHAIN stamp=$stamp ==="
Write-Chain "Seller=$SellerDevice Buyer=$BuyerDevice"
Write-Chain "Acompanhar: tool\TEST_BATTERY_LIVE.md (actualizado apos cada teste)"

if (-not $SkipBuild) {
  Write-Chain ">>> Build APK"
  flutter build apk --debug 2>&1 | Tee-Object -FilePath (Join-Path $logDir "build.log")
  if ($LASTEXITCODE -ne 0) { Write-Chain "FAIL build"; exit 1 }
  $apk = Join-Path $root "build\app\outputs\flutter-apk\app-debug.apk"
  $adb = Join-Path $env:ANDROID_HOME "platform-tools\adb.exe"
  & $adb -s $SellerDevice install -r $apk | Out-Null
  & $adb -s $BuyerDevice install -r $apk | Out-Null
  Write-Chain "<<< APK instalado"
} else {
  Write-Chain "SkipBuild"
}

Write-Chain ""
Write-Chain ">>> FASE 1: BD + Maestro classico"
$p1Log = Join-Path $logDir "phase1.log"
$p1Args = @(
  "-File", "tool\run_full_automated_battery.ps1",
  "-SellerDevice", $SellerDevice,
  "-BuyerDevice", $BuyerDevice,
  "-ExternalStamp", $stamp,
  "-SkipInstall"
)
if ($SkipFlutterTest) { $p1Args += "-SkipFlutterTest" }

& powershell -ExecutionPolicy Bypass @p1Args *> $p1Log
$phase1 = $LASTEXITCODE
Write-Chain "<<< Fase 1 exit=$phase1 (log: $p1Log)"

if (-not $NoFailFast -and $phase1 -ne 0) {
  Write-Chain "FAIL-fast: parar para analisar prints/logs (pausa ${FailFastPauseSec}s) e corrigir antes da Fase 2."
  Start-Sleep -Seconds $FailFastPauseSec
  exit 1
}

Write-Chain ""
Write-Chain ">>> FASE 2: Cross-surface CS01-CS10"
$p2Log = Join-Path $logDir "phase2.log"
$p2Args = @(
  "-File", "tool\run_cross_surface_ux_battery.ps1",
  "-SellerDevice", $SellerDevice,
  "-BuyerDevice", $BuyerDevice,
  "-ExternalStamp", $stamp,
  "-SkipInstall"
)

& powershell -ExecutionPolicy Bypass @p2Args *> $p2Log
$phase2 = $LASTEXITCODE
Write-Chain "<<< Fase 2 exit=$phase2 (log: $p2Log)"

Write-Chain ""
Write-Chain "=== FIM CHAIN ==="
Write-Chain "Fase1=$phase1 Fase2=$phase2"
Write-Chain "Resumo UX: tool\TEST_BATTERY_LIVE.md"
Write-Chain "Logs: $logDir"

if ($phase1 -ne 0 -or $phase2 -ne 0) { exit 1 }
exit 0
