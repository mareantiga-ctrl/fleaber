# Copia o log do harness Maestro do emulador para tool/logs/maestro_studio.log
param(
  [string]$Device = "emulator-5554",
  [string]$Package = "com.mycompany.fleaber"
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$outDir = Join-Path $root "tool\logs"
$outFile = Join-Path $outDir "maestro_studio.log"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
  Write-Host "FAIL: adb nao encontrado"
  exit 1
}

$remote = "/sdcard/Android/data/$Package/files/maestro_studio_debug.log"
Write-Host "Pull $remote -> $outFile"

# adb escreve progresso em stderr mesmo quando o pull tem sucesso.
$prevEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$pullOut = & $adb -s $Device pull $remote $outFile 2>&1
$pullCode = $LASTEXITCODE
$ErrorActionPreference = $prevEap
if (-not (Test-Path $outFile) -or (Get-Item $outFile).Length -eq 0) {
  if ($pullOut) { Write-Host $pullOut }
  Write-Host ""
  Write-Host "Se o ficheiro nao existir, abre o harness Maestro e reproduz o bug primeiro."
  Write-Host "Depois: powershell -File tool\pull_maestro_studio_logs.ps1"
  exit 1
}

Write-Host ""
Write-Host "OK: log em $outFile"
Get-Content $outFile -Tail 40
