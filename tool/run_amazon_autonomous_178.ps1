# ZIP 178 - single command: pilot 5 ASINs, then detached full batch.
param(
  [switch]$PilotOnly,
  [switch]$FullOnly,
  [switch]$Resume
)

$ErrorActionPreference = "Stop"
$ToolDir = $PSScriptRoot
$Root = Split-Path -Parent $ToolDir
Set-Location $Root

$OutDir = Join-Path $Root "tool\reports\amazon_importer_phase1\enrich_178"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$Py = Join-Path $ToolDir "amazon_importer_autonomous_178.py"
$Status = Join-Path $OutDir "status.json"
$Pilot = Join-Path $OutDir "PILOT_RESULT.json"
$WorkerLog = Join-Path $OutDir "worker.log"
$PidFile = Join-Path $OutDir "worker.pid"

Write-Host "ZIP178 autonomous root=$Root"
Write-Host "Logs: $WorkerLog"
Write-Host "Status: $Status"
Write-Host "Progress: $(Join-Path $OutDir 'progress.json')"

function Start-DetachedFull {
  param([string]$ModeArg)
  $p = Start-Process -FilePath "python" `
    -ArgumentList @($Py, $ModeArg) `
    -WorkingDirectory $Root `
    -RedirectStandardOutput (Join-Path $OutDir "full_stdout.log") `
    -RedirectStandardError (Join-Path $OutDir "full_stderr.log") `
    -WindowStyle Hidden `
    -PassThru
  Set-Content -Path $PidFile -Value $p.Id -Encoding ASCII
  Write-Host "FULL started PID=$($p.Id) detached - zero Cursor tokens."
  Write-Host "Check progress: Get-Content $Status"
}

if ($FullOnly) { Start-DetachedFull -ModeArg "--full"; exit 0 }
if ($Resume) { Start-DetachedFull -ModeArg "--resume"; exit 0 }

Write-Host "=== PILOT 5 ASIN ==="
& python $Py --pilot
if ($LASTEXITCODE -ne 0) {
  Write-Host "PILOT FAIL exit=$LASTEXITCODE"
  if (Test-Path $Pilot) { Get-Content $Pilot -Raw }
  exit $LASTEXITCODE
}
Write-Host "PILOT PASS"
if (Test-Path $Pilot) { Get-Content $Pilot -Raw }
if ($PilotOnly) { exit 0 }

Write-Host "=== FULL 584 detached ==="
Start-DetachedFull -ModeArg "--full"
Write-Host "Autonomous worker running. STOP."
exit 0
