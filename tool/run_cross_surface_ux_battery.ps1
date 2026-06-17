# Bateria UX cross-surface: Maestro nos 2 emuladores + screenshot por passo + BD + logs.
# Uso:
#   powershell -File tool\run_cross_surface_ux_battery.ps1
#   powershell -File tool\run_cross_surface_ux_battery.ps1 -Scenario CS02,CS05
#   powershell -File tool\run_cross_surface_ux_battery.ps1 -ListOnly
#   powershell -File tool\run_cross_surface_ux_battery.ps1 -ExternalStamp 20260615_220000
param(
  [string]$SellerDevice = "emulator-5554",
  [string]$BuyerDevice = "emulator-5556",
  [string]$Scenario = "",
  [string]$ExternalStamp = "",
  [int]$UxStepTimeoutSec = 300,
  [switch]$SkipInstall,
  [switch]$SkipBd,
  [switch]$ListOnly,
  [int]$FailFastPauseSec = 75,
  [switch]$NoFailFast
)

$FailFast = -not $NoFailFast

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
. (Join-Path $PSScriptRoot "audit_battery_hooks.ps1")

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:PATH = "C:\src\flutter\bin;C:\Program Files\Git\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"

$manifestPath = Join-Path $root "tool\cross_surface_ux_manifest.json"
if (-not (Test-Path $manifestPath)) {
  Write-Host "FAIL: falta $manifestPath"
  exit 1
}
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

if ($ListOnly) {
  $manifest.scenarios | ForEach-Object {
    [pscustomobject]@{
      Id = $_.id
      Name = $_.name
      BD = $_.status
      UX = $_.statusUx
      Automation = $_.automation
      Gap = $_.gap
    }
  } | Format-Table -AutoSize -Wrap
  exit 0
}

$stamp = if ($ExternalStamp -ne "") { $ExternalStamp } else { Get-Date -Format "yyyyMMdd_HHmmss" }
$shotRoot = Join-Path $root "tool\logs\cross_surface_$stamp"
New-Item -ItemType Directory -Force -Path $shotRoot | Out-Null
$summaryFile = Join-Path $shotRoot "summary.txt"
$results = New-Object System.Collections.Generic.List[object]

$prepareScenarios = @("CS01", "CS02", "CS03", "CS04", "CS05", "CS06", "CS09", "CS10")

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

function Archive-LatestMaestroShots {
  param([string]$Label)
  $maestroRoot = Join-Path $env:USERPROFILE ".maestro\tests"
  if (-not (Test-Path $maestroRoot)) { return $null }
  $latest = Get-ChildItem $maestroRoot -Directory -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $latest) { return $null }
  $dest = Join-Path $shotRoot $Label
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item -Path (Join-Path $latest.FullName "*") -Destination $dest -Recurse -Force -ErrorAction SilentlyContinue
  return $dest
}

function Archive-NamedScreenshots {
  param([string]$DestDir)
  if (-not (Test-Path $DestDir)) {
    New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
  }
  Get-ChildItem -Path $root -Filter "cs*.png" -File -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $DestDir $_.Name) -Force
    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
  }
}

function Invoke-MaestroStep {
  param(
    [string]$Flow,
    [string]$Device,
    [int]$Port,
    [string]$ShotLabel,
    [int]$TimeoutSec = $UxStepTimeoutSec
  )
  if ([string]::IsNullOrWhiteSpace($Flow)) { return $true }
  Write-Log "  UX [$Device] maestro -> $Flow (port $Port, max ${TimeoutSec}s)"
  $stepLog = Join-Path $shotRoot "${ShotLabel}_run.log"
  $psArgs = @(
    "-File", "tool\run_maestro_flow.ps1",
    "-FlowPath", $Flow,
    "-Device", $Device,
    "-DriverHostPort", "$Port"
  )
  if ($SkipInstall) { $psArgs += "-SkipInstall" }
  & (Join-Path $root "tool\run_ps_with_timeout.ps1") -TimeoutSec $TimeoutSec -LogFile $stepLog -PsArgs $psArgs 2>&1 | Out-Null
  $code = $LASTEXITCODE
  if ($code -ne 0) {
    $why = if ($code -eq 124) { "TIMEOUT ${TimeoutSec}s" } else { "exit=$code" }
    Write-Log "  UX FAIL [$Device] $why flow=$Flow (log: $stepLog)"
    $dest = Archive-LatestMaestroShots $ShotLabel
    if ($dest) { Archive-NamedScreenshots $dest }
    return $false
  }
  $dest = Archive-LatestMaestroShots $ShotLabel
  if ($dest) {
    Write-Log "  UX OK [$Device] screenshots -> $dest"
    Archive-NamedScreenshots $dest
  }
  return $true
}

