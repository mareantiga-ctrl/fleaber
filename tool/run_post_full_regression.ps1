# Pós --full: re-corre fails + auditoria + bateria T retry.
param(
  [switch]$SkipBattery,
  [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$env:PATH = "C:\src\flutter\bin;$env:PATH"

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$log = Join-Path $root "tool\logs\post_full_regression_$stamp.log"

function Log([string]$msg) {
  $line = "$(Get-Date -Format 'HH:mm:ss') $msg"
  Write-Host $line
  Add-Content -Path $log -Value $line
}

Log "=== post-full: failed-only + auditoria ==="
dart run tool/fleaber_regression_runner.dart --failed-only 2>&1 | Tee-Object -FilePath $log -Append
$code1 = $LASTEXITCODE
Log "failed-only exit=$code1"

if (-not $SkipBattery) {
  Log "=== bateria T retry (se aplicável) ==="
  & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run_retry_failed_battery.ps1") @(
    if ($SkipInstall) { "-SkipInstall" }
  ) 2>&1 | Tee-Object -FilePath $log -Append
}

$auditStamp = (Get-ChildItem (Join-Path $root "tool\logs") -Directory -Filter "regression_*" |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1).Name -replace '^regression_', ''
if ($auditStamp) {
  Log "=== batch auditoria stamp=$auditStamp ==="
  dart run tool/audit/audit_runner.dart --batch-stamp $auditStamp 2>&1 | Tee-Object -FilePath $log -Append
}

Log "=== concluído ==="
exit $code1
