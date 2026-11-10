# Captura screenshots UX FleaHub no TCL (sem Maestro) — navegação ADB + uiautomator.
param(
  [string]$Device = "a698f0de"
)

$ErrorActionPreference = "Continue"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$dest = Join-Path $root "tool/reports/screenshots/fleahub_ux_manual"
New-Item -ItemType Directory -Force -Path $dest | Out-Null

function Log($m) { Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $m" }

function Shot($name) {
  $path = Join-Path $dest "$name.png"
  & $adb -s $Device shell screencap -p /sdcard/fleahub_cap.png 2>$null | Out-Null
  & $adb -s $Device pull /sdcard/fleahub_cap.png $path 2>$null | Out-Null
  if (Test-Path $path) {
    Log "screenshot: $path ($((Get-Item $path).Length) bytes)"
    return $path
  }
  Log "ERRO screenshot: $name"
  return $null
}

function Get-UiDump {
  & $adb -s $Device shell uiautomator dump /sdcard/ui.xml 2>$null | Out-Null
  $local = Join-Path $env:TEMP "fleahub_ui_$Device.xml"
  & $adb -s $Device pull /sdcard/ui.xml $local 2>$null | Out-Null
  if (-not (Test-Path $local)) { return $null }
  return Get-Content $local -Raw -Encoding UTF8
}

function Tap-Text {
  param([string]$Pattern)
  $xml = Get-UiDump
  if (-not $xml) { Log "sem ui dump"; return $false }
  $matches = [regex]::Matches($xml, 'text="([^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
  foreach ($m in $matches) {
    $text = $m.Groups[1].Value
    if ($text -notmatch $Pattern) { continue }
    $x1 = [int]$m.Groups[2].Value; $y1 = [int]$m.Groups[3].Value
    $x2 = [int]$m.Groups[4].Value; $y2 = [int]$m.Groups[5].Value
    $cx = [int](($x1 + $x2) / 2); $cy = [int](($y1 + $y2) / 2)
    Log "tap '$text' -> $cx,$cy"
    & $adb -s $Device shell input tap $cx $cy 2>$null | Out-Null
    Start-Sleep -Seconds 2
    return $true
  }
  Log "nao encontrado: $Pattern"
  return $false
}

function Tap-ContentDesc {
  param([string]$Pattern)
  $xml = Get-UiDump
  if (-not $xml) { return $false }
  $matches = [regex]::Matches($xml, 'content-desc="([^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
  foreach ($m in $matches) {
    $text = $m.Groups[1].Value
    if ($text -notmatch $Pattern) { continue }
    $x1 = [int]$m.Groups[2].Value; $y1 = [int]$m.Groups[3].Value
    $x2 = [int]$m.Groups[4].Value; $y2 = [int]$m.Groups[5].Value
    $cx = [int](($x1 + $x2) / 2); $cy = [int](($y1 + $y2) / 2)
    Log "tap desc '$text' -> $cx,$cy"
    & $adb -s $Device shell input tap $cx $cy 2>$null | Out-Null
    Start-Sleep -Seconds 2
    return $true
  }
  return $false
}

function Press-Back {
  & $adb -s $Device shell input keyevent 4 2>$null | Out-Null
  Start-Sleep -Seconds 1
}

# Install APK
$apk = Join-Path $root "build/app/outputs/flutter-apk/app-debug.apk"
if (Test-Path $apk) {
  Log "install APK..."
  & $adb -s $Device install -r $apk 2>&1 | Out-Null
}

Log "launch app"
& $adb -s $Device shell monkey -p pt.fleaber.app -c android.intent.category.LAUNCHER 1 2>$null | Out-Null
Start-Sleep -Seconds 4

Log "=== 1 Perfil seller + linha FleaHub ==="
Tap-Text "Perfil" | Out-Null
Start-Sleep -Seconds 1
Tap-Text "an.ncios e diretos|meus an" | Out-Null
Start-Sleep -Seconds 2
Shot "01_perfil_seller_fleahub_line"

Log "=== 2 Sheet FleaHub activa ==="
Tap-Text "FleaHub|Criar FleaHub" | Out-Null
Start-Sleep -Seconds 2
if (-not (Tap-Text "Activar FleaHub")) {
  Log "FleaHub ja activo ou sem botao Activar"
}
Start-Sleep -Seconds 2
Shot "02_sheet_fleahub_activa"

Log "=== 3 Sheet FleaHub inactiva ==="
Tap-Text "Desactivar FleaHub" | Out-Null
Start-Sleep -Seconds 3
Shot "03_sheet_fleahub_inactiva"

Log "=== 5 Personalizar endereco ==="
Tap-Text "Personalizar endere" | Out-Null
Start-Sleep -Seconds 2
Shot "05_personalizar_endereco"
Press-Back
Press-Back
Press-Back

Log "=== 4 Criar FleaHub (conta sem slug - pode falhar nesta sessao) ==="
Log "NOTA: seller staging tem slug; screenshot 4 requer conta nova ou BD limpa."

Write-Host ""
Write-Host "Screenshots em: $dest"
Get-ChildItem $dest -Filter "*.png" | Format-Table Name, Length -AutoSize
