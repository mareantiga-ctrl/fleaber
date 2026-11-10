# Bateria AVISO — 12 PASS COM AVISO restantes (sem criar live).
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File tool\run_aviso_battery.ps1
#   powershell -ExecutionPolicy Bypass -File tool\run_aviso_battery.ps1 -SkipInstall -Test APP031
#
# Testes Maestro: APP031, APP055, APP056, APP083, APP086
# SKIP (PS/FB): SEC-008, SEC-013, SEC-019
# PENDENTE_LIVE: APP-218, SEC-020
# SEC-025: só se preflight achar disputa com oferta parcial
param(
  # Default: Oppo seller (TCL USB instavel). Override: -SellerDevice a698f0de
  [string]$SellerDevice = "95B6HUZ9GEGQPBRG",
  [string]$BuyerDevice = "d6pnqgz5jvnnbm9x",
  [string]$Test = "ALL",
  [switch]$SkipInstall,
  [switch]$SkipPreflight
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:PATH = "C:\src\flutter\bin;C:\Program Files\Git\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportRoot = Join-Path $root "tool\reports\battery_aviso_2026-08-23"
$shotDir = Join-Path $reportRoot "screenshots"
$logDir = Join-Path $reportRoot "logs"
$bdDir = Join-Path $reportRoot "bd"
New-Item -ItemType Directory -Force -Path $shotDir, $logDir, $bdDir | Out-Null

$masterLog = Join-Path $logDir "aviso_battery_$stamp.log"
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

Write-Log "=== AVISO MAESTRO BATTERY stamp=$stamp seller=$SellerDevice buyer=$BuyerDevice ==="

Install-Apk @($SellerDevice, $BuyerDevice)

$preflightJson = Join-Path $bdDir "preflight.json"
if (-not $SkipPreflight) {
  Write-Log "Preflight BD"
  dart run tool/aviso_battery_preflight.dart 2>&1 | Tee-Object -FilePath (Join-Path $logDir "preflight_run.log")
} else {
  Write-Log "SkipPreflight - usar $preflightJson existente"
}
if (-not (Test-Path $preflightJson)) {
  Write-Log "Preflight sem JSON - abort"
  exit 1
}

# Merge APP-056 seed se existir
$seed056 = Join-Path $bdDir "app056_seed.json"
if (Test-Path $seed056) {
  $seed = Get-Content $seed056 -Raw | ConvertFrom-Json
  if ($seed.chat_id -and $seed.order_id) {
    $prefRaw = Get-Content $preflightJson -Raw | ConvertFrom-Json
    $prefRaw.app056 = [pscustomobject]@{
      chat_id = $seed.chat_id
      order_id = $seed.order_id
      product_id = $seed.product_id
      order_status = $seed.status
      note = "from app056_seed.json mode=$($seed.mode)"
    }
    $prefRaw | ConvertTo-Json -Depth 10 | Set-Content $preflightJson -Encoding UTF8
    $env056 = Join-Path $bdDir "preflight.env"
    $envTxt = ""
    if (Test-Path $env056) { $envTxt = Get-Content $env056 -Raw }
    if ($envTxt -notmatch 'AVISO056_CHAT_ID=') {
      Add-Content $env056 "AVISO056_CHAT_ID=$($seed.chat_id)"
      Add-Content $env056 "AVISO056_ORDER_ID=$($seed.order_id)"
    } else {
      $envTxt = $envTxt -replace 'AVISO056_CHAT_ID=.*', "AVISO056_CHAT_ID=$($seed.chat_id)"
      $envTxt = $envTxt -replace 'AVISO056_ORDER_ID=.*', "AVISO056_ORDER_ID=$($seed.order_id)"
      if ($envTxt -notmatch 'AVISO056_ORDER_ID=') { $envTxt += "`nAVISO056_ORDER_ID=$($seed.order_id)" }
      Set-Content $env056 -Value $envTxt.Trim() -Encoding UTF8
    }
    Write-Log "APP-056 merged from seed order=$($seed.order_id)"
  }
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

$results = [ordered]@{}

# --- SKIP PS / FB ---
$results["SEC-008"] = "SKIP_PS"
$results["SEC-013"] = "SKIP_PS"
$results["SEC-019"] = "SKIP_PS"
Write-Log "SEC-008 / SEC-013 / SEC-019 = SKIP_PS (PS Reader / FB / extensao)"

# --- PENDENTE LIVE (BATATA: nao criar directo) ---
$results["APP-218"] = "PENDENTE_LIVE"
$results["SEC-020"] = "PENDENTE_LIVE"
Write-Log "APP-218 / SEC-020 = PENDENTE_LIVE (sem criar directo nesta bateria)"

# --- SEC-025 (so se houver disputa parcial) ---
if ($Test -eq "ALL" -or $Test -eq "SEC025") {
  if (-not $pref.sec025) {
    Write-Log "SEC-025 SKIP - sem disputa aberta com oferta parcial"
    $results["SEC-025"] = "SKIP"
  } else {
    Write-Log "SEC-025 caso BD encontrado - READY_BD"
    $results["SEC-025"] = "READY_BD"
  }
}

# --- Maestro flows ---
if ($Test -eq "ALL" -or $Test -eq "APP031") {
  if (-not $pref.app031) {
    Write-Log "APP-031 SKIP - sem aguarda_confirmacao"
    $results["APP-031"] = "SKIP"
  } else {
    Write-Log "APP-031 buyer Redmi order=$($pref.app031.order_id)"
    & powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\maestro_cooldown.ps1") -Device $BuyerDevice -Seconds 5
    $r = Invoke-MaestroFlow -Flow ".maestro/flows/aviso_031_buyer_no_confirmo.yaml" -LogLabel "aviso031" -Device $BuyerDevice -Port 7021
    Archive-Shots "aviso031_maestro" | Out-Null
    $results["APP-031"] = if ($r.Ok) { "PASS" } else { "FAIL" }
  }
}

if ($Test -eq "ALL" -or $Test -eq "APP086") {
  if (-not $pref.app086) {
    Write-Log "APP-086 SKIP - sem enviado"
    $results["APP-086"] = "SKIP"
  } else {
    Write-Log "APP-086 buyer Redmi order=$($pref.app086.order_id)"
    & powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\maestro_cooldown.ps1") -Device $BuyerDevice -Seconds 5
    $r = Invoke-MaestroFlow -Flow ".maestro/flows/aviso_086_buyer_enviado_chat.yaml" -LogLabel "aviso086" -Device $BuyerDevice -Port 7021
    Archive-Shots "aviso086_maestro" | Out-Null
    $results["APP-086"] = if ($r.Ok) { "PASS" } else { "FAIL" }
  }
}

if ($Test -eq "ALL" -or $Test -eq "APP083" -or $Test -eq "APP043") {
  if (-not $pref.app043) {
    Write-Log "APP-043/083 SKIP - sem product_bundle accepted"
    $results["APP-043"] = "SKIP"
    $results["APP-083"] = "SKIP"
  } else {
    Write-Log "APP-083/043 buyer bundle=$($pref.app043.bundle_id)"
    & powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\maestro_cooldown.ps1") -Device $BuyerDevice -Seconds 5
    $r = Invoke-MaestroFlow -Flow ".maestro/flows/aviso_083_bundle_chat.yaml" -LogLabel "aviso083" -Device $BuyerDevice -Port 7021
    Archive-Shots "aviso083_maestro" | Out-Null
    $tag = if ($r.Ok) { "PASS" } else { "FAIL" }
    $results["APP-043"] = $tag
    $results["APP-083"] = $tag
  }
}

if ($Test -eq "ALL" -or $Test -eq "APP055") {
  if (-not $pref.app055) {
    Write-Log "APP-055 SKIP - sem pago"
    $results["APP-055"] = "SKIP"
  } else {
    Write-Log "APP-055 seller Oppo order=$($pref.app055.order_id)"
    & powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\maestro_cooldown.ps1") -Device $SellerDevice -Seconds 5
    $r = Invoke-MaestroFlow -Flow ".maestro/flows/aviso_055_seller_ship_entry.yaml" -LogLabel "aviso055" -Device $SellerDevice -Port 7020
    Archive-Shots "aviso055_maestro" | Out-Null
    $results["APP-055"] = if ($r.Ok) { "PASS" } else { "FAIL" }
  }
}

if ($Test -eq "ALL" -or $Test -eq "APP056") {
  if (-not $pref.app056) {
    Write-Log "APP-056 SKIP - sem concluido/entregue"
    $results["APP-056"] = "SKIP"
  } else {
    Write-Log "APP-056 seller Oppo order=$($pref.app056.order_id)"
    & powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\maestro_cooldown.ps1") -Device $SellerDevice -Seconds 5
    $r = Invoke-MaestroFlow -Flow ".maestro/flows/aviso_056_seller_rececao_chat.yaml" -LogLabel "aviso056" -Device $SellerDevice -Port 7020
    Archive-Shots "aviso056_maestro" | Out-Null
    $results["APP-056"] = if ($r.Ok) { "PASS" } else { "FAIL" }
  }
}

foreach ($k in @("APP-031","APP-043","APP-055","APP-056","APP-083","APP-086","APP-218","SEC-008","SEC-013","SEC-019","SEC-020","SEC-025")) {
  if (-not $results.Contains($k)) { $results[$k] = "NOT_RUN" }
}

$jsonResults = ($results.GetEnumerator() | ForEach-Object { $_.Key + "=" + $_.Value }) -join "; "
Write-Log "RESULTS: $jsonResults"

$briefPath = Join-Path $reportRoot "BRIEFING_DIRECTOR.md"
@(
  "# Bateria AVISO $stamp",
  "",
  "Seller=$SellerDevice Buyer=$BuyerDevice",
  "",
  "APP-031=$($results['APP-031'])",
  "APP-043=$($results['APP-043'])",
  "APP-055=$($results['APP-055'])",
  "APP-056=$($results['APP-056'])",
  "APP-083=$($results['APP-083'])",
  "APP-086=$($results['APP-086'])",
  "APP-218=$($results['APP-218'])",
  "SEC-008=$($results['SEC-008'])",
  "SEC-013=$($results['SEC-013'])",
  "SEC-019=$($results['SEC-019'])",
  "SEC-020=$($results['SEC-020'])",
  "SEC-025=$($results['SEC-025'])",
  "",
  "Prints: $shotDir",
  "Logs: $logDir",
  "BD: $bdDir"
) | Set-Content -Path $briefPath -Encoding UTF8
Write-Log "Briefing: $briefPath"

$zipPath = Join-Path $reportRoot "audit_aviso_battery_$stamp.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path @($shotDir, $logDir, $bdDir, $briefPath) -DestinationPath $zipPath -Force
Write-Log "ZIP: $zipPath"

$anyFail = $results.Values | Where-Object { $_ -eq "FAIL" }
if ($anyFail) { exit 1 }
exit 0
