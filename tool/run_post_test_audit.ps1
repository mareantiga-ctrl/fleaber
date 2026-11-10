# Pós-teste: recolhe evidência e corre auditoria Cursor.
param(
  [Parameter(Mandatory = $true)]
  [string]$TestId,
  [Parameter(Mandatory = $true)]
  [string]$Stamp,
  [string]$EvidenceDir = "",
  [string]$LogPath = "",
  [int]$MaestroExit = 0,
  [string]$Layer = "UX",
  [string]$Scenario = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$env:PATH = "C:\src\flutter\bin;$env:PATH"

if ($Scenario -eq "") { $Scenario = $TestId }

$args = @(
  "run", "tool/audit/audit_runner.dart",
  "--test-id", $TestId,
  "--stamp", $Stamp,
  "--maestro-exit", "$MaestroExit",
  "--layer", $Layer,
  "--scenario", $Scenario
)
if ($EvidenceDir -ne "") { $args += @("--evidence-dir", $EvidenceDir) }
if ($LogPath -ne "") { $args += @("--log-path", $LogPath) }

dart @args
exit $LASTEXITCODE
