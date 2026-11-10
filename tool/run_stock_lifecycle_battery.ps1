# Bateria STOCK LIFECYCLE v2 — caminho UX mínimo + cobertura completa + auditoria profunda.
#
# 4 fases: SL-A (5–6 Maestro numa sessão) → SL-B (BD batch) → SL-C (msgs) → SL-D (deep audit)
# Modo assisted (default): timeout curto + pausa operador sem recomeçar.
#
# Uso:
#   powershell -File tool\run_stock_lifecycle_battery.ps1
#   powershell -File tool\run_stock_lifecycle_battery.ps1 -Phase SL-A,SL-B
#   powershell -File tool\run_stock_lifecycle_battery.ps1 -ListOnly
param(
  [string]$SellerDevice = "",
  [string]$BuyerDevice = "",
  [string]$Phase = "",
  [string]$ExternalStamp = "",
  [int]$UxStepTimeoutSec = 300,
  [int]$UxStepTimeoutAssistedSec = 55,
  [switch]$SkipInstall,
  [switch]$SkipBd,
  [switch]$SkipAudit,
  [switch]$SkipMessages,
  [switch]$ListOnly,
  [switch]$NoAssisted,
  [switch]$NoFailFast
)

$AssistedMode = -not $NoAssisted
$FailFast = -not $NoFailFast

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
. (Join-Path $PSScriptRoot "audit_battery_hooks.ps1")
. (Join-Path $PSScriptRoot "maestro_assisted_helpers.ps1")

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:PATH = "C:\src\flutter\bin;C:\Program Files\Git\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"

$manifestPath = Join-Path $root "tool\stock_lifecycle_manifest.json"
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

if ($SellerDevice -eq "") { $SellerDevice = $manifest.devices.seller }
if ($BuyerDevice -eq "") { $BuyerDevice = $manifest.devices.buyer }

if ($ListOnly) {
  Write-Host "Cobertura: $($manifest.coverageMatrix)"
  $manifest.scenarios | ForEach-Object {
    $ux = if ($_.uxSteps) { "$($_.uxSteps.Count) passos Maestro" }
          elseif ($_.automation -eq "bd_batch") { "BD batch" }
          elseif ($_.automation -eq "messages_batch") { "Msgs batch" }
          elseif ($_.automation -eq "deep_audit") { "Deep audit" }
          else { $_.automation }
    [pscustomobject]@{ Id = $_.id; Name = $_.name; Layer = $ux; Registry = $_.registryId }
  } | Format-Table -AutoSize -Wrap
  exit 0
}

$stamp = if ($ExternalStamp -ne "") { $ExternalStamp } else { Get-Date -Format "yyyyMMdd_HHmmss" }
$shotRoot = Join-Path $root "tool\logs\stock_lifecycle_$stamp"
New-Item -ItemType Directory -Force -Path $shotRoot | Out-Null
$summaryFile = Join-Path $shotRoot "summary.txt"
$results = New-Object System.Collections.Generic.List[object]

