# Captura PNG binária segura (Windows PowerShell).
# Nunca usar: adb exec-out screencap -p > ficheiro.png
param(
  [Parameter(Mandatory = $true)][string]$Device,
  [Parameter(Mandatory = $true)][string]$OutFile,
  [string]$RemotePath = "/sdcard/fleaber_screencap_tmp.png"
)
$ErrorActionPreference = "Stop"
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) { throw "adb not found: $adb" }

$dir = Split-Path -Parent $OutFile
if ($dir -and -not (Test-Path $dir)) {
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

& $adb -s $Device shell screencap -p $RemotePath
if ($LASTEXITCODE -ne 0) { throw "screencap failed exit=$LASTEXITCODE" }
& $adb -s $Device pull $RemotePath $OutFile
if ($LASTEXITCODE -ne 0) { throw "pull failed exit=$LASTEXITCODE" }
& $adb -s $Device shell rm $RemotePath 2>$null | Out-Null

$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $OutFile))
$ok = ($bytes.Length -gt 1000 -and $bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47)
if (-not $ok) {
  throw "Invalid PNG written to $OutFile (size=$($bytes.Length)). Do not ship in audit ZIP."
}
Write-Host "OK PNG $OutFile ($($bytes.Length) bytes)"
