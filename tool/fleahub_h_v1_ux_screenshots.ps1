# FleaHub H-v1 UX screenshots completos (TCL + scroll ADB).
param(
  [string]$Device = "a698f0de",
  [string]$Handle = "fleahub-demo-ux",
  [switch]$SkipBuild
)

$ErrorActionPreference = "Continue"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:PATH = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"
$adb = "$env:ANDROID_HOME\platform-tools\adb.exe"

$stamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$dest = Join-Path $root "tool/reports/screenshots/fleahub_h_v1_ux_$stamp"
New-Item -ItemType Directory -Force -Path $dest | Out-Null

function Log($m) { Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $m" }

function AdbShot($name) {
  $path = Join-Path $dest "$name.png"
  & $adb -s $Device shell screencap -p /sdcard/fleahub_h_v1.png 2>$null | Out-Null
  & $adb -s $Device pull /sdcard/fleahub_h_v1.png $path 2>$null | Out-Null
  if (Test-Path $path) {
    Log "OK $name ($((Get-Item $path).Length) b)"
    return $true
  }
  Log "FAIL $name"
  return $false
}

function SwipeUp([int]$y1 = 1900, [int]$y2 = 350, [int]$ms = 650) {
  & $adb -s $Device shell input swipe 540 $y1 540 $y2 $ms 2>$null | Out-Null
  Start-Sleep -Milliseconds 1200
}

function SwipeBlock([int]$times = 1) {
  for ($i = 0; $i -lt $times; $i++) { SwipeUp }
}

Log "Build + install APK (Hub routes app)..."
if (-not $SkipBuild) {
  flutter build apk --debug 2>&1 | Out-Host
  if ($LASTEXITCODE -ne 0) { exit 1 }
}
$apk = Join-Path $root "build/app/outputs/flutter-apk/app-debug.apk"
& $adb -s $Device install -r $apk 2>&1 | Out-Null

Log "Abrir FleaHub demo /$Handle ..."
& $adb -s $Device shell am force-stop pt.fleaber.app 2>$null | Out-Null
Start-Sleep -Milliseconds 800
& $adb -s $Device shell am start -a android.intent.action.VIEW `
  -d "fleaber://fleaber.com/$Handle" pt.fleaber.app 2>&1 | Out-Null
Log "Aguardar app + dados Hub (15s)..."
Start-Sleep -Seconds 15

# Garantir que Fleaber está em foreground
$fg = & $adb -s $Device shell dumpsys window | Select-String -Pattern "mCurrentFocus.*fleaber"
if (-not $fg) {
  Log "AVISO: Fleaber pode nao estar em foreground - tentar launch directo"
  & $adb -s $Device shell monkey -p pt.fleaber.app -c android.intent.category.LAUNCHER 1 2>$null | Out-Null
  Start-Sleep -Seconds 6
  & $adb -s $Device shell am start -a android.intent.action.VIEW `
    -d "fleaber://fleaber.com/$Handle" pt.fleaber.app 2>&1 | Out-Null
  Start-Sleep -Seconds 10
}

Log "Capturas com scroll..."
$steps = @(
  @{ name = "01_hero"; scrolls = 0 },
  @{ name = "02_em_directo_agora"; scrolls = 0 },
  @{ name = "03_gravados"; scrolls = 2 },
  @{ name = "04_marketplace"; scrolls = 2 },
  @{ name = "05_opinioes"; scrolls = 3 },
  @{ name = "06_sobre"; scrolls = 2 },
  @{ name = "07_rodape_fleaber"; scrolls = 2 }
)

foreach ($s in $steps) {
  if ($s.scrolls -gt 0) { SwipeBlock $s.scrolls }
  if (-not (AdbShot $s.name)) { exit 1 }
}

$readmeLines = @(
  "# FleaHub H-v1 UX screenshots",
  "Handle demo: $Handle",
  "Dispositivo: $Device",
  "Gerado: $(Get-Date -Format o)",
  "Dados staging: demonstracao UX (nao metricas reais).",
  "Ficheiros: 01_hero, 02_em_directo_agora, 03_gravados, 04_marketplace, 05_opinioes, 06_sobre, 07_rodape_fleaber"
)
Set-Content -Path (Join-Path $dest "README.md") -Value ($readmeLines -join "`n")
Set-Content -Path (Join-Path $root "tool/reports/screenshots/fleahub_h_v1_ux_LATEST.txt") -Value $dest

Log "Pasta: $dest"
