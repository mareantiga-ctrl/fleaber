# FleaHub UX: pasta NOVA por corrida + Maestro/ADB. Sem sobrescrever corridas anteriores.
param(
  [string]$Device = "a698f0de",
  [switch]$IncludeCreateFlow,
  [string]$Label = ""
)

$ErrorActionPreference = "Continue"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:PATH = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"

$adb = "$env:ANDROID_HOME\platform-tools\adb.exe"
$maestro = Join-Path $root ".tools\maestro\maestro\bin\maestro.bat"
$config = Join-Path $root ".maestro\config.yaml"
$shotsDir = Join-Path $root ".maestro\flows\hub_ux\fleahub_shots"
$reportsRoot = Join-Path $root "tool/reports/screenshots"

$stamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$suffix = if ($Label) { "_$Label" } else { "" }
$dest = Join-Path $reportsRoot "fleahub_ux_${stamp}${suffix}"
New-Item -ItemType Directory -Force -Path $dest | Out-Null

function Log($m) { Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $m" }

function AdbShot($name) {
  $path = Join-Path $dest "$name.png"
  & $adb -s $Device shell screencap -p /sdcard/fleahub_cap.png 2>$null | Out-Null
  & $adb -s $Device pull /sdcard/fleahub_cap.png $path 2>$null | Out-Null
  if (Test-Path $path) {
    Log "ADB OK -> $name ($((Get-Item $path).Length) b)"
    return $true
  }
  Log "ADB FAIL -> $name"
  return $false
}

function Run-Maestro($flowPath) {
  & $maestro test --config $config --device $Device --driver-host-port 7011 $flowPath 2>&1 | Out-Host
  return $LASTEXITCODE
}

function Run-Shot($flow, $out) {
  $flowPath = Join-Path $shotsDir $flow
  Log "Maestro $flow..."
  $code = Run-Maestro $flowPath
  if ($code -ne 0) {
    Log "FAIL $flow exit=$code"
    return $false
  }
  Start-Sleep -Milliseconds 800
  return (AdbShot $out)
}

Log "Pasta destino: $dest"

Log "flutter test..."
flutter test test/hub_seller_hub_test.dart test/hub_seller_fleahub_flow_test.dart 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { exit 1 }

$apk = Join-Path $root "build/app/outputs/flutter-apk/app-debug.apk"
Log "flutter build apk debug..."
flutter build apk --debug 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { exit 1 }
& $adb -s $Device install -r $apk 2>&1 | Out-Null

$fail = 0
$steps = @(
  @{ flow = "01_perfil_line.yaml"; out = "01_perfil_seller_fleahub_line" },
  @{ flow = "02_sheet_activa.yaml"; out = "02_sheet_fleahub_activa" },
  @{ flow = "03_sheet_inactiva.yaml"; out = "03_sheet_fleahub_inactiva" },
  @{ flow = "05_personalizar.yaml"; out = "05_personalizar_endereco" }
)

if ($IncludeCreateFlow) {
  Log "staging clear (screenshot 04)..."
  dart run tool/fleahub_staging_create_flow_reset.dart backup 2>&1 | Out-Null
  dart run tool/fleahub_staging_create_flow_reset.dart clear 2>&1 | Out-Host
  if ($LASTEXITCODE -eq 0) {
    if (-not (Run-Shot "04_criar_fleahub.yaml" "04_criar_fleahub")) { $fail++ }
    dart run tool/fleahub_staging_create_flow_reset.dart restore 2>&1 | Out-Null
  } else {
    Log "AVISO: clear staging falhou - 04 omitido"
    $fail++
  }
}

foreach ($step in $steps) {
  if (-not (Run-Shot $step.flow $step.out)) { $fail++ }
}

dart run tool/fleahub_staging_create_flow_reset.dart restore 2>&1 | Out-Null

$readmeLines = @(
  "# FleaHub UX - corrida $stamp",
  "",
  "Pasta: $dest",
  "",
  "Copy: HubSellerCopy (O teu espaco publico na Fleaber / Personalizar / Ocultar)",
  "",
  "01_perfil_seller_fleahub_line.png - linha FleaHub no perfil",
  "02_sheet_fleahub_activa.png - sheet activa",
  "03_sheet_fleahub_inactiva.png - sheet oculta",
  "04_criar_fleahub.png - criar (flag -IncludeCreateFlow)",
  "05_personalizar_endereco.png - personalizar endereco"
)
Set-Content -Path (Join-Path $dest "README.md") -Value ($readmeLines -join "`n") -Encoding UTF8

$latest = Join-Path $reportsRoot "fleahub_ux_LATEST.txt"
Set-Content -Path $latest -Value $dest -Encoding UTF8

Write-Host ""
Write-Host "NOVA PASTA: $dest" -ForegroundColor Green
Get-ChildItem $dest -Filter "*.png" | Sort-Object Name | Format-Table Name, Length -AutoSize
exit [Math]::Min($fail, 1)
