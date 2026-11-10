# Funções partilhadas — Maestro com timeout curto + pausa operador (continua sem recomeçar).
# Dot-source: . (Join-Path $PSScriptRoot "maestro_assisted_helpers.ps1")
#
# Variáveis esperadas no scope do caller:
#   $root, $shotRoot, $SkipInstall, $AssistedMode, $UxStepTimeoutSec, $UxStepTimeoutAssistedSec

function Get-MaestroFailHint {
  param([string]$LogFile)
  if (-not (Test-Path $LogFile)) { return "Maestro falhou (sem log)" }
  $tail = Get-Content $LogFile -Tail 40 -ErrorAction SilentlyContinue
  if (-not $tail) { return "Maestro falhou (log vazio)" }
  $joined = ($tail -join " ")
  if ($joined -match '(?i)(not visible|assertion|timeout|unable to find|failed)') {
    foreach ($line in $tail) {
      if ($line -match '(?i)(visible|tap|assert|scroll|timeout|fail|warn)') {
        return $line.Trim()
      }
    }
  }
  return ($tail[-1]).Trim()
}

function Invoke-AdbScreenshot {
  param(
    [string]$Device,
    [string]$DestPath
  )
  $adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
  if (-not (Test-Path $adb)) { return $false }
  if ([string]::IsNullOrWhiteSpace($Device)) { return $false }
  $dir = Split-Path $DestPath -Parent
  if ($dir -and -not (Test-Path $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $remote = "/sdcard/fleaber_maestro_cap.png"
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  & $adb -s $Device shell screencap -p $remote 2>&1 | Out-Null
  & $adb -s $Device pull $remote $DestPath 2>&1 | Out-Null
  & $adb -s $Device shell rm $remote 2>&1 | Out-Null
  $ErrorActionPreference = $prevEap
  return (Test-Path $DestPath)
}

function Wait-OperatorCheckpoint {
  param(
    [string]$Title,
    [string[]]$Steps,
    [string]$Device = "",
    [string]$ScreenshotPath = ""
  )
  Write-Host ""
  Write-Host "========================================" -ForegroundColor Cyan
  Write-Host " PAUSA OPERADOR: $Title" -ForegroundColor Cyan
  Write-Host "========================================" -ForegroundColor Cyan
  foreach ($s in $Steps) { Write-Host "  $s" }
  if ($Device -ne "" -and $ScreenshotPath -ne "") {
    $ok = Invoke-AdbScreenshot -Device $Device -DestPath $ScreenshotPath
    if ($ok) { Write-Host "  [print] $ScreenshotPath" -ForegroundColor DarkGray }
  }
  Write-Host ""
  Write-Host "  done / ENTER = continuar (passo OK)" -ForegroundColor Green
  Write-Host "  skip = saltar este passo" -ForegroundColor Yellow
  Write-Host "  fail = marcar falha" -ForegroundColor Red
  $r = Read-Host "operador"
  switch ($r.Trim().ToLower()) {
    "skip" { return "skip" }
    "s" { return "skip" }
    "fail" { return "fail" }
    "f" { return "fail" }
    "done" { return "pass" }
    "d" { return "pass" }
    default { return "pass" }
  }
}

function Archive-LatestMaestroShotsShared {
  param([string]$Label)
  $maestroRoot = Join-Path $env:USERPROFILE ".maestro\tests"
  if (-not (Test-Path $maestroRoot)) { return $null }
  $latest = Get-ChildItem $maestroRoot -Directory -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $latest) { return $null }
  $dest = Join-Path $script:ShotRoot $Label
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item -Path (Join-Path $latest.FullName "*") -Destination $dest -Recurse -Force -ErrorAction SilentlyContinue
  return $dest
}

function Archive-NamedScreenshotsShared {
  param([string]$DestDir)
  if (-not (Test-Path $DestDir)) {
    New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
  }
  Get-ChildItem -Path $script:Root -Filter "cs*.png" -File -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $DestDir $_.Name) -Force
    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
  }
  Get-ChildItem -Path $script:Root -Filter "sl*.png" -File -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $DestDir $_.Name) -Force
    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
  }
}