Initialize-MaestroAssistedContext -Root $root -ShotRoot $shotRoot -SkipInstall:$SkipInstall `
  -AssistedMode:$AssistedMode -UxStepTimeoutSec $UxStepTimeoutSec -UxStepTimeoutAssistedSec $UxStepTimeoutAssistedSec

function Write-Log([string]$Msg) {
  $line = "[$(Get-Date -Format 'HH:mm:ss')] $Msg"
  Write-Host $line
  Add-Content -Path $summaryFile -Value $line
}

function Read-MaestroEnvKey {
  param([string]$Key)
  $envFile = Join-Path $root ".maestro\.env"
  if (-not (Test-Path $envFile)) { return "" }
  foreach ($line in Get-Content $envFile) {
    $t = $line.Trim()
    if ($t -match "^$Key=(.+)$") { return $Matches[1].Trim() }
  }
  return ""
}

function Invoke-PreStep {
  param([string]$Name)
  switch ($Name) {
    "prepare_live" {
      Write-Log "  preStep: maestro_prepare_live (único seed SL-A)..."
      dart run tool/maestro_prepare_live.dart
      return ($LASTEXITCODE -eq 0)
    }
    "edge_seed" {
      Write-Log "  preStep: stock_lifecycle_edge_seed (live isolada SL-E)..."
      dart run tool/stock_lifecycle_edge_seed.dart
      return ($LASTEXITCODE -eq 0)
    }
    "cross_pool_ui_seed" {
      Write-Log "  preStep: stock_lifecycle_cross_pool_ui_seed (SL-G)..."
      dart run tool/stock_lifecycle_cross_pool_ui_seed.dart
      return ($LASTEXITCODE -eq 0)
    }
    default { return $true }
  }
}

function Invoke-PostStep {
  param([string]$Name)
  switch ($Name) {
    "restore_env" {
      Write-Log "  postStep: restore MAESTRO_LIVE_ID (sessão SL-A)..."
      dart run tool/stock_lifecycle_restore_env.dart
      return ($LASTEXITCODE -eq 0)
    }
    default { return $true }
  }
}

function Invoke-BdScenario {
  param([string]$Name)
  if ($SkipBd -or [string]::IsNullOrWhiteSpace($Name)) { return $true }
  $liveId = Read-MaestroEnvKey "MAESTRO_LIVE_ID"
  if ($liveId -ne "") { $env:MAESTRO_LIVE_ID = $liveId }
  dart run tool/regression_integration.dart --scenario $Name 2>&1 | Tee-Object -FilePath (Join-Path $shotRoot "${Name}_bd.log") | Out-Null
  return ($LASTEXITCODE -eq 0)
}

function Invoke-CheckpointAudit {
  param(
    [string]$TestId,
    [string]$StepId,
    [string]$ScenarioId
  )
  if ($SkipAudit) { return $null }
  $liveId = Read-MaestroEnvKey "MAESTRO_LIVE_ID"
  Invoke-StockBdSnapshot -Label "${ScenarioId}_${StepId}" -LiveId $liveId | Out-Null
  $logHint = Join-Path $shotRoot "${ScenarioId}_${StepId}_run.log"
  return Invoke-PostTestAudit -TestId "${TestId}_${StepId}" -Stamp $stamp `
    -EvidenceDir $shotRoot -LogPath $logHint -MaestroExit 0 -Layer "UX+BD" -Scenario "${ScenarioId}_${StepId}"
}

function Invoke-SlAUxChain {
  param($Scenario)
  $testId = [string]$Scenario.registryId
  $allOk = $true
  $anyAssisted = $false

  foreach ($step in $Scenario.uxSteps) {
    $sid = [string]$step.id
    Write-Log "  -- UX step $sid --"
    $sellerOk = $true
    $buyerOk = $true
    $sellerAssist = $false
    $buyerAssist = $false

    if ($step.sellerFlow) {
      $hint = [string]$step.sellerHint
      $r = Invoke-MaestroStepAssisted -Flow $step.sellerFlow -Device $SellerDevice -Port 7001 `
        -ShotLabel "$($Scenario.id)_${sid}_seller" -PhaseId "$($Scenario.id)_$sid" -OperatorHint $hint
      $sellerOk = [bool]$r.Ok
      $sellerAssist = [bool]$r.OperatorAssisted
    }
    if ($step.buyerFlow) {
      $hint = [string]$step.buyerHint
      $r = Invoke-MaestroStepAssisted -Flow $step.buyerFlow -Device $BuyerDevice -Port 7002 `
        -ShotLabel "$($Scenario.id)_${sid}_buyer" -PhaseId "$($Scenario.id)_$sid" -OperatorHint $hint
      $buyerOk = [bool]$r.Ok
      $buyerAssist = [bool]$r.OperatorAssisted
    }

    if ($sellerAssist -or $buyerAssist) { $anyAssisted = $true }
    if (-not $sellerOk -or -not $buyerOk) { $allOk = $false }

    if ($step.bdScenario) {
      $bdOk = Invoke-BdScenario -Name $step.bdScenario
      if (-not $bdOk) { $allOk = $false }
    }

    if ($Scenario.checkpointAudit -eq $true) {
      $audit = Invoke-CheckpointAudit -TestId $testId -StepId $sid -ScenarioId $Scenario.id
      if ($audit -and $audit.Conclusion -eq "FAIL") { $allOk = $false }
    }
  }

  if ($Scenario.postBd) {
    $bdOk = Invoke-BdScenario -Name $Scenario.postBd
    if (-not $bdOk) { $allOk = $false }
  }

  Pull-DeviceStudioLogs -Device $SellerDevice -DestLabel "$($Scenario.id)_seller_studio.log"
  Pull-DeviceStudioLogs -Device $BuyerDevice -DestLabel "$($Scenario.id)_buyer_studio.log"

  return @{ Ok = $allOk; Assisted = $anyAssisted }
}

