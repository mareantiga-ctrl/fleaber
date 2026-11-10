# APP-201 E2E with ADB tab tap (Maestro id fails on TCL)
param([string]$Device = "a698f0de")
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb -s $Device shell input keyevent KEYCODE_WAKEUP
& $adb -s $Device shell input keyevent 82
Start-Sleep 1

powershell -File tool/run_maestro.ps1 -Flow _ronda_c22_app201_prep_load.yaml -Device $Device -SkipInstall
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Tab Sem catálogo — bounds C15 [540,270][1080,416]
& $adb -s $Device shell input tap 810 343
Start-Sleep 2

powershell -File tool/run_maestro.ps1 -Flow _ronda_c22_app201_refs_steps.yaml -Device $Device -SkipInstall
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Re-open tab for persist check
& $adb -s $Device shell input tap 810 343
Start-Sleep 2
# NUNCA usar `>` em PowerShell para PNG — corrompe para UTF-16.
$shot = "tool/reports/battery_c22_2026-08-19/screenshots/c22_app201_persisted.png"
& $adb -s $Device shell screencap -p /sdcard/c22_app201_persisted.png
& $adb -s $Device pull /sdcard/c22_app201_persisted.png $shot
Write-Host "APP-201 steps done - verify screenshot for 10-20 row"
