# Phase 5.5 REAL screenshots (ASCII-safe needles for PowerShell encoding)
$ErrorActionPreference = 'Continue'
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$Device = 'JRK7AINR9DIJEQ8P'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$out = '14-unified-commerce-phase5.5-product-polish-final\screenshots'
$raw = '14-unified-commerce-phase5.5-product-polish-final\raw'
New-Item -ItemType Directory -Force -Path $out, $raw | Out-Null

function Read-Env([string]$Key) {
  $line = Get-Content tool\live_ops_staging.env | Where-Object { $_ -match "^$Key=" } | Select-Object -First 1
  return ($line.Substring($Key.Length + 1)).Trim()
}
$email = [uri]::EscapeDataString((Read-Env 'LIVE_OPS_TEST_SELLER_EMAIL'))
$sellerPass = [uri]::EscapeDataString((Read-Env 'LIVE_OPS_TEST_SELLER_PASSWORD'))
$buyerEmail = [uri]::EscapeDataString((Read-Env 'LIVE_OPS_TEST_BUYER_EMAIL'))
$buyerPass = [uri]::EscapeDataString((Read-Env 'LIVE_OPS_TEST_BUYER_PASSWORD'))

function Dump-Ui([string]$Name = 'ui_last') {
  & $adb -s $Device shell uiautomator dump /sdcard/ui55.xml | Out-Null
  & $adb -s $Device pull /sdcard/ui55.xml "$raw\$Name.xml" | Out-Null
  return (Get-Content "$raw\$Name.xml" -Raw -ErrorAction SilentlyContinue)
}
function Shot([string]$Name) {
  & $adb -s $Device shell screencap -p /sdcard/p55.png
  & $adb -s $Device pull /sdcard/p55.png "$out\$Name.png" | Out-Null
  Write-Host "SHOT $Name $((Get-Item "$out\$Name.png").Length)"
}
function Bounds([string]$Needle, $xml) {
  $m = [regex]::Match($xml, ('content-desc="[^"]*{0}[^"]*"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"' -f [regex]::Escape($Needle)))
  if (-not $m.Success) { return $null }
  return @{
    x = [int](([int]$m.Groups[1].Value + [int]$m.Groups[3].Value) / 2)
    y = [int](([int]$m.Groups[2].Value + [int]$m.Groups[4].Value) / 2)
    y1 = [int]$m.Groups[2].Value
    y2 = [int]$m.Groups[4].Value
  }
}
function Tap-Needle([string]$Needle, $xml, [int]$YMax = 1350) {
  $b = Bounds $Needle $xml
  if (-not $b) { Write-Host "MISS $Needle"; return $false }
  $yTop = [Math]::Min($b.y2, $YMax)
  $y = [int](($b.y1 + $yTop) / 2)
  if ($y -gt $YMax) { $y = $YMax }
  & $adb -s $Device shell input tap $b.x $y
  Write-Host "TAP $Needle $($b.x),$y"
  return $true
}
function Open-Uri([string]$Path, [string]$Who = 'seller') {
  $em = if ($Who -eq 'buyer') { $buyerEmail } else { $email }
  $pw = if ($Who -eq 'buyer') { $buyerPass } else { $sellerPass }
  $next = [uri]::EscapeDataString($Path)
  $uri = "fleaber://fleaber.com/maestroAutologin?email=$em&password=$pw&next=$next"
  & $adb -s $Device shell am force-stop pt.fleaber.app
  Start-Sleep 1
  & $adb -s $Device shell am start -a android.intent.action.VIEW -d "'$uri'" -n pt.fleaber.app/.MainActivity | Out-Null
}
function Has-Text($xml, [string]$Needle) {
  return ($xml -like "*$Needle*")
}
function List-Descs($xml, [int]$N = 30) {
  $ms = [regex]::Matches($xml, 'content-desc="([^"]{4,})"')
  $i = 0
  foreach ($m in $ms) {
    if ($i -ge $N) { break }
    Write-Host ("  DESC: " + $m.Groups[1].Value)
    $i++
  }
}

Write-Host '=== SEED ==='
Write-Host 'Clear stale buyer bag lines…'
dart run tool/phase5_5_clear_buyer_bag.dart 2>&1 | Select-Object -Last 1
dart run tool/phase5_4_seed.dart realistic 2>&1 | Select-Object -Last 1
Copy-Item '14-unified-commerce-phase5.4-final-visual-proof\raw\seed_realistic.json' "$raw\seed_realistic.json" -Force
dart run tool/phase5_4_seed.dart guaranteed 2>&1 | Select-Object -Last 1
Copy-Item '14-unified-commerce-phase5.4-final-visual-proof\raw\seed_guaranteed.json' "$raw\seed_guaranteed.json" -Force
dart run tool/phase5_4_seed.dart bag 2>&1 | Select-Object -Last 1
Copy-Item '14-unified-commerce-phase5.4-final-visual-proof\raw\seed_bag.json' "$raw\seed_bag.json" -Force