function Pull-DeviceStudioLogs {
  param([string]$Device, [string]$DestLabel)
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  & powershell -ExecutionPolicy Bypass -File tool\pull_maestro_studio_logs.ps1 -Device $Device 2>&1 | Out-Null
  $ErrorActionPreference = $prevEap
  $src = Join-Path $root "tool\logs\maestro_studio.log"
  if (Test-Path $src) { Copy-Item $src (Join-Path $shotRoot $DestLabel) -Force }
}

function Invoke-BdBatch {
  param($Scenario)
  Write-Log "  BD batch (1 processo, $($Scenario.matrixIds -join ', '))..."
  dart run tool/stock_lifecycle_bd_batch.dart 2>&1 | Tee-Object -FilePath (Join-Path $shotRoot "bd_batch.log") | Out-Null
  return ($LASTEXITCODE -eq 0)
}

function Invoke-MessagesBatch {
  param($Scenario)
  if ($SkipMessages) {
    Write-Log "  SKIP messages (-SkipMessages)"
    return $true
  }
  $allOk = $true
  foreach ($ms in $Scenario.messageSteps) {
    $cmd = [string]$ms.cmd
    $args = @($ms.args | ForEach-Object { [string]$_ })
    Write-Log "  MSG: $cmd $($args -join ' ')"
    if ($cmd -eq "flutter") {
      & flutter @args 2>&1 | Tee-Object -FilePath (Join-Path $shotRoot "msg_humanizer.log") | Out-Null
    } else {
      & dart @args 2>&1 | Tee-Object -Append -FilePath (Join-Path $shotRoot "msg_batch.log") | Out-Null
    }
    if ($LASTEXITCODE -ne 0) { $allOk = $false }
  }
  return $allOk
}

function Invoke-EdgeSuite {
  param($Scenario)
  $bdOk = $true
  if ($Scenario.edgeBatch) {
    Write-Log "  Edge BD batch..."
    dart run $($Scenario.edgeBatch) 2>&1 | Tee-Object -FilePath (Join-Path $shotRoot "edge_batch.log") | Out-Null
    $bdOk = ($LASTEXITCODE -eq 0)
  }
  $chain = Invoke-SlAUxChain -Scenario $Scenario
  return @{ Ok = ([bool]$chain.Ok -and $bdOk); Assisted = [bool]$chain.Assisted }
}

function Invoke-HubFunctional {
  param($Scenario)
  $script = [string]$Scenario.hubScript
  if ($script -eq "") { $script = "tool/hub_publish_staging_functional.dart" }
  Write-Log "  Hub functional: $script"
  dart run $script 2>&1 | Tee-Object -FilePath (Join-Path $shotRoot "hub_publish.log") | Out-Null
  return ($LASTEXITCODE -eq 0)
}

function Invoke-CrossPoolUi {
  param($Scenario)
  $chain = Invoke-SlAUxChain -Scenario $Scenario
  return @{ Ok = [bool]$chain.Ok; Assisted = [bool]$chain.Assisted }
}