function Invoke-SellerHarnessFlow {
  param(
    [string]$AssertFlow,
    [string]$ExpandCategory = "inBag",
    [string]$ShotLabel = "harness_seller"
  )
  Write-Log "  UX [$SellerDevice] harness UX nav + assert -> $AssertFlow"
  $navOk = Invoke-MaestroStep -Flow ".maestro/flows/open_seller_studio_nav.yaml" -Device $SellerDevice -Port 7001 -ShotLabel "${ShotLabel}_nav"
  if (-not $navOk) { return $false }
  return Invoke-MaestroStep -Flow $AssertFlow -Device $SellerDevice -Port 7001 -ShotLabel $ShotLabel
}

function Invoke-ScenarioSellerFlow {
  param(
    $Scenario,
    [string]$SellerDevice
  )
  if (-not $Scenario.sellerFlow) { return $true }

  if ($Scenario.sellerHarness -eq $true) {
    return Invoke-SellerHarnessFlow -AssertFlow $Scenario.sellerFlow -ShotLabel "$($Scenario.id)_seller"
  }
  if ($Scenario.sellerFlow -match "harness|doc_03|cross_surface|multidevice") {
    if ($Scenario.sellerFlow -notmatch "seller_sees_cancelados") {
      Write-Log "  UX [$SellerDevice] open seller studio (UX nav)..."
      $openOk = Invoke-MaestroStep -Flow ".maestro/flows/open_seller_studio_ux.yaml" -Device $SellerDevice -Port 7001 -ShotLabel "$($Scenario.id)_seller_open"
      if (-not $openOk) { return $false }
    }
    return Invoke-MaestroStep -Flow $Scenario.sellerFlow -Device $SellerDevice -Port 7001 -ShotLabel "$($Scenario.id)_seller"
  }
  return Invoke-MaestroStep -Flow $Scenario.sellerFlow -Device $SellerDevice -Port 7001 -ShotLabel "$($Scenario.id)_seller"
}

function Invoke-ScenarioBuyerFlow {
  param(
    $Scenario,
    [string]$BuyerDevice
  )
  if (-not $Scenario.buyerFlow) { return $true }
  return Invoke-MaestroStep -Flow $Scenario.buyerFlow -Device $BuyerDevice -Port 7002 -ShotLabel "$($Scenario.id)_buyer"
}

function Invoke-ScenarioFlows {
  param(
    $Scenario,
    [string]$SellerDevice,
    [string]$BuyerDevice
  )
  $buyerFirst = ($Scenario.runOrder -eq "buyer_first")
  $sellerOk = $true
  $buyerOk = $true

  if ($buyerFirst) {
    $buyerOk = Invoke-ScenarioBuyerFlow -Scenario $Scenario -BuyerDevice $BuyerDevice
    $sellerOk = Invoke-ScenarioSellerFlow -Scenario $Scenario -SellerDevice $SellerDevice
  } else {
    $sellerOk = Invoke-ScenarioSellerFlow -Scenario $Scenario -SellerDevice $SellerDevice
    $buyerOk = Invoke-ScenarioBuyerFlow -Scenario $Scenario -BuyerDevice $BuyerDevice
  }

  return @{ Seller = $sellerOk; Buyer = $buyerOk }
}

