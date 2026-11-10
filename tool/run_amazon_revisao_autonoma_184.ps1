# ZIP 184 - pilot 5 needs_review then detached full reprocess (no Cursor tokens).
param(
  [switch]$PilotOnly,
  [switch]$FullOnly
)

$ErrorActionPreference = "Stop"
$ToolDir = $PSScriptRoot
$Root = Split-Path -Parent $ToolDir
Set-Location $Root
$OutDir = Join-Path $Root "tool\reports\amazon_importer_phase1\enrich_184"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$Py = Join-Path $ToolDir "amazon_importer_review_autonoma_184.py"
$PidFile = Join-Path $OutDir "worker.pid"
$Status = Join-Path $OutDir "status.json"

Write-Host "ZIP184 revisao autonomoma out=$OutDir"

function Start-Detached {
  $p = Start-Process -FilePath "python" -ArgumentList @($Py, "--full") `
    -WorkingDirectory $Root `
    -RedirectStandardOutput (Join-Path $OutDir "full_stdout.log") `
    -RedirectStandardError (Join-Path $OutDir "full_stderr.log") `
    -WindowStyle Hidden -PassThru
  Set-Content $PidFile $p.Id -Encoding ASCII
  Write-Host "FULL PID=$($p.Id) detached - zero Cursor tokens/ASIN"
  Write-Host "Progress: $OutDir\progress.json | status.json"
}

if ($FullOnly) { Start-Detached; exit 0 }

Write-Host "=== PILOT 5 ==="
& python $Py --pilot
if ($LASTEXITCODE -ne 0) {
  Write-Host "PILOT FAIL"
  exit $LASTEXITCODE
}
Write-Host "PILOT PASS"
if ($PilotOnly) { exit 0 }
Start-Detached
exit 0
