# Executa powershell com timeout; mata processo + Maestro se exceder.
param(
  [Parameter(Mandatory = $true)]
  [string[]]$PsArgs,
  [int]$TimeoutSec = 180,
  [string]$LogFile = ""
)

$ErrorActionPreference = "Stop"
$out = if ($LogFile -ne "") { $LogFile } else { [System.IO.Path]::GetTempFileName() }
$err = "$out.err"

$proc = Start-Process -FilePath "powershell.exe" `
  -ArgumentList (@("-ExecutionPolicy", "Bypass", "-NoProfile") + $PsArgs) `
  -PassThru -NoNewWindow `
  -RedirectStandardOutput $out `
  -RedirectStandardError $err

$finished = $proc.WaitForExit($TimeoutSec * 1000)
if (-not $finished) {
  try { $proc.Kill($true) } catch {}
  & powershell -ExecutionPolicy Bypass -File (Join-Path (Split-Path $PSScriptRoot -Parent) "tool\stop_maestro_stale.ps1") | Out-Null
  Write-Host "TIMEOUT apos ${TimeoutSec}s (log: $out)"
  exit 124
}

if ($proc.ExitCode -ne 0) {
  & powershell -ExecutionPolicy Bypass -File (Join-Path (Split-Path $PSScriptRoot -Parent) "tool\stop_maestro_stale.ps1") | Out-Null
}

exit $proc.ExitCode