$real = Get-Content "$raw\seed_realistic.json" -Raw | ConvertFrom-Json
$guar = Get-Content "$raw\seed_guaranteed.json" -Raw | ConvertFrom-Json
$bag = Get-Content "$raw\seed_bag.json" -Raw | ConvertFrom-Json

Write-Host '=== P1/P2 policy ==='
Open-Uri '/contaDefinicoes' 'seller'
Start-Sleep 14
Dump-Ui 'ui_settings' | Out-Null
& $adb -s $Device shell input swipe 360 1200 360 400 450
Start-Sleep 1
$xml = Dump-Ui 'ui_settings2'
if (-not (Tap-Needle 'Configurar reservas' $xml)) {
  Tap-Needle 'Reservas no directo' $xml | Out-Null
  Start-Sleep 1
  $xml = Dump-Ui 'ui_settings3'
  Tap-Needle 'Configurar reservas' $xml | Out-Null
}
Start-Sleep 3
$xml = Dump-Ui 'ui_policy_closed'
Shot 'P1_policy_selector_REAL'
# Tap current duration value to open dropdown
if (-not (Tap-Needle '1 hora' $xml)) {
  if (-not (Tap-Needle '1 dia' $xml)) {
    Tap-Needle 'Duração normal' $xml | Out-Null
  }
}
Start-Sleep 2
$xml = Dump-Ui 'ui_policy_open'
Shot 'P2_policy_selector_open_REAL'
& $adb -s $Device shell input keyevent 4
Start-Sleep 1

Write-Host '=== S1 studio ==='
Open-Uri "/maestroSellerStudio?liveId=$($real.live_id)&opsSection=payments" 'seller'
Start-Sleep 24
Dump-Ui 'ui_S1' | Out-Null
Shot 'S1_studio_polished_REAL'

Write-Host '=== K2 / L2 ==='
Open-Uri "/maestroSellerStudio?liveId=$($guar.live_id)&opsSection=payments" 'seller'
Start-Sleep 22
$xml = Dump-Ui 'ui_KL'
Tap-Needle '1 reserva' $xml | Out-Null
Start-Sleep 3
$xml = Dump-Ui 'ui_KL_sheet'
if (Tap-Needle 'Confiar' $xml) {
  Start-Sleep 2
  Dump-Ui 'ui_K2' | Out-Null
  Shot 'K2_confianca_REAL'
  & $adb -s $Device shell input keyevent 4
  Start-Sleep 1
} else { Shot 'K2_confianca_REAL_FAILED' }

$xml = Dump-Ui 'ui_KL2'
if (-not (Tap-Needle '1 reserva' $xml)) { Tap-Needle 'reserva' $xml | Out-Null }
Start-Sleep 2
$xml = Dump-Ui 'ui_KL2b'
if (Tap-Needle 'Prolongar' $xml) {
  Start-Sleep 2
  Dump-Ui 'ui_L2' | Out-Null
  Shot 'L2_prolongar_REAL'
  & $adb -s $Device shell input keyevent 4
} else { Shot 'L2_prolongar_REAL_FAILED' }

Write-Host '=== G/H bag ==='
& $adb -s $Device shell wm size reset
Open-Uri "/fleaberLivePlayer?liveId=$($bag.live_id)" 'buyer'
Start-Sleep 22
$xml = Dump-Ui 'ui_bag_live'
Tap-Needle 'Saco' $xml | Out-Null
Start-Sleep 3
for ($i = 0; $i -lt 4; $i++) {
  & $adb -s $Device shell input swipe 360 1100 360 450 320
  Start-Sleep 1
}
$xml = Dump-Ui 'ui_bag_scrolled'
$fin = Bounds 'Finalizar compra' $xml
if ($fin) {
  $ty = [Math]::Min($fin.y1 + 16, 1320)
  & $adb -s $Device shell input tap $fin.x $ty
  Write-Host "TAP Finalizar $($fin.x),$ty"
} else {
  Write-Host 'Finalizar missing'
  List-Descs $xml 20
}
Start-Sleep 6
$xml = Dump-Ui 'ui_checkout'
Write-Host '--- checkout ---'
List-Descs $xml 35

$opened = (Has-Text $xml 'Finalizar compra') -or (Has-Text $xml 'Escolhe o que queres')
if (-not $opened) {
  Write-Host 'Retry open checkout'
  Open-Uri "/fleaberLivePlayer?liveId=$($bag.live_id)" 'buyer'
  Start-Sleep 18
  $xml = Dump-Ui 'ui_bag_retry'
  Tap-Needle 'Saco' $xml | Out-Null
  Start-Sleep 2
  & $adb -s $Device shell input swipe 360 1250 360 200 500
  Start-Sleep 1
  $xml = Dump-Ui 'ui_bag_retry2'
  $fin = Bounds 'Finalizar compra' $xml
  if ($fin) {
    & $adb -s $Device shell input tap $fin.x ([Math]::Min($fin.y1 + 12, 1300))
  }
  Start-Sleep 6
  $xml = Dump-Ui 'ui_checkout'
  List-Descs $xml 30
}