function Pull-DeviceStudioLogs {
  param(
    [string]$Device,
    [string]$DestLabel
  )
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  & powershell -ExecutionPolicy Bypass -File tool\pull_maestro_studio_logs.ps1 -Device $Device 2>&1 | Out-Null
  $ErrorActionPreference = $prevEap
  $src = Join-Path $root "tool\logs\maestro_studio.log"
  if (Test-Path $src) {
    Copy-Item $src (Join-Path $shotRoot $DestLabel) -Force
  }
}

function Invoke-BdScenario {
  param([string]$Name)
  if ($SkipBd -or [string]::IsNullOrWhiteSpace($Name)) { return $true }
  dart run tool/regression_integration.dart --scenario $Name 2>&1 | Out-Null
  return ($LASTEXITCODE -eq 0)
}

$filter = @()
if ($Scenario -ne "") { $filter = $Scenario.Split(",") | ForEach-Object { $_.Trim().ToUpper() } }

Write-Log "=== CROSS-SURFACE UX BATTERY (seller=$SellerDevice buyer=$BuyerDevice) ==="
Write-Log "Regra: PASS so se UX Maestro OK nos emuladores E BD OK. BD sozinho nunca passa cenario."
Write-Log "Screenshots + logs: $shotRoot"

foreach ($sc in $manifest.scenarios) {
  if ($filter.Count -gt 0 -and ($filter -notcontains $sc.id)) { continue }

  Write-Log ""
  Write-Log ">>> $($sc.id) $($sc.name) [BD=$($sc.status) UX=$($sc.statusUx)]"

  $testNum = 10 + [int]($sc.id -replace 'CS','')
  $testId = "T{0:D2}" -f $testNum
  if ($sc.id -eq "CS11") { $testId = "T21" }

  & powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\update_test_battery_status.ps1") `
    -TestId $testId -Status "RUNNING" -Stamp $stamp | Out-Null

  if ($sc.automation -eq "manual" -or $sc.automation -eq "bd_only") {
    Write-Log "  SKIP automacao ($($sc.automation)): $($sc.gap)"
    $results.Add([pscustomobject]@{ Id = $sc.id; Result = "SKIP"; Reason = $sc.automation }) | Out-Null
    & powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\update_test_battery_status.ps1") `
      -TestId $testId -Status "SKIP" -Stamp $stamp -UxNote $sc.gap | Out-Null
    continue
  }

  if ($sc.automation -eq "missing") {
    Write-Log "  SKIP flow em falta: $($sc.gap)"
    $results.Add([pscustomobject]@{ Id = $sc.id; Result = "TODO"; Reason = "flow_missing" }) | Out-Null
    & powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\update_test_battery_status.ps1") `
      -TestId $testId -Status "TODO" -Stamp $stamp -FailReason "flow_missing" | Out-Null
    continue
  }

  if ($prepareScenarios -contains $sc.id) {
    Write-Log "  BD seed: maestro_prepare_live..."
    dart run tool/maestro_prepare_live.dart
    if ($LASTEXITCODE -ne 0) {
      $results.Add([pscustomobject]@{ Id = $sc.id; Result = "FAIL"; Seller = $false; Buyer = $false; BD = $false; Reason = "prepare" }) | Out-Null
      Write-Log "<<< $($sc.id) = FAIL (prepare BD seed)"
      continue
    }
  }

  Write-Log "  --- fase UX (emuladores) ---"
  $flowResult = Invoke-ScenarioFlows -Scenario $sc -SellerDevice $SellerDevice -BuyerDevice $BuyerDevice
  $sellerOk = [bool]$flowResult.Seller
  $buyerOk = [bool]$flowResult.Buyer
  $uxOk = $sellerOk -and $buyerOk

  $bdOk = $true
  if ($sc.bdScenario) {
    Write-Log "  --- fase BD (servidor) ---"
    Write-Log "  BD: $($sc.bdScenario)"
    $bdOk = Invoke-BdScenario -Name $sc.bdScenario
    if (-not $bdOk) { Write-Log "  BD FAIL: $($sc.bdScenario)" }
  }

  Pull-DeviceStudioLogs -Device $SellerDevice -DestLabel "$($sc.id)_seller_studio.log"
  Pull-DeviceStudioLogs -Device $BuyerDevice -DestLabel "$($sc.id)_buyer_studio.log"

  $allOk = $uxOk -and $bdOk
  $r = if ($allOk) { "PASS" } else { "FAIL" }
  $results.Add([pscustomobject]@{
    Id = $sc.id
    Result = $r
    SellerUx = $sellerOk
    BuyerUx = $buyerOk
    BD = $bdOk
  }) | Out-Null
  $uxTag = "seller=$sellerOk buyer=$buyerOk"
  Write-Log "<<< $($sc.id) = $r | UX: $uxTag | BD=$bdOk"

  $failParts = @()
  if (-not $sellerOk -and $sc.sellerFlow) { $failParts += "seller UX fail" }
  if (-not $buyerOk -and $sc.buyerFlow) { $failParts += "buyer UX fail" }
  if (-not $bdOk) { $failParts += "BD fail" }
  $failReason = ($failParts -join "; ")
  $logHint = Join-Path $shotRoot "${sc.id}_seller_run.log"
  & powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\update_test_battery_status.ps1") `
    -TestId $testId -Status $r -Stamp $stamp -FailReason:$failReason -LogPath $logHint -UxNote:$uxTag | Out-Null

  $evidenceDirs = @()
  foreach ($side in @("seller", "buyer", "harness_seller", "seller_nav", "seller_open")) {
    $d = Join-Path $shotRoot "${sc.id}_$side"
    if (Test-Path $d) { $evidenceDirs += $d }
  }
  if ($evidenceDirs.Count -eq 0) { $evidenceDirs += $shotRoot }
  $audit = Invoke-PostTestAudit -TestId $testId -Stamp $stamp `
    -EvidenceDir ($evidenceDirs -join ";") `
    -LogPath $logHint -MaestroExit $(if ($allOk) { 0 } else { 1 }) -Layer "UX+BD" -Scenario $sc.id
  if ($audit) {
    Update-RegistryFromAudit -TestId $testId -Stamp $stamp -AuditResult $audit -LogPath $logHint -UxNote:$uxTag -FailReason:$failReason
    if ($audit.Conclusion -eq "FAIL") { $allOk = $false; $r = "FAIL" }
    elseif ($audit.Conclusion -ne "PASS") { $r = $audit.Conclusion }
  }

  if ($FailFast -and $r -ne "PASS" -and $r -ne "PASS_COM_AVISO" -and $r -ne "PASS_COM_AVISO_DEEPLINK") {
    Write-Log "  FAIL-fast: parar para analisar prints/logs (pausa ${FailFastPauseSec}s). Depois relançar."
    Start-Sleep -Seconds $FailFastPauseSec
    exit 1
  }
}

# Copiar prints soltos que ficaram na raiz do projecto
$orphanDir = Join-Path $shotRoot "_orphan_cs_png"
Archive-NamedScreenshots $orphanDir

Write-Log ""
Write-Log "=== RESUMO ==="
$results | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Log $_.TrimEnd() }
$results | Format-Table -AutoSize | Out-File -Append $summaryFile

$fail = ($results | Where-Object { $_.Result -eq "FAIL" }).Count
$todo = ($results | Where-Object { $_.Result -eq "TODO" }).Count
$skip = ($results | Where-Object { $_.Result -eq "SKIP" }).Count
Write-Log "FAIL=$fail TODO=$todo SKIP=$skip"
Write-Log "Pasta: $shotRoot"

if ($fail -gt 0) { exit 1 }
exit 0