function Invoke-MaestroStepCore {
  param(
    [string]$Flow,
    [string]$Device,
    [int]$Port,
    [string]$ShotLabel,
    [int]$TimeoutSec
  )
  if ([string]::IsNullOrWhiteSpace($Flow)) {
    return @{ Ok = $true; OperatorAssisted = $false; LogFile = "" }
  }
  $stepLog = Join-Path $script:ShotRoot "${ShotLabel}_run.log"
  $psArgs = @(
    "-File", "tool\run_maestro_flow.ps1",
    "-FlowPath", $Flow,
    "-Device", $Device,
    "-DriverHostPort", "$Port"
  )
  if ($script:SkipInstall) { $psArgs += "-SkipInstall" }
  & (Join-Path $script:Root "tool\run_ps_with_timeout.ps1") -TimeoutSec $TimeoutSec -LogFile $stepLog -PsArgs $psArgs 2>&1 | Out-Null
  $code = $LASTEXITCODE
  $ok = ($code -eq 0)
  if (-not $ok) {
    $why = if ($code -eq 124) { "TIMEOUT ${TimeoutSec}s" } else { "exit=$code" }
    Write-Host "  UX FAIL [$Device] $why flow=$Flow (log: $stepLog)" -ForegroundColor Red
    $dest = Archive-LatestMaestroShotsShared $ShotLabel
    if ($dest) { Archive-NamedScreenshotsShared $dest }
    return @{ Ok = $false; OperatorAssisted = $false; LogFile = $stepLog; Reason = $why }
  }
  $dest = Archive-LatestMaestroShotsShared $ShotLabel
  if ($dest) {
    Write-Host "  UX OK [$Device] screenshots -> $dest" -ForegroundColor DarkGreen
    Archive-NamedScreenshotsShared $dest
  }
  return @{ Ok = $true; OperatorAssisted = $false; LogFile = $stepLog; Reason = "" }
}

function Invoke-MaestroStepAssisted {
  param(
    [string]$Flow,
    [string]$Device,
    [int]$Port,
    [string]$ShotLabel,
    [string]$OperatorHint = "",
    [int]$TimeoutSec = 0,
    [string]$PhaseId = ""
  )
  $maxSec = if ($TimeoutSec -gt 0) {
    $TimeoutSec
  } elseif ($script:AssistedMode) {
    $script:UxStepTimeoutAssistedSec
  } else {
    $script:UxStepTimeoutSec
  }

  Write-Host "  UX [$Device] maestro -> $Flow (port $Port, max ${maxSec}s$(if ($script:AssistedMode) { ', assisted' } else { '' }))"
  $result = Invoke-MaestroStepCore -Flow $Flow -Device $Device -Port $Port -ShotLabel $ShotLabel -TimeoutSec $maxSec
  if ($result.Ok) { return $result }

  if (-not $script:AssistedMode) { return $result }

  $hint = Get-MaestroFailHint -LogFile $result.LogFile
  $capBefore = Join-Path $script:ShotRoot "${ShotLabel}_operator_before.png"
  Invoke-AdbScreenshot -Device $Device -DestPath $capBefore | Out-Null

  $steps = @(
    "Maestro nao completou: $hint"
    if ($result.Reason) { "Detalhe: $($result.Reason)" }
    "Device: $Device"
    if ($OperatorHint) { $OperatorHint }
    "Toca no telemovel onde for preciso (ex. botao, tab, artigo)."
    "Quando o ecrã estiver correcto escreve: done"
  ) | Where-Object { $_ -ne $null -and $_ -ne "" }

  $op = Wait-OperatorCheckpoint -Title "$PhaseId $ShotLabel" -Steps $steps -Device $Device `
    -ScreenshotPath (Join-Path $script:ShotRoot "${ShotLabel}_operator_after.png")

  if ($op -eq "skip") {
    return @{ Ok = $true; OperatorAssisted = $true; Skipped = $true; LogFile = $result.LogFile; Reason = "operator_skip" }
  }
  if ($op -eq "fail") {
    return @{ Ok = $false; OperatorAssisted = $true; LogFile = $result.LogFile; Reason = "operator_fail" }
  }

  return @{ Ok = $true; OperatorAssisted = $true; LogFile = $result.LogFile; Reason = "operator_done" }
}

function Invoke-StockBdSnapshot {
  param(
    [string]$Label,
    [string]$LiveId = ""
  )
  $args = @("run", "tool/stock_lifecycle_snapshot.dart", "--label", $Label, "--out", (Join-Path $script:ShotRoot "${Label}_bd_stock.json"))
  if ($LiveId -ne "") { $args += @("--live-id", $LiveId) }
  dart @args 2>&1 | Out-Null
  return ($LASTEXITCODE -eq 0)
}

function Initialize-MaestroAssistedContext {
  param(
    [string]$Root,
    [string]$ShotRoot,
    [switch]$SkipInstall,
    [switch]$AssistedMode,
    [int]$UxStepTimeoutSec = 300,
    [int]$UxStepTimeoutAssistedSec = 55
  )
  $script:Root = $Root
  $script:ShotRoot = $ShotRoot
  $script:SkipInstall = [bool]$SkipInstall
  $script:AssistedMode = [bool]$AssistedMode
  $script:UxStepTimeoutSec = $UxStepTimeoutSec
  $script:UxStepTimeoutAssistedSec = $UxStepTimeoutAssistedSec
}
