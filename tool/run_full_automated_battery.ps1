# Bateria 100% automatica — sem Read-Host, sem checkpoints manuais.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File tool\run_full_automated_battery.ps1
#   powershell -ExecutionPolicy Bypass -File tool\run_full_automated_battery.ps1 -SkipMaestro
#   powershell -ExecutionPolicy Bypass -File tool\run_full_automated_battery.ps1 -ExternalStamp 20260615_220000
param(
  [string]$SellerDevice = "emulator-5554",
  [string]$BuyerDevice = "emulator-5556",
  [string]$ExternalStamp = "",
  [switch]$SkipMaestro,
  [switch]$SkipFlutterTest,
  [switch]$SkipInstall,
  [int]$FailFastPauseSec = 75,
  [switch]$NoFailFast
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$FailFast = -not $NoFailFast
. (Join-Path $PSScriptRoot "audit_battery_hooks.ps1")

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:PATH = "C:\src\flutter\bin;C:\Program Files\Git\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"

$logDir = Join-Path $root "tool\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stamp = if ($ExternalStamp -ne "") { $ExternalStamp } else { Get-Date -Format "yyyyMMdd_HHmmss" }
$summaryFile = Join-Path $logDir "battery_$stamp.txt"
$results = New-Object System.Collections.Generic.List[object]

function Write-Log([string]$Msg) {
  $line = "[$(Get-Date -Format 'HH:mm:ss')] $Msg"
  Write-Host $line
  Add-Content -Path $summaryFile -Value $line
}

function Invoke-BatteryStep {
  param(
    [string]$Name,
    [string]$TestId = "",
    [scriptblock]$Action,
    [string]$LogFile = ""
  )
  if ($TestId -ne "") {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\update_test_battery_status.ps1") `
      -TestId $TestId -Status "RUNNING" -Stamp $stamp | Out-Null
  }
  Write-Log ">>> $Name"
  $out = Join-Path $logDir "${stamp}_${Name.Replace(' ','_')}.log"
  if ($LogFile -ne "") { $out = $LogFile }
  try {
    & $Action *> $out
    $stepCode = $LASTEXITCODE
    $ok = ($stepCode -eq 0)
  } catch {
    $_ | Out-File -FilePath $out -Append
    $ok = $false
    $stepCode = 1
  }
  $r = if ($ok) { "PASS" } else { "FAIL" }
  $layer = if ($Name -match "integration|staging|flutter_test") { "BD/unit" } elseif ($Name -match "maestro|doc_apk|stock_ui|pull_|cross_surface") { "Android UX" } else { "other" }
  $results.Add([pscustomobject]@{ Test = $Name; Layer = $layer; Result = $r; Log = $out }) | Out-Null
  Write-Log "<<< $Name = $r ($layer)"
  if ($TestId -ne "") {
    $reason = if (-not $ok) { "exit=$stepCode ver log: $out" } else { "" }
    & powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\update_test_battery_status.ps1") `
      -TestId $TestId -Status $r -Stamp $stamp -FailReason:$reason -LogPath $out | Out-Null
  }
  return $ok
}

function Invoke-StepAudit {
  param(
    [string]$TestId,
    [string]$EvidenceDir,
    [string]$LogPath,
    [int]$MaestroExit,
    [string]$Layer = "UX",
    [string]$Scenario = ""
  )
  if ($TestId -eq "") { return $true }
  $audit = Invoke-PostTestAudit -TestId $TestId -Stamp $stamp -EvidenceDir $EvidenceDir `
    -LogPath $LogPath -MaestroExit $MaestroExit -Layer $Layer -Scenario $Scenario
  if (-not $audit) { return $true }
  Update-RegistryFromAudit -TestId $TestId -Stamp $stamp -AuditResult $audit -LogPath $LogPath
  return ($audit.Conclusion -ne "FAIL")
}

function Archive-MaestroScreenshots {
  param([string]$Label)
  $maestroRoot = Join-Path $env:USERPROFILE ".maestro\tests"
  if (-not (Test-Path $maestroRoot)) { return }
  $latest = Get-ChildItem $maestroRoot -Directory -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $latest) { return }
  $dest = Join-Path $logDir "screenshots_${stamp}\$Label"
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item -Path (Join-Path $latest.FullName "*") -Destination $dest -Recurse -Force -ErrorAction SilentlyContinue
  Write-Log "Screenshots arquivados: $dest"
  # Prints nomeados cs*.png na raiz do projecto
  Get-ChildItem -Path $root -Filter "cs*.png" -File -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dest $_.Name) -Force
    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
  }
}

Write-Log "=== BATERIA: BD + 2 emuladores (seller=$SellerDevice buyer=$BuyerDevice) ==="
Write-Log "stamp=$stamp | UX Maestro nos emuladores + BD servidor. PASS UX exige Maestro OK."

if (-not $SkipFlutterTest) {
  $ok = Invoke-BatteryStep "flutter_test_core" -TestId "T01" {
    flutter test `
      test/live_raffle_service_test.dart `
      test/live_public_chat_line_test.dart `
      test/live_ref_lineage_sheet_test.dart `
      test/live_ref_lineage_preview_service_test.dart
  }
  if ($FailFast -and -not $ok) { Write-Log "  FAIL-fast: pausa ${FailFastPauseSec}s e parar (flutter_test_core)"; Start-Sleep -Seconds $FailFastPauseSec; exit 1 }
} else {
  $results.Add([pscustomobject]@{ Test = "flutter_test_core"; Layer = "BD/unit"; Result = "SKIP"; Log = "" }) | Out-Null
}

$ok = Invoke-BatteryStep "live_ops_staging_check" -TestId "T02" {
  dart run tool/live_ops_staging_check.dart
}
if ($FailFast -and -not $ok) { Write-Log "  FAIL-fast: pausa ${FailFastPauseSec}s e parar (live_ops_staging_check)"; Start-Sleep -Seconds $FailFastPauseSec; exit 1 }

$ok = Invoke-BatteryStep "integration_stock" -TestId "T03" {
  dart run tool/regression_integration.dart --scenario stock --test-id A3
}
if ($FailFast -and -not $ok) { Write-Log "  FAIL-fast: pausa ${FailFastPauseSec}s e parar (integration_stock)"; Start-Sleep -Seconds $FailFastPauseSec; exit 1 }

$ok = Invoke-BatteryStep "integration_a3_r32_qty" -TestId "T04" {
  dart run tool/regression_integration.dart --scenario a3_r32_qty_alignment --test-id R32
}
if ($FailFast -and -not $ok) { Write-Log "  FAIL-fast: pausa ${FailFastPauseSec}s e parar (integration_a3_r32_qty)"; Start-Sleep -Seconds $FailFastPauseSec; exit 1 }

$ok = Invoke-BatteryStep "integration_cross_pool" -TestId "T05" {
  dart run tool/regression_integration.dart --scenario cross_pool_rr1 --test-id A340
}
if ($FailFast -and -not $ok) { Write-Log "  FAIL-fast: pausa ${FailFastPauseSec}s e parar (integration_cross_pool)"; Start-Sleep -Seconds $FailFastPauseSec; exit 1 }

$ok = Invoke-BatteryStep "integration_lineage" -TestId "T06" {
  dart run tool/regression_integration.dart --scenario logical_item_lineage --test-id A005
}
if ($FailFast -and -not $ok) { Write-Log "  FAIL-fast: pausa ${FailFastPauseSec}s e parar (integration_lineage)"; Start-Sleep -Seconds $FailFastPauseSec; exit 1 }

if (-not $SkipMaestro) {
  $maestroArgs = @("-File", "tool\run_maestro_automation.ps1", "-SellerDevice", $SellerDevice, "-BuyerDevice", $BuyerDevice)
  if ($SkipInstall) { $maestroArgs += "-SkipInstall" }
  $ok = Invoke-BatteryStep "maestro_automation_seller_buyer" -TestId "T07c" {
    powershell -ExecutionPolicy Bypass @maestroArgs
  }
  if ($FailFast -and -not $ok) { Write-Log "  FAIL-fast: pausa ${FailFastPauseSec}s e parar (maestro_automation_seller_buyer)"; Start-Sleep -Seconds $FailFastPauseSec; exit 1 }
  Archive-MaestroScreenshots "01_maestro_automation"
  $maestroLog = Join-Path $logDir "${stamp}_maestro_automation_seller_buyer.log"
  $auditOk = Invoke-StepAudit -TestId "T07c" -EvidenceDir (Join-Path $logDir "screenshots_$stamp\01_maestro_automation") `
    -LogPath $maestroLog -MaestroExit $(if ($ok) { 0 } else { 1 }) -Scenario "maestro_automation"
  if ($FailFast -and -not $auditOk) { Write-Log "  FAIL-fast: auditoria T07c"; Start-Sleep -Seconds $FailFastPauseSec; exit 1 }

  $docArgs = @("-File", "tool\run_doc_apk_tests.ps1", "-Device", $BuyerDevice)
  if ($SkipInstall) { $docArgs += "-SkipInstall" }
  $ok = Invoke-BatteryStep "doc_apk_buyer_flows" -TestId "T08b" {
    powershell -ExecutionPolicy Bypass @docArgs
  }
  if ($FailFast -and -not $ok) { Write-Log "  FAIL-fast: pausa ${FailFastPauseSec}s e parar (doc_apk_buyer_flows)"; Start-Sleep -Seconds $FailFastPauseSec; exit 1 }
  Archive-MaestroScreenshots "02_doc_apk_buyer"
  $docLog = Join-Path $logDir "${stamp}_doc_apk_buyer_flows.log"
  $auditOk = Invoke-StepAudit -TestId "T08b" -EvidenceDir (Join-Path $logDir "screenshots_$stamp\02_doc_apk_buyer") `
    -LogPath $docLog -MaestroExit $(if ($ok) { 0 } else { 1 }) -Scenario "doc_apk"
  if ($FailFast -and -not $auditOk) { Write-Log "  FAIL-fast: auditoria T08b"; Start-Sleep -Seconds $FailFastPauseSec; exit 1 }

  $ok = Invoke-BatteryStep "seller_stock_ui_maestro" -TestId "T09" {
    powershell -ExecutionPolicy Bypass -File tool\open_seller_test_studio.ps1 -Device $SellerDevice -SkipPrepare
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $flowArgs = @("-File", "tool\run_maestro_flow.ps1", "-FlowPath", ".maestro/flows/doc_03_seller_stock_add.yaml", "-Device", $SellerDevice, "-DriverHostPort", "7001")
    if ($SkipInstall) { $flowArgs += "-SkipInstall" }
    powershell -ExecutionPolicy Bypass @flowArgs
  }
  if ($FailFast -and -not $ok) { Write-Log "  FAIL-fast: pausa ${FailFastPauseSec}s e parar (seller_stock_ui_maestro)"; Start-Sleep -Seconds $FailFastPauseSec; exit 1 }
  Archive-MaestroScreenshots "03_seller_stock"
  $stockLog = Join-Path $logDir "${stamp}_seller_stock_ui_maestro.log"
  $auditOk = Invoke-StepAudit -TestId "T09" -EvidenceDir (Join-Path $logDir "screenshots_$stamp\03_seller_stock") `
    -LogPath $stockLog -MaestroExit $(if ($ok) { 0 } else { 1 }) -Scenario "seller_stock"
  if ($FailFast -and -not $auditOk) { Write-Log "  FAIL-fast: auditoria T09"; Start-Sleep -Seconds $FailFastPauseSec; exit 1 }

  $ok = Invoke-BatteryStep "pull_maestro_logs" -TestId "T10" {
    powershell -ExecutionPolicy Bypass -File tool\pull_maestro_studio_logs.ps1 -Device $SellerDevice
  }
  if ($FailFast -and -not $ok) { Write-Log "  FAIL-fast: pausa ${FailFastPauseSec}s e parar (pull_maestro_logs)"; Start-Sleep -Seconds $FailFastPauseSec; exit 1 }
} else {
  foreach ($n in @("maestro_automation_seller_buyer", "doc_apk_buyer_flows", "seller_stock_ui_maestro", "pull_maestro_logs")) {
    $results.Add([pscustomobject]@{ Test = $n; Layer = "Android UX"; Result = "SKIP"; Log = "" }) | Out-Null
  }
}

Write-Log ""
Write-Log "=== RESUMO FASE BD+MAESTRO ==="
$results | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Log $_.TrimEnd() }
$results | Format-Table -AutoSize | Out-File -Append $summaryFile

$fail = ($results | Where-Object { $_.Result -eq "FAIL" }).Count
Write-Log "Falhas: $fail"
Write-Log "Resumo: $summaryFile"
Write-Log "Nota: cross-surface UX (CS01 a CS10) corre em run_overnight_full_battery.ps1 fase 2"

if ($fail -gt 0) { exit 1 }
exit 0
