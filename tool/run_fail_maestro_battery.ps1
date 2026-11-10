# Maestro APP-065 + APP-095 — TCL vendedor + Redmi comprador, prints/logs/BD/ZIP.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File tool\run_fail_maestro_battery.ps1
#   powershell -ExecutionPolicy Bypass -File tool\run_fail_maestro_battery.ps1 -SkipInstall -Test APP095
#
param(
  [string]$SellerDevice = "a698f0de",
  [string]$BuyerDevice = "d6pnqgz5jvnnbm9x",
  [string]$Test = "ALL",
  [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:PATH = "C:\src\flutter\bin;C:\Program Files\Git\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportRoot = Join-Path $root "tool\reports\battery_fail_2026-08-23"
$shotDir = Join-Path $reportRoot "screenshots"
$logDir = Join-Path $reportRoot "logs"
$bdDir = Join-Path $reportRoot "bd"
New-Item -ItemType Directory -Force -Path $shotDir, $logDir, $bdDir | Out-Null

$masterLog = Join-Path $logDir "fail_battery_$stamp.log"
$adb = Join-Path $env:ANDROID_HOME "platform-tools\adb.exe"

function Write-Log([string]$Msg) {
  $line = "[$(Get-Date -Format 'HH:mm:ss')] $Msg"
  Write-Host $line
  Add-Content -Path $masterLog -Value $line
}

function Merge-PreflightEnv {
  param([string]$PreflightEnvPath)
  $envFile = Join-Path $root ".maestro\.env"
  if (-not (Test-Path $envFile)) {
    dart run tool/maestro_prepare_live.dart 2>&1 | Out-Null
  }
  if (-not (Test-Path $envFile)) {
    Write-Log "FALTA .maestro/.env"
    exit 1
  }
  if (-not (Test-Path $PreflightEnvPath)) { return }
  $existing = @{}
  Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq "" -or $line.StartsWith("#")) { return }
    $i = $line.IndexOf("=")
    if ($i -lt 1) { return }
    $existing[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1).Trim()
  }
  Get-Content $PreflightEnvPath | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq "" -or $line.StartsWith("#")) { return }
    $i = $line.IndexOf("=")
    if ($i -lt 1) { return }
    $existing[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1).Trim()
  }
  $existing["MAESTRO_DEVICE_SELLER"] = $SellerDevice
  $existing["MAESTRO_DEVICE_BUYER"] = $BuyerDevice
  $existing["MAESTRO_DEVICE_DEFAULT"] = $SellerDevice
  if ($existing["MAESTRO_BUYER_ID"]) { }
  $lines = $existing.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }
  Set-Content -Path $envFile -Value ($lines -join "`n") -Encoding UTF8
}

function Archive-Shots([string]$Label) {
  $maestroRoot = Join-Path $env:USERPROFILE ".maestro\tests"
  if (-not (Test-Path $maestroRoot)) { return $null }
  $latest = Get-ChildItem $maestroRoot -Directory -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $latest) { return $null }
  $dest = Join-Path $logDir $Label
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item -Path (Join-Path $latest.FullName "*") -Destination $dest -Recurse -Force -ErrorAction SilentlyContinue
  Get-ChildItem -Path $shotDir -Filter "*.png" -File -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dest $_.Name) -Force -ErrorAction SilentlyContinue
  }
  return $dest
}

function Invoke-MaestroFlow {
  param(
    [string]$Flow,
    [string]$LogLabel,
    [string]$Device,
    [int]$Port
  )
  $stepLog = Join-Path $logDir "${LogLabel}_run.log"
  $psArgs = @(
    "-File", (Join-Path $root "tool\run_maestro_flow.ps1"),
    "-FlowPath", $Flow,
    "-Device", $Device,
    "-DriverHostPort", "$Port"
  )
  if ($SkipInstall) { $psArgs += "-SkipInstall" }
  & powershell -ExecutionPolicy Bypass @psArgs *> $stepLog
  $ok = ($LASTEXITCODE -eq 0)
  Write-Log "$LogLabel [$Device] maestro exit=$LASTEXITCODE"
  return @{ Ok = $ok; Log = $stepLog }
}

function Install-Apk([string[]]$Devices) {
  if ($SkipInstall) { return }
  $apk = Join-Path $root "build\app\outputs\flutter-apk\app-debug.apk"
  if (-not (Test-Path $apk)) {
    Write-Log "Build APK debug..."
    flutter build apk --debug 2>&1 | Tee-Object -FilePath (Join-Path $logDir "build.log") | Out-Null
    if ($LASTEXITCODE -ne 0) { exit 1 }
  }
  foreach ($d in $Devices) {
    Write-Log "Install APK -> $d"
    & $adb -s $d install -r $apk 2>&1 | Out-Null
  }
}

Write-Log "=== FAIL MAESTRO BATTERY stamp=$stamp seller=$SellerDevice buyer=$BuyerDevice ==="
Write-Log "APP-200-CREEP: PENDENTE ate novo directo (prep C27 A so)"

Install-Apk @($SellerDevice, $BuyerDevice)

Write-Log "Preflight BD"
dart run tool/fail_battery_preflight.dart 2>&1 | Tee-Object -FilePath (Join-Path $logDir "preflight_run.log") | Out-Null
$preflightJson = Join-Path $bdDir "preflight.json"
if (-not (Test-Path $preflightJson)) {
  Write-Log "Preflight sem JSON - abort"
  exit 1
}
$pref = Get-Content $preflightJson -Raw | ConvertFrom-Json
Merge-PreflightEnv -PreflightEnvPath (Join-Path $bdDir "preflight.env")

