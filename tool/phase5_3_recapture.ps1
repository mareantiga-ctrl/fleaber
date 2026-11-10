$ErrorActionPreference = 'Continue'
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$Device = 'JRK7AINR9DIJEQ8P'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$out = '14-unified-commerce-phase5.3-final-polish\screenshots'
$email = [uri]::EscapeDataString('vendora.muxc+0921@fleaber.test')

dart run tool/phase5_2_seed_scenario.dart g 2>&1 | Select-Object -Last 1
Copy-Item '14-unified-commerce-phase5.2-final-evidence\raw\seed_g.json' '14-unified-commerce-phase5.3-final-polish\raw\seed_pending.json' -Force
dart run tool/phase5_2_seed_scenario.dart n1 2>&1 | Select-Object -Last 1
Copy-Item '14-unified-commerce-phase5.2-final-evidence\raw\seed_n1.json' '14-unified-commerce-phase5.3-final-polish\raw\seed_guaranteed.json' -Force
dart run tool/phase5_2_seed_scenario.dart n2 2>&1 | Select-Object -Last 1
Copy-Item '14-unified-commerce-phase5.2-final-evidence\raw\seed_n2.json' '14-unified-commerce-phase5.3-final-polish\raw\seed_expiry.json' -Force

$g = Get-Content '14-unified-commerce-phase5.3-final-polish\raw\seed_pending.json' -Raw | ConvertFrom-Json
$n1 = Get-Content '14-unified-commerce-phase5.3-final-polish\raw\seed_guaranteed.json' -Raw | ConvertFrom-Json
$n2 = Get-Content '14-unified-commerce-phase5.3-final-polish\raw\seed_expiry.json' -Raw | ConvertFrom-Json

function Open-StudioWait([string]$liveId, [string]$shot, [int]$sec = 18) {
  $next = [uri]::EscapeDataString("/maestroSellerStudio?liveId=$liveId&opsSection=queue")
  $uri = "fleaber://fleaber.com/maestroAutologin?email=$email&password=testeteste&next=$next"
  & $adb -s $Device shell am force-stop pt.fleaber.app
  Start-Sleep 1
  & $adb -s $Device shell am start -a android.intent.action.VIEW -d "'$uri'" -n pt.fleaber.app/.MainActivity | Out-Null
  Start-Sleep $sec
  & $adb -s $Device shell screencap -p /sdcard/p53.png
  & $adb -s $Device pull /sdcard/p53.png "$out\$shot.png" | Out-Null
  Write-Host "SHOT $shot $((Get-Item "$out\$shot.png").Length)"
}

Open-StudioWait $g.live_id 'A_studio_pending' 18
Open-StudioWait $n1.live_id 'B_studio_guaranteed' 18
& $adb -s $Device shell input tap 360 620
Start-Sleep 2
& $adb -s $Device shell screencap -p /sdcard/p53.png
& $adb -s $Device pull /sdcard/p53.png "$out\C_studio_aguarda_pagamento.png" | Out-Null
Write-Host "C $((Get-Item "$out\C_studio_aguarda_pagamento.png").Length)"

& $adb -s $Device shell uiautomator dump /sdcard/u.xml
& $adb -s $Device pull /sdcard/u.xml '14-unified-commerce-phase5.3-final-polish\raw\ui_trust.xml' | Out-Null
$lines = python tool/_tmp_ui_bounds.py '14-unified-commerce-phase5.3-final-polish/raw/ui_trust.xml' 2>$null
$lines | ForEach-Object { Write-Host $_ }

$confiar = $lines | Where-Object { $_ -match 'Confiar' -and $_ -notmatch 'Nao|Não' } | Select-Object -First 1
if ($confiar) {
  $xy = ($confiar -split '\t')[0] -split ','
  & $adb -s $Device shell input tap $xy[0] $xy[1]
  Start-Sleep 1
  & $adb -s $Device shell screencap -p /sdcard/p53.png
  & $adb -s $Device pull /sdcard/p53.png "$out\K_dialog_confiar.png" | Out-Null
  Write-Host 'K ok'
  & $adb -s $Device shell input keyevent 4
  Start-Sleep 1
}

$prolong = $lines | Where-Object { $_ -match 'Prolongar' } | Select-Object -First 1
if ($prolong) {
  $xy = ($prolong -split '\t')[0] -split ','
  & $adb -s $Device shell input tap $xy[0] $xy[1]
  Start-Sleep 1
  & $adb -s $Device shell screencap -p /sdcard/p53.png
  & $adb -s $Device pull /sdcard/p53.png "$out\L_dialog_prolongar.png" | Out-Null
  Write-Host 'L ok'
}

# Cancel N1 + history
dart run tool/_p53_cancel_n1.dart 2>&1 | Select-Object -Last 1
Open-StudioWait $n1.live_id 'D_tmp' 16
& $adb -s $Device shell input tap 578 620
Start-Sleep 2
& $adb -s $Device shell screencap -p /sdcard/p53.png
& $adb -s $Device pull /sdcard/p53.png "$out\D_studio_historico_cancel.png" | Out-Null

# Expire N2 + history
Copy-Item '14-unified-commerce-phase5.3-final-polish\raw\seed_expiry.json' '14-unified-commerce-phase5.2-final-evidence\raw\seed_n2.json' -Force
dart run tool/phase5_2_expire_n2.dart 2>&1 | Select-Object -Last 1
Copy-Item '14-unified-commerce-phase5.2-final-evidence\raw\n2_expire_rpc.json' '14-unified-commerce-phase5.3-final-polish\raw\n2_expire_rpc.json' -Force
Open-StudioWait $n2.live_id 'E_tmp' 16
& $adb -s $Device shell input tap 578 620
Start-Sleep 2
& $adb -s $Device shell screencap -p /sdcard/p53.png
& $adb -s $Device pull /sdcard/p53.png "$out\E_studio_historico_expiry.png" | Out-Null

# Empty after reject G
dart run tool/_p53_reject_g.dart 2>&1 | Select-Object -Last 1
Open-StudioWait $g.live_id 'F_studio_empty_state' 16

Get-ChildItem $out\*.png | Format-Table Name, Length
