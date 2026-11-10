# Phase 5.6 — final visual proofs P3/S2/H2/L3/G2/I2
$ErrorActionPreference = 'Continue'
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$Device = 'JRK7AINR9DIJEQ8P'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$out = '14-unified-commerce-phase5.6-visual-final\screenshots'
$raw = '14-unified-commerce-phase5.6-visual-final\raw'
New-Item -ItemType Directory -Force -Path $out, $raw | Out-Null

function Read-Env([string]$Key) {
  $line = Get-Content tool\live_ops_staging.env | Where-Object { $_ -match "^$Key=" } | Select-Object -First 1
  return ($line.Substring($Key.Length + 1)).Trim()
}
$buyerEmail = [uri]::EscapeDataString((Read-Env 'LIVE_OPS_TEST_BUYER_EMAIL'))
$buyerPass = [uri]::EscapeDataString((Read-Env 'LIVE_OPS_TEST_BUYER_PASSWORD'))
$email = [uri]::EscapeDataString((Read-Env 'LIVE_OPS_TEST_SELLER_EMAIL'))
$sellerPass = [uri]::EscapeDataString((Read-Env 'LIVE_OPS_TEST_SELLER_PASSWORD'))

function Dump([string]$n) {
  & $adb -s $Device shell uiautomator dump /sdcard/ui56.xml | Out-Null
  & $adb -s $Device pull /sdcard/ui56.xml "$raw\$n.xml" | Out-Null
  return (Get-Content "$raw\$n.xml" -Raw -ErrorAction SilentlyContinue)
}
function Shot([string]$n) {
  & $adb -s $Device shell screencap -p /sdcard/p56.png
  & $adb -s $Device pull /sdcard/p56.png "$out\$n.png" | Out-Null
  $dims = Png-Dims "$out\$n.png"
  Write-Host "SHOT $n $((Get-Item "$out\$n.png").Length) $dims"
}
function Png-Dims([string]$path) {
  Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
  try {
    $img = [System.Drawing.Image]::FromFile((Resolve-Path $path))
    $d = "$($img.Width)x$($img.Height)"
    $img.Dispose()
    return $d
  } catch { return '?' }
}
function TapDesc([string]$needle, $xml) {
  $m = [regex]::Match($xml, ('content-desc="[^"]*{0}[^"]*"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"' -f [regex]::Escape($needle)))
  if (-not $m.Success) { Write-Host "MISS $needle"; return $false }
  $x = [int](($([int]$m.Groups[1].Value) + $([int]$m.Groups[3].Value)) / 2)
  $y = [int](($([int]$m.Groups[2].Value) + $([int]$m.Groups[4].Value)) / 2)
  & $adb -s $Device shell input tap $x $y
  Write-Host "TAP $needle $x,$y"
  return $true
}
function TapFinalizar($xml) {
  $ms = [regex]::Matches($xml, 'content-desc="Finalizar compra"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
  if ($ms.Count -eq 0) { return $false }
  $m = $ms[$ms.Count - 1]
  $x = [int](($([int]$m.Groups[1].Value) + $([int]$m.Groups[3].Value)) / 2)
  $y = [int](($([int]$m.Groups[2].Value) + $([int]$m.Groups[4].Value)) / 2)
  & $adb -s $Device shell input tap $x $y
  Write-Host "TAP Finalizar $x,$y"
  return $true
}
function Open-Uri([string]$next, [string]$who) {
  $e = if ($who -eq 'buyer') { $buyerEmail } else { $email }
  $p = if ($who -eq 'buyer') { $buyerPass } else { $sellerPass }
  $uri = "fleaber://fleaber.com/maestroAutologin?email=$e&password=$p&next=$([uri]::EscapeDataString($next))"
  & $adb -s $Device shell am force-stop pt.fleaber.app
  Start-Sleep 1
  & $adb -s $Device shell am start -a android.intent.action.VIEW -d "'$uri'" -n pt.fleaber.app/.MainActivity | Out-Null
}

& $adb -s $Device shell settings put global policy_control immersive.navigation=*
& $adb -s $Device shell wm size reset

Write-Host '=== P3 policy selector open ==='
Open-Uri '/contaDefinicoes' 'seller'
Start-Sleep 14
Dump 'p3_settings' | Out-Null
& $adb -s $Device shell input swipe 360 1200 360 400 450
Start-Sleep 1
$xml = Dump 'p3_settings2'
if (-not (TapDesc 'Configurar reservas' $xml)) {
  TapDesc 'Reservas no directo' $xml | Out-Null
  Start-Sleep 1
  $xml = Dump 'p3_settings3'
  TapDesc 'Configurar reservas' $xml | Out-Null
}
Start-Sleep 3
$xml = Dump 'p3_closed'
if (-not (TapDesc '1 dia' $xml)) {
  if (-not (TapDesc '1 hora' $xml)) { TapDesc 'Duração normal' $xml | Out-Null }
}
Start-Sleep 2
Dump 'p3_open' | Out-Null
Shot 'P3_policy_selector_open_FINAL'
& $adb -s $Device shell input keyevent 4
Start-Sleep 1

dart run tool/phase5_4_seed.dart guaranteed 2>&1 | Select-Object -Last 1
Copy-Item '14-unified-commerce-phase5.4-final-visual-proof\raw\seed_guaranteed.json' "$raw\seed_guaranteed.json" -Force
$guar = Get-Content "$raw\seed_guaranteed.json" -Raw | ConvertFrom-Json
dart run tool/phase5_4_seed.dart realistic 2>&1 | Select-Object -Last 1
Copy-Item '14-unified-commerce-phase5.4-final-visual-proof\raw\seed_realistic.json' "$raw\seed_realistic.json" -Force -ErrorAction SilentlyContinue
$real = if (Test-Path "$raw\seed_realistic.json") {
  Get-Content "$raw\seed_realistic.json" -Raw | ConvertFrom-Json
} else { $guar }

Write-Host '=== S2 bottom actions ==='
Open-Uri "/maestroSellerStudio?liveId=$($real.live_id)&opsSection=catalog" 'seller'
Start-Sleep 22
$xml = Dump 's2_0'
foreach ($n in @('Casaco','Vestido','Camisa','Novidades','Mostrar')) {
  if (TapDesc $n $xml) { break }
}
Start-Sleep 2
Dump 's2_1' | Out-Null
Shot 'S2_studio_bottom_actions_FINAL'

Write-Host '=== L3 prolongar ==='
Open-Uri "/maestroSellerStudio?liveId=$($guar.live_id)&opsSection=payments" 'seller'
Start-Sleep 22
$xml = Dump 'l3_0'
$m = [regex]::Match($xml, 'content-desc="1 reserva"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
if ($m.Success) {
  $x = [int](($([int]$m.Groups[1].Value) + $([int]$m.Groups[3].Value)) / 2)
  $y = [int](($([int]$m.Groups[2].Value) + $([int]$m.Groups[4].Value)) / 2)
  & $adb -s $Device shell input tap $x $y
}
Start-Sleep 3
$xml = Dump 'l3_1'
TapDesc 'Prolongar' $xml | Out-Null
Start-Sleep 2
Dump 'l3_2' | Out-Null
Shot 'L3_prolongar_FINAL'

Write-Host '=== G2/H2 bag changed ==='
& $adb -s $Device shell wm size reset
dart run tool/phase5_5_clear_buyer_bag.dart 2>&1 | Select-Object -Last 1
dart run tool/phase5_4_seed.dart bag 2>&1 | Select-Object -Last 1
Copy-Item '14-unified-commerce-phase5.4-final-visual-proof\raw\seed_bag.json' "$raw\seed_bag.json" -Force
$bag = Get-Content "$raw\seed_bag.json" -Raw | ConvertFrom-Json
Open-Uri "/fleaberLivePlayer?liveId=$($bag.live_id)" 'buyer'
Start-Sleep 22
$xml = Dump 'g_live'
TapDesc 'Saco' $xml | Out-Null
for ($i = 0; $i -lt 14; $i++) {
  Start-Sleep 2
  $xml = Dump "gbag$i"
  if ($xml -like '*Finalizar compra*') { TapFinalizar $xml | Out-Null; break }
}
Start-Sleep 6
$xml = Dump 'g_co'
if ($xml -like '*Envio*') {
  TapDesc 'Envio' $xml | Out-Null
  Start-Sleep 1
  $xml = Dump 'genv'
  foreach ($n in @('0,00', 'Entrega em M')) { if (TapDesc $n $xml) { break } }
  Start-Sleep 1
}
Copy-Item "$raw\seed_bag.json" '14-unified-commerce-phase5.4-final-visual-proof\raw\seed_bag.json' -Force
dart run tool/phase5_4_bag_zero_b.dart 2>&1 | Tee-Object "$raw\bag_zero_b.log" | Select-Object -Last 1
Copy-Item '14-unified-commerce-phase5.4-final-visual-proof\raw\bag_zero_b.json' "$raw\bag_zero_b.json" -Force -ErrorAction SilentlyContinue
$xml = Dump 'g_pay'
$ms = [regex]::Matches($xml, 'content-desc="Pagar"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
if ($ms.Count -gt 0) {
  $m = $ms[$ms.Count - 1]
  $x = [int](($([int]$m.Groups[1].Value) + $([int]$m.Groups[3].Value)) / 2)
  $y = [int](($([int]$m.Groups[2].Value) + $([int]$m.Groups[4].Value)) / 2)
  & $adb -s $Device shell input tap $x $y
  Write-Host "TAP Pagar $x,$y"
}
Start-Sleep 6
$xml = Dump 'g_dialog'
if ($xml -like '*O saco mudou*') {
  Shot 'G2_bag_changed_no_loading_FINAL'
  Copy-Item "$raw\g_dialog.xml" "$raw\ui_G2.xml" -Force
  TapDesc 'Continuar' $xml | Out-Null
  Start-Sleep 5
  Dump 'h2' | Out-Null
  Shot 'H2_checkout_ptpt_FINAL'
  Copy-Item "$raw\h2.xml" "$raw\ui_H2.xml" -Force
} else {
  Write-Host 'G2 FAIL'
  Shot 'G2_bag_changed_no_loading_FINAL_FAILED'
}

Write-Host '=== I2 REAL landscape desktop ==='
# Force landscape physical capture: set size THEN user rotation
& $adb -s $Device shell settings put system accelerometer_rotation 0
& $adb -s $Device shell settings put system user_rotation 1
& $adb -s $Device shell wm size 1280x800
Start-Sleep 2
dart run tool/phase5_5_clear_buyer_bag.dart 2>&1 | Select-Object -Last 1
dart run tool/phase5_4_seed.dart bag 2>&1 | Select-Object -Last 1
Copy-Item '14-unified-commerce-phase5.4-final-visual-proof\raw\seed_bag.json' "$raw\seed_bag_desktop.json" -Force
$bag = Get-Content "$raw\seed_bag_desktop.json" -Raw | ConvertFrom-Json
Open-Uri "/fleaberLivePlayer?liveId=$($bag.live_id)" 'buyer'
Start-Sleep 20
$xml = Dump 'i_live'
TapDesc 'Saco' $xml | Out-Null
for ($i = 0; $i -lt 12; $i++) {
  Start-Sleep 2
  $xml = Dump "ibag$i"
  if ($xml -like '*Finalizar compra*') { TapFinalizar $xml | Out-Null; break }
}
Start-Sleep 5
$xml = Dump 'i_co'
if ($xml -like '*Envio*') {
  TapDesc 'Envio' $xml | Out-Null
  Start-Sleep 1
  $xml = Dump 'ienv'
  foreach ($n in @('0,00', 'Entrega em M')) { if (TapDesc $n $xml) { break } }
  Start-Sleep 1
}
Copy-Item "$raw\seed_bag_desktop.json" '14-unified-commerce-phase5.4-final-visual-proof\raw\seed_bag.json' -Force
dart run tool/phase5_4_bag_zero_b.dart 2>&1 | Select-Object -Last 1
Copy-Item '14-unified-commerce-phase5.4-final-visual-proof\raw\bag_zero_b.json' "$raw\bag_zero_b_desktop.json" -Force -ErrorAction SilentlyContinue
$xml = Dump 'i_pay'
$ms = [regex]::Matches($xml, 'content-desc="Pagar"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
if ($ms.Count -gt 0) {
  $m = $ms[$ms.Count - 1]
  & $adb -s $Device shell input tap ([int](($([int]$m.Groups[1].Value) + $([int]$m.Groups[3].Value)) / 2)) ([int](($([int]$m.Groups[2].Value) + $([int]$m.Groups[4].Value)) / 2))
}
Start-Sleep 6
$xml = Dump 'i_d'
if ($xml -like '*O saco mudou*') {
  Shot 'I2_bag_changed_DESKTOP_FINAL'
  Copy-Item "$raw\i_d.xml" "$raw\ui_I2.xml" -Force
  $dims = Png-Dims "$out\I2_bag_changed_DESKTOP_FINAL.png"
  "$dims" | Set-Content "$raw\I2_dimensions.txt"
  Write-Host "I2 dimensions: $dims"
  $parts = $dims -split 'x'
  if ([int]$parts[0] -le [int]$parts[1]) {
    Write-Host 'I2 STILL PORTRAIT — will try chrome/desktop fallback'
  }
} else {
  Shot 'I2_bag_changed_DESKTOP_FINAL_FAILED'
}

& $adb -s $Device shell wm size reset
& $adb -s $Device shell settings put system user_rotation 0
& $adb -s $Device shell settings put system accelerometer_rotation 1
& $adb -s $Device shell settings put global policy_control null

Write-Host '=== DONE ==='
Get-ChildItem $out\*.png | Format-Table Name, Length