$filter = @()
if ($Phase -ne "") { $filter = $Phase.Split(",") | ForEach-Object { $_.Trim().ToUpper() } }

Write-Log "=== STOCK LIFECYCLE v3 (7 fases, Stripe excluído) ==="
Write-Log "Modo: $(if ($AssistedMode) { "ASSISTED (${UxStepTimeoutAssistedSec}s + pausa)" } else { "AUTO" })"
Write-Log "Cobertura: tool/stock_lifecycle_coverage.json"
Write-Log "Evidências: $shotRoot"

foreach ($sc in $manifest.scenarios) {
  if ($filter.Count -gt 0 -and ($filter -notcontains $sc.id)) { continue }

  Write-Log ""
  Write-Log ">>> $($sc.id) $($sc.name)"
  $testId = [string]$sc.registryId
  if ($testId -eq "") { $testId = $sc.id }

  & powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\update_test_battery_status.ps1") `
    -TestId $testId -Status "RUNNING" -Stamp $stamp | Out-Null

  if ($sc.preStep) {
    if (-not (Invoke-PreStep -Name $sc.preStep)) {
      $results.Add([pscustomobject]@{ Id = $sc.id; Result = "FAIL"; Reason = "preStep" }) | Out-Null
      continue
    }
  }

  $uxOk = $true
  $assisted = $false
  $bdOk = $true

  switch ([string]$sc.automation) {
    "bd_batch" {
      $bdOk = Invoke-BdBatch -Scenario $sc
      $uxOk = $true
    }
    "messages_batch" {
      $uxOk = Invoke-MessagesBatch -Scenario $sc
    }
    "deep_audit" {
      $uxOk = Invoke-DeepAudit -Scenario $sc
    }
    "edge_suite" {
      $r = Invoke-EdgeSuite -Scenario $sc
      $uxOk = [bool]$r.Ok
      $assisted = [bool]$r.Assisted
      $bdOk = $uxOk
    }
    "hub_functional" {
      $uxOk = Invoke-HubFunctional -Scenario $sc
      $bdOk = $uxOk
    }
    "cross_pool_ui" {
      $r = Invoke-CrossPoolUi -Scenario $sc
      $uxOk = [bool]$r.Ok
      $assisted = [bool]$r.Assisted
    }
    default {
      if ($sc.uxSteps) {
        $chain = Invoke-SlAUxChain -Scenario $sc
        $uxOk = [bool]$chain.Ok
        $assisted = [bool]$chain.Assisted
      }
    }
  }

  if ($sc.postStep) {
    Invoke-PostStep -Name $sc.postStep | Out-Null
  }

  $allOk = $uxOk -and $bdOk
  $r = if ($allOk) { if ($assisted) { "PASS_COM_AVISO" } else { "PASS" } } else { "FAIL" }
  $tag = "ux=$uxOk bd=$bdOk assisted=$assisted"
  $results.Add([pscustomobject]@{ Id = $sc.id; Result = $r; Tag = $tag }) | Out-Null
  Write-Log "<<< $($sc.id) = $r | $tag"

  & powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\update_test_battery_status.ps1") `
    -TestId $testId -Status $r -Stamp $stamp -UxNote:$tag | Out-Null

  if ($FailFast -and $r -eq "FAIL") {
    Write-Log "  FAIL-fast: pausa 15s — relançar -Phase $($sc.id),..."
    Start-Sleep -Seconds 15
    exit 1
  }
}

Archive-NamedScreenshotsShared (Join-Path $shotRoot "_orphan_png")

Write-Log ""
Write-Log "=== RESUMO (7 fases SL-A…SL-G + SL-D audit) ==="
$results | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Log $_.TrimEnd() }
$fail = ($results | Where-Object { $_.Result -eq "FAIL" }).Count
Write-Log "FAIL=$fail | $shotRoot"

if ($fail -gt 0) { exit 1 }
exit 0