$envFile = Join-Path $root ".maestro\.env"
if ($pref.buyer_id) {
  $lines = Get-Content $envFile
  $hasBuyer = $false
  $newLines = foreach ($l in $lines) {
    if ($l -match '^MAESTRO_BUYER_ID=') {
      $hasBuyer = $true
      "MAESTRO_BUYER_ID=$($pref.buyer_id)"
    } else { $l }
  }
  if (-not $hasBuyer) { $newLines += "MAESTRO_BUYER_ID=$($pref.buyer_id)" }
  Set-Content -Path $envFile -Value ($newLines -join "`n") -Encoding UTF8
}

$results = @{}

if ($Test -eq "ALL" -or $Test -eq "APP065") {
  if (-not $pref.app065) {
    Write-Log "APP-065 SKIP - sem conjunto enviado na BD"
    $results["APP-065"] = "SKIP"
  } else {
    Write-Log "APP-065 Maestro comprador Redmi"
    & powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\maestro_cooldown.ps1") -Device $BuyerDevice -Seconds 5
    $r = Invoke-MaestroFlow -Flow ".maestro/flows/app065_buyer_bundle_enviado_collapsed.yaml" -LogLabel "app065" -Device $BuyerDevice -Port 7026
    Archive-Shots "app065_maestro" | Out-Null
    $results["APP-065"] = if ($r.Ok) { "PASS" } else { "FAIL" }
  }
}

if ($Test -eq "ALL" -or $Test -eq "APP095") {
  if (-not $pref.app095) {
    Write-Log "APP-095 SKIP - sem reserva_pendente limpa"
    $results["APP-095"] = "SKIP"
  } else {
    $orderId = $pref.app095.order_id
    Write-Log "APP-095 order=$orderId mode=$($pref.app095_mode)"
    dart run tool/app095_bd_snapshot.dart $orderId before 2>&1 | Tee-Object -FilePath (Join-Path $logDir "app095_bd_before.log") | Out-Null

    if ($pref.app095_mode -eq "accept_then_open") {
      Write-Log "APP-095 prep chat payload completo"
      dart run tool/c26_app061_prep_chat.dart $orderId 2>&1 | Tee-Object -FilePath (Join-Path $logDir "app095_prep_chat.log") | Out-Null

      & powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\maestro_cooldown.ps1") -Device $SellerDevice -Seconds 5
      Write-Log "APP-095 seller accept TCL"
      $rAccept = Invoke-MaestroFlow -Flow ".maestro/flows/app095_seller_accept_reserva.yaml" -LogLabel "app095_seller" -Device $SellerDevice -Port 7025
      Archive-Shots "app095_seller" | Out-Null

      dart run tool/app095_bd_snapshot.dart $orderId after_accept 2>&1 | Tee-Object -FilePath (Join-Path $logDir "app095_bd_after.log") | Out-Null

      if (-not $rAccept.Ok) {
        $results["APP-095"] = "FAIL"
      } else {
        & powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\maestro_cooldown.ps1") -Device $BuyerDevice -Seconds 8
        Write-Log "APP-095 buyer chat Redmi (sem lembrete imediato)"
        $rBuyer = Invoke-MaestroFlow -Flow ".maestro/flows/app095_buyer_no_immediate_reminder.yaml" -LogLabel "app095_buyer" -Device $BuyerDevice -Port 7026
        Archive-Shots "app095_buyer" | Out-Null
        $results["APP-095"] = if ($rBuyer.Ok) { "PASS" } else { "FAIL" }
      }
    } else {
      $rBuyer = Invoke-MaestroFlow -Flow ".maestro/flows/app095_buyer_no_immediate_reminder.yaml" -LogLabel "app095_buyer" -Device $BuyerDevice -Port 7026
      Archive-Shots "app095_buyer" | Out-Null
      $results["APP-095"] = if ($rBuyer.Ok) { "PASS" } else { "FAIL" }
    }
  }
}

$briefing = @"
# Fail battery Maestro — $stamp

## Dispositivos
- Vendedor: TCL ($SellerDevice)
- Comprador: Redmi ($BuyerDevice)

## APP-200-CREEP
**PENDENTE** — prep so C27 A; reteste creep com novo directo.

## Resultados auditados

| ID | Resultado | Notas |
|----|-----------|-------|
| APP-065 | $($results['APP-065']) | Card Conjunto fechado «Artigo Enviado» |
| APP-095 | $($results['APP-095']) | Pos-aceite: sem lembrete imediato no chat comprador |

## Fix aplicado nesta ronda
- Aceitar reserva: ``otherUserId`` resolvido via chat quando falta na rota (botao silencioso).
- Prep QA: payload ``reservation_request`` com buyer_id/seller_id.

## Evidencia
- Prints: $shotDir
- Logs: $logDir
- BD: $bdDir (preflight, app095_before, app095_after_accept)

"@

$briefPath = Join-Path $reportRoot "BRIEFING_DIRECTOR.md"
Set-Content -Path $briefPath -Value $briefing -Encoding UTF8
Write-Log "Briefing: $briefPath"

$zipPath = Join-Path $reportRoot "audit_fail_battery_$stamp.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path @($shotDir, $logDir, $bdDir, $briefPath) -DestinationPath $zipPath -Force
Write-Log "ZIP: $zipPath"

$anyFail = $results.Values | Where-Object { $_ -eq "FAIL" }
if ($anyFail) { exit 1 }
exit 0