if (Has-Text $xml 'Envio') {
  Tap-Needle 'Envio' $xml | Out-Null
  Start-Sleep 1
  $xml = Dump-Ui 'ui_envio'
  foreach ($n in @('Entrega em M', '0,00', 'mao')) {
    if (Tap-Needle $n $xml 1400) { break }
  }
  Start-Sleep 1
  $xml = Dump-Ui 'ui_checkout2'
}

# Select ganga row checkbox area if present
$c = Bounds 'ganga' $xml
if ($c) {
  & $adb -s $Device shell input tap ([Math]::Max(48, $c.x - 260)) $c.y
  Write-Host 'tap ganga checkbox area'
  Start-Sleep 1
}

Write-Host 'Zero B'
Copy-Item "$raw\seed_bag.json" '14-unified-commerce-phase5.4-final-visual-proof\raw\seed_bag.json' -Force
dart run tool/phase5_4_bag_zero_b.dart 2>&1 | Tee-Object -FilePath "$raw\bag_zero_b.log" | Select-Object -Last 1
if (Test-Path '14-unified-commerce-phase5.4-final-visual-proof\raw\bag_zero_b.json') {
  Copy-Item '14-unified-commerce-phase5.4-final-visual-proof\raw\bag_zero_b.json' "$raw\bag_zero_b.json" -Force
}

$xml = Dump-Ui 'ui_before_pay'
$ms = [regex]::Matches($xml, 'content-desc="Pagar"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
if ($ms.Count -gt 0) {
  $m = $ms[$ms.Count - 1]
  $x = [int](([int]$m.Groups[1].Value + [int]$m.Groups[3].Value) / 2)
  $y = [Math]::Min([int](([int]$m.Groups[2].Value + [int]$m.Groups[4].Value) / 2), 1350)
  & $adb -s $Device shell input tap $x $y
  Write-Host "TAP Pagar $x,$y"
} else {
  & $adb -s $Device shell input tap 360 1280
}
Start-Sleep 5
$xml = Dump-Ui 'ui_after_pay'
Copy-Item "$raw\ui_after_pay.xml" "$raw\ui_G_attempt.xml" -Force
if (Has-Text $xml 'O saco mudou') {
  Shot 'G_saco_mudou_REAL_390'
  Tap-Needle 'Continuar' $xml | Out-Null
  Start-Sleep 5
  Dump-Ui 'ui_H' | Out-Null
  Shot 'H_checkout_depois_continuar_REAL_390'
} else {
  Write-Host 'G NOT CAPTURED'
  Shot 'G_saco_mudou_REAL_390_FAILED'
  List-Descs $xml 25
}

Write-Host '=== I desktop ==='
& $adb -s $Device shell wm size 1280x800
dart run tool/phase5_4_seed.dart bag 2>&1 | Select-Object -Last 1
Copy-Item '14-unified-commerce-phase5.4-final-visual-proof\raw\seed_bag.json' "$raw\seed_bag_desktop.json" -Force
$bag = Get-Content "$raw\seed_bag_desktop.json" -Raw | ConvertFrom-Json
Open-Uri "/fleaberLivePlayer?liveId=$($bag.live_id)" 'buyer'
Start-Sleep 18
$xml = Dump-Ui 'ui_I_live'
Tap-Needle 'Saco' $xml 700 | Out-Null
Start-Sleep 2
& $adb -s $Device shell input swipe 640 650 640 150 400
Start-Sleep 1
$xml = Dump-Ui 'ui_I_bag'
$fin = Bounds 'Finalizar compra' $xml
if ($fin) { & $adb -s $Device shell input tap $fin.x ([Math]::Min($fin.y1 + 10, 700)) }
Start-Sleep 5
Copy-Item "$raw\seed_bag_desktop.json" '14-unified-commerce-phase5.4-final-visual-proof\raw\seed_bag.json' -Force
dart run tool/phase5_4_bag_zero_b.dart 2>&1 | Select-Object -Last 1
$xml = Dump-Ui 'ui_I_checkout'
$ms = [regex]::Matches($xml, 'content-desc="Pagar"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
if ($ms.Count -gt 0) {
  $m = $ms[$ms.Count - 1]
  $x = [int](([int]$m.Groups[1].Value + [int]$m.Groups[3].Value) / 2)
  $y = [int](([int]$m.Groups[2].Value + [int]$m.Groups[4].Value) / 2)
  & $adb -s $Device shell input tap $x $y
}
Start-Sleep 5
$xml = Dump-Ui 'ui_I_dialog'
if (Has-Text $xml 'O saco mudou') {
  Shot 'I_saco_mudou_REAL_desktop'
} else {
  Write-Host 'I NOT CAPTURED'
  Shot 'I_saco_mudou_REAL_desktop_FAILED'
}
& $adb -s $Device shell wm size reset

Write-Host '=== DONE ==='
Get-ChildItem $out\*.png | Format-Table Name, Length
