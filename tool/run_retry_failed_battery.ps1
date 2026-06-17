# Re-corre testes Fase 1 ainda em FAIL / DEEPLINK e actualiza registry + auditoria.
# Uso: powershell -ExecutionPolicy Bypass -File tool\run_retry_failed_battery.ps1 -SkipInstall
param(
  [string]$SellerDevice = "emulator-5554",
  [string]$BuyerDevice = "emulator-5556",
  [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
. (Join-Path $PSScriptRoot "audit_battery_hooks.ps1")

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:PATH = "C:\src\flutter\bin;C:\Program Files\Git\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = Join-Path $root "tool\logs\retry_$stamp"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$UxTimeoutSec = 300

function Write-Log([string]$Msg) {
  $line = "[$(Get-Date -Format 'HH:mm:ss')] $Msg"
  Write-Host $line
  Add-Content -Path (Join-Path $logDir "retry.log") -Value $line
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
  Get-ChildItem -Path $root -Filter "cs*.png" -File -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dest $_.Name) -Force
    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
  }
  return $dest
}

function Invoke-MaestroStep {
  param(
    [string]$Flow,
    [string]$Device,
    [int]$Port,
    [string]$LogLabel
  )
  $stepLog = Join-Path $logDir "${LogLabel}_run.log"
  $psArgs = @(
    "-File", (Join-Path $root "tool\run_maestro_flow.ps1"),
    "-FlowPath", $Flow,
    "-Device", $Device,
    "-DriverHostPort", "$Port"
  )
  if ($SkipInstall) { $psArgs += "-SkipInstall" }
  & (Join-Path $root "tool\run_ps_with_timeout.ps1") -TimeoutSec $UxTimeoutSec -LogFile $stepLog -PsArgs $psArgs | Out-Null
  return ($LASTEXITCODE -eq 0)
}

function Set-Battery {
  param(
    [string]$TestId,
    [string]$Status,
    [string]$LogPath = "",
    [string]$FailReason = "",
    [string]$UxNote = ""
  )
  & powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\update_test_battery_status.ps1") `
    -TestId $TestId -Status $Status -Stamp $stamp `
    -FailReason:$FailReason -LogPath $LogPath -UxNote:$UxNote | Out-Null
}

function Audit-And-Set {
  param(
    [string]$TestId,
    [string]$EvidenceDir,
    [string]$LogPath,
    [int]$MaestroExit,
    [string]$Scenario,
    [string]$Layer = "UX"
  )
  $audit = Invoke-PostTestAudit -TestId $TestId -Stamp $stamp -EvidenceDir $EvidenceDir `
    -LogPath $LogPath -MaestroExit $MaestroExit -Layer $Layer -Scenario $Scenario
  if ($audit) {
    Update-RegistryFromAudit -TestId $TestId -Stamp $stamp -AuditResult $audit -LogPath $LogPath
    return ($audit.Conclusion -ne "FAIL")
  }
  $status = if ($MaestroExit -eq 0) { "PASS" } else { "FAIL" }
  Set-Battery -TestId $TestId -Status $status -LogPath $LogPath
  return ($MaestroExit -eq 0)
}

Write-Log "=== RETRY FAILED BATTERY stamp=$stamp ==="

# --- T07a/T07b/T07c: chain seller + buyer (UX, sem deep link) ---
Write-Log ">>> T07a/T07b/T07c maestro automation"
dart run tool/maestro_prepare_live.dart 2>&1 | Tee-Object -FilePath (Join-Path $logDir "prepare.log") | Out-Null
if ($LASTEXITCODE -ne 0) {
  Set-Battery -TestId "T07c" -Status "FAIL" -FailReason "prepare BD"
  exit 1
}

& powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\maestro_cooldown.ps1") -Device $SellerDevice -Seconds 5
$sellerChainOk = Invoke-MaestroStep -Flow ".maestro/flows/v2_seller_automation_chain.yaml" `
  -Device $SellerDevice -Port 7001 -LogLabel "T07abc_seller_chain"
$sellerShots = Archive-Shots "T07abc_seller"
$sellerLog = Join-Path $logDir "T07abc_seller_chain_run.log"

if ($sellerChainOk) {
  Audit-And-Set -TestId "T07a" -EvidenceDir $sellerShots -LogPath $sellerLog `
    -MaestroExit 0 -Scenario "seller_harness_aceitar" | Out-Null
  Audit-And-Set -TestId "T07b" -EvidenceDir $sellerShots -LogPath $sellerLog `
    -MaestroExit 0 -Scenario "seller_stock" | Out-Null
} else {
  Set-Battery -TestId "T07a" -Status "FAIL" -LogPath $sellerLog -FailReason "seller chain fail"
  Set-Battery -TestId "T07b" -Status "FAIL" -LogPath $sellerLog -FailReason "seller chain fail"
}

& powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\maestro_cooldown.ps1") -Device $BuyerDevice -Seconds 8
$buyerOk = Invoke-MaestroStep -Flow ".maestro/flows/v2_buyer_raffle_bag.yaml" `
  -Device $BuyerDevice -Port 7002 -LogLabel "T07c_buyer"
$buyerShots = Archive-Shots "T07c_buyer"
$buyerLog = Join-Path $logDir "T07c_buyer_run.log"
Audit-And-Set -TestId "T07c" -EvidenceDir $buyerShots -LogPath $buyerLog `
  -MaestroExit $(if ($buyerOk) { 0 } else { 1 }) -Scenario "maestro_buyer" | Out-Null

# --- T08c: Doc #6 Pagar ---
Write-Log ">>> T08c Doc #6 Pagar"
& powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\maestro_cooldown.ps1") -Device $BuyerDevice -Seconds 5
dart run tool/maestro_prepare_live.dart 2>&1 | Out-Null
$t08cOk = Invoke-MaestroStep -Flow ".maestro/flows/v1_03_buyer_bag_sheet.yaml" `
  -Device $BuyerDevice -Port 7002 -LogLabel "T08c"
$t08cShots = Archive-Shots "T08c"
$t08cLog = Join-Path $logDir "T08c_run.log"
Audit-And-Set -TestId "T08c" -EvidenceDir $t08cShots -LogPath $t08cLog `
  -MaestroExit $(if ($t08cOk) { 0 } else { 1 }) -Scenario "doc_apk_bag_pagar" | Out-Null

# --- T08d: Doc #3 stock seller ---
Write-Log ">>> T08d Doc #3 stock"
& powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\stop_maestro_stale.ps1") | Out-Null
& powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\maestro_cooldown.ps1") -Device $SellerDevice -Seconds 10
dart run tool/maestro_prepare_live.dart 2>&1 | Out-Null
$navOk = Invoke-MaestroStep -Flow ".maestro/flows/open_seller_studio_nav.yaml" `
  -Device $SellerDevice -Port 7001 -LogLabel "T08d_nav"
$catalogOk = $false
$stockOk = $false
if ($navOk) {
  $catalogOk = Invoke-MaestroStep -Flow ".maestro/flows/open_seller_studio_catalog.yaml" `
    -Device $SellerDevice -Port 7001 -LogLabel "T08d_catalog"
}
if ($catalogOk) {
  $stockOk = Invoke-MaestroStep -Flow ".maestro/flows/doc_03_seller_stock_add.yaml" `
    -Device $SellerDevice -Port 7001 -LogLabel "T08d_stock"
}
$t08dOk = $navOk -and $catalogOk -and $stockOk
$t08dShots = Archive-Shots "T08d"
$t08dLog = Join-Path $logDir "T08d_stock_run.log"
Audit-And-Set -TestId "T08d" -EvidenceDir $t08dShots -LogPath $t08dLog `
  -MaestroExit $(if ($t08dOk) { 0 } else { 1 }) -Scenario "doc_apk_seller_stock" | Out-Null

# --- T13/T14: reclassificar (auditoria já PASS_COM_AVISO sem deeplink) ---
foreach ($tid in @("T13", "T14")) {
  Set-Battery -TestId $tid -Status "PASS_COM_AVISO" -UxNote "UX nav; auditoria sem deeplink"
}

Write-Log ""
Write-Log "=== FIM RETRY ==="
Write-Log "Logs: $logDir"
Write-Log "Resumo: tool\TEST_BATTERY_LIVE.md"

$fail = @($sellerChainOk, $buyerOk, $t08cOk, $t08dOk) | Where-Object { -not $_ }
if ($fail.Count -gt 0) { exit 1 }
exit 0
