param([string]$Device = "JRK7AINR9DIJEQ8P")
$ErrorActionPreference = "Continue"
$root = "c:\Users\Casa\Desktop\Fleaber\fleaber"
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$out = Join-Path $root "14-unified-commerce-phase5-live-seller-studio\screenshots"
New-Item -Force -ItemType Directory $out | Out-Null

$email = "vendora.muxc+0921@fleaber.test"
$pass = "testeteste"
$seed = Get-Content "$root\14-unified-commerce-phase5-live-seller-studio\raw\ui_seed_for_screenshots.json" -Raw | ConvertFrom-Json
$liveId = $seed.live_id

function Shot($n) {
  & $adb -s $Device shell screencap -p "/sdcard/$n.png"
  & $adb -s $Device pull "/sdcard/$n.png" "$out\$n.png" | Out-Null
  Write-Host "SHOT $n $((Get-Item "$out\$n.png").Length)"
}

function Dump() {
  & $adb -s $Device shell uiautomator dump /sdcard/u.xml | Out-Null
  & $adb -s $Device pull /sdcard/u.xml "$out\_u.xml" | Out-Null
  return (Get-Content "$out\_u.xml" -Raw)
}

function TapText($xml, $text) {
  $esc = [regex]::Escape($text)
  $m = [regex]::Match($xml, "text=`"$esc`"[^>]*bounds=`"\[(\d+),(\d+)\]\[(\d+),(\d+)\]`"")
  if (-not $m.Success) { Write-Host "MISS $text"; return $false }
  $cx = [int]((+[int]$m.Groups[1].Value + [int]$m.Groups[3].Value) / 2)
  $cy = [int]((+[int]$m.Groups[2].Value + [int]$m.Groups[4].Value) / 2)
  Write-Host "TAP $text $cx,$cy"
  & $adb -s $Device shell input tap $cx $cy
  Start-Sleep 2
  return $true
}

& $adb -s $Device shell am force-stop pt.fleaber.app
Start-Sleep 1
& $adb -s $Device shell am start -n pt.fleaber.app/.MainActivity
Start-Sleep 5
Shot "L01_launch"

# Dismiss cookies if any
$xml = Dump
TapText $xml "Aceitar" | Out-Null

# Focus email - clear and type
$xml = Dump
# Tap email field by content-desc or hint
if (-not (TapText $xml "E-mail")) {
  # try by resource id via bounds of EditText - tap first edit roughly
  & $adb -s $Device shell input tap 540 780
  Start-Sleep 1
}
& $adb -s $Device shell input keyevent KEYCODE_MOVE_HOME
& $adb -s $Device shell input keyevent --elongated KEYCODE_DEL 2>$null
# Clear field: select all + delete
& $adb -s $Device shell input keyevent 123 # move end
1..40 | ForEach-Object { & $adb -s $Device shell input keyevent 67 } # DEL
& $adb -s $Device shell input text ($email -replace '\+','%2B' -replace '@','\@')
# adb input text doesn't like + and @ well - use %s escaping for spaces only; for @ use $@
# Better: use maestro or clipper
& $adb -s $Device shell am broadcast -a clipper.set -e text $email 2>$null
# Use ADB keyboard / paste: 
& $adb -s $Device shell input keyevent 279 # paste if supported
Start-Sleep 1

# Use run with encoded: replace + with \+
& $adb -s $Device shell input tap 540 780
Start-Sleep 1
1..50 | ForEach-Object { & $adb -s $Device shell input keyevent 67 }
# Escape for adb: @ -> \@, space -> %s, + is ok in newer adb
& $adb -s $Device shell input text "vendora.muxc+0921@fleaber.test"
Start-Sleep 1
& $adb -s $Device shell input tap 540 950
Start-Sleep 1
1..20 | ForEach-Object { & $adb -s $Device shell input keyevent 67 }
& $adb -s $Device shell input text $pass
Start-Sleep 1
Shot "L02_filled"
$xml = Dump
if (-not (TapText $xml "Entrar")) {
  & $adb -s $Device shell input tap 540 1200
}
Start-Sleep 8
Shot "L03_after_entrar"
$xml = Dump
Write-Host "TEXTS:" 
[regex]::Matches($xml, 'text="([^"]{2,50})"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique | Select-Object -First 40

# If home - go perfil
if ($xml -match "In") {
  TapText $xml "Perfil" | Out-Null
  Start-Sleep 2
  Shot "L04_perfil"
  $xml = Dump
  TapText $xml "Definições de conta" | Out-Null
  Start-Sleep 2
  Shot "B_seller_definicoes"
  1..15 | ForEach-Object {
    & $adb -s $Device shell input swipe 540 1700 540 500 280
    Start-Sleep -Milliseconds 350
  }
  Shot "B_seller_definicoes_scrolled"
  $xml = Dump
  [regex]::Matches($xml, 'text="([^"]{2,60})"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
  TapText $xml "Reservas no directo" | Out-Null
  Start-Sleep 1
  $xml = Dump
  TapText $xml "Configurar reservas" | Out-Null
  Start-Sleep 2
  Shot "B_C_policy_sheet"
  $xml = Dump
  TapText $xml "Só o pagamento garante" | Out-Null
  Start-Sleep 1
  Shot "D_pay_mode"
}

# Studio deep link after hopefully logged in
$uri = "fleaber://fleaber.com/maestroSellerStudio?liveId=$liveId&opsSection=queue"
& $adb -s $Device shell am start -a android.intent.action.VIEW -d $uri
Start-Sleep 12
Shot "E_H_studio"
Write-Host "DONE"
