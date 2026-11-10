# Recapture G/H/I + K2/L2 after sticky Finalizar fix
$ErrorActionPreference = 'Continue'
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$Device = 'JRK7AINR9DIJEQ8P'
Set-Location (Split-Path $PSScriptRoot -Parent)
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

function Dump-Ui([string]$Name) {
  & $adb -s $Device shell uiautomator dump /sdcard/ui55.xml | Out-Null
  & $adb -s $Device pull /sdcard/ui55.xml "$raw\$Name.xml" | Out-Null
  Get-Content "$raw\$Name.xml" -Raw -ErrorAction SilentlyContinue
}
function Shot([string]$Name) {
  & $adb -s $Device shell screencap -p /sdcard/p55.png
  & $adb -s $Device pull /sdcard/p55.png "$out\$Name.png" | Out-Null
  Write-Host "SHOT $Name $((Get-Item "$out\$Name.png").Length)"
}
function Bounds([string]$Needle, $xml) {
  $m = [regex]::Match($xml, ('content-desc="[^"]*{0}[^"]*"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"' -f [regex]::Escape($Needle)))
  if (-not $m.Success) { return $null }
  @{ x = [int](([int]$m.Groups[1].Value + [int]$m.Groups[3].Value)/2)
     y = [int](([int]$m.Groups[2].Value + [int]$m.Groups[4].Value)/2)
     y1 = [int]$m.Groups[2].Value; y2 = [int]$m.Groups[4].Value }
}
function TapN([string]$Needle, $xml, [int]$YMax = 1380) {
  $b = Bounds $Needle $xml
  if (-not $b) { Write-Host "MISS $Needle"; return $false }
  $y = [Math]::Min($b.y, $YMax)
  if ($b.y1 -lt $YMax) { $y = [Math]::Min([int](($b.y1 + [Math]::Min($b.y2,$YMax))/2), $YMax) }
  & $adb -s $Device shell input tap $b.x $y
  Write-Host "TAP $Needle $($b.x),$y"
  return $true
}
function Open-Uri([string]$Path, [string]$Who) {
  $em = if ($Who -eq 'buyer') { $buyerEmail } else { $email }
  $pw = if ($Who -eq 'buyer') { $buyerPass } else { $sellerPass }
  $uri = "fleaber://fleaber.com/maestroAutologin?email=$em&password=$pw&next=$([uri]::EscapeDataString($Path))"
  & $adb -s $Device shell am force-stop pt.fleaber.app
  Start-Sleep 1
  & $adb -s $Device shell am start -a android.intent.action.VIEW -d "'$uri'" -n pt.fleaber.app/.MainActivity | Out-Null
}

Write-Host 'Install APK'
& $adb -s $Device install -r build\app\outputs\flutter-apk\app-profile.apk | Out-Null

Write-Host 'Clear + seed'
dart run tool/phase5_5_clear_buyer_bag.dart 2>&1 | Select-Object -Last 1
dart run tool/phase5_4_seed.dart guaranteed 2>&1 | Select-Object -Last 1
Copy-Item '14-unified-commerce-phase5.4-final-visual-proof\raw\seed_guaranteed.json' "$raw\seed_guaranteed.json" -Force
dart run tool/phase5_4_seed.dart bag 2>&1 | Select-Object -Last 1
Copy-Item '14-unified-commerce-phase5.4-final-visual-proof\raw\seed_bag.json' "$raw\seed_bag.json" -Force
$guar = Get-Content "$raw\seed_guaranteed.json" -Raw | ConvertFrom-Json
$bag = Get-Content "$raw\seed_bag.json" -Raw | ConvertFrom-Json

Write-Host '=== K2/L2 ==='
Open-Uri "/maestroSellerStudio?liveId=$($guar.live_id)&opsSection=payments" 'seller'
Start-Sleep 24
$xml = Dump-Ui 'ui_kl'
# Tap reservation chip on product card (not system nav)
$b = Bounds '1 reserva' $xml
if ($b) {
  & $adb -s $Device shell input tap $b.x ([Math]::Min($b.y1 + 12, 1280))
  Write-Host "TAP reserva chip $($b.x),$([Math]::Min($b.y1+12,1280))"
}
Start-Sleep 3
$xml = Dump-Ui 'ui_kl_sheet'
if (TapN 'Confiar' $xml 1280) {
  Start-Sleep 2
  Dump-Ui 'ui_k2' | Out-Null
  Shot 'K2_confianca_REAL'
  & $adb -s $Device shell input keyevent 4
  Start-Sleep 1
} else { Write-Host 'K2 fail'; Shot 'K2_confianca_REAL_FAILED' }

$xml = Dump-Ui 'ui_kl2'
$b = Bounds '1 reserva' $xml
if ($b) { & $adb -s $Device shell input tap $b.x ([Math]::Min($b.y1 + 12, 1280)) }
Start-Sleep 3
$xml = Dump-Ui 'ui_kl2b'
if (TapN 'Prolongar' $xml 1280) {
  Start-Sleep 2
  Dump-Ui 'ui_l2' | Out-Null
  Shot 'L2_prolongar_REAL'
} else { Write-Host 'L2 fail'; Shot 'L2_prolongar_REAL_FAILED' }

Write-Host '=== G/H ==='
& $adb -s $Device shell wm size reset
Open-Uri "/fleaberLivePlayer?liveId=$($bag.live_id)" 'buyer'
Start-Sleep 22
$xml = Dump-Ui 'ui_g_live'
TapN 'Saco' $xml | Out-Null
Start-Sleep 4
$xml = Dump-Ui 'ui_g_bag'
Write-Host 'bag descs:'
([regex]::Matches($xml, 'content-desc="([^"]{5,})"') | Select-Object -First 20) | ForEach-Object { $_.Groups[1].Value }

if (-not (TapN 'Finalizar compra' $xml 1400)) {
  TapN 'Finalizar' $xml 1400 | Out-Null
}
Start-Sleep 6
$xml = Dump-Ui 'ui_g_checkout'
Write-Host 'checkout:'
([regex]::Matches($xml, 'content-desc="([^"]{5,})"') | Select-Object -First 25) | ForEach-Object { $_.Groups[1].Value }

if ($xml -notlike '*Escolhe o que*' -and $xml -notlike '*Finalizar compra*') {
  Write-Host 'checkout not open'
  Shot 'G_debug_no_checkout'
} else {
  # hand delivery if Envio present
  if ($xml -like '*Envio*') {
    TapN 'Envio' $xml | Out-Null
    Start-Sleep 1
    $xml = Dump-Ui 'ui_envio'
    foreach ($n in @('0,00','Entrega em M','mao')) { if (TapN $n $xml) { break } }
    Start-Sleep 1
    $xml = Dump-Ui 'ui_g_checkout2'
  }
  # select ganga
  $c = Bounds 'ganga' $xml
  if ($c) { & $adb -s $Device shell input tap ([Math]::Max(48,$c.x-250)) $c.y; Start-Sleep 1 }

  Copy-Item "$raw\seed_bag.json" '14-unified-commerce-phase5.4-final-visual-proof\raw\seed_bag.json' -Force
  dart run tool/phase5_4_bag_zero_b.dart 2>&1 | Tee-Object "$raw\bag_zero_b.log" | Select-Object -Last 1
  if (Test-Path '14-unified-commerce-phase5.4-final-visual-proof\raw\bag_zero_b.json') {
    Copy-Item '14-unified-commerce-phase5.4-final-visual-proof\raw\bag_zero_b.json' "$raw\bag_zero_b.json" -Force
  }

  $xml = Dump-Ui 'ui_g_before_pay'
  $ms = [regex]::Matches($xml, 'content-desc="Pagar"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
  if ($ms.Count -gt 0) {
    $m = $ms[$ms.Count-1]
    $x = [int](([int]$m.Groups[1].Value+[int]$m.Groups[3].Value)/2)
    $y = [Math]::Min([int](([int]$m.Groups[2].Value+[int]$m.Groups[4].Value)/2), 1360)
    & $adb -s $Device shell input tap $x $y
    Write-Host "TAP Pagar $x,$y"
  } else { & $adb -s $Device shell input tap 360 1300 }
  Start-Sleep 5
  $xml = Dump-Ui 'ui_g_after_pay'
  if ($xml -like '*O saco mudou*') {
    Shot 'G_saco_mudou_REAL_390'
    TapN 'Continuar' $xml | Out-Null
    Start-Sleep 5
    Dump-Ui 'ui_h' | Out-Null
    Shot 'H_checkout_depois_continuar_REAL_390'
  } else {
    Write-Host 'G FAIL'
    Shot 'G_saco_mudou_REAL_390_FAILED'
    ([regex]::Matches($xml, 'content-desc="([^"]{5,})"') | Select-Object -First 20) | ForEach-Object { $_.Groups[1].Value }
  }
}

Write-Host '=== I ==='
& $adb -s $Device shell wm size 1280x800
dart run tool/phase5_5_clear_buyer_bag.dart 2>&1 | Select-Object -Last 1
dart run tool/phase5_4_seed.dart bag 2>&1 | Select-Object -Last 1
Copy-Item '14-unified-commerce-phase5.4-final-visual-proof\raw\seed_bag.json' "$raw\seed_bag_desktop.json" -Force
$bag = Get-Content "$raw\seed_bag_desktop.json" -Raw | ConvertFrom-Json
Open-Uri "/fleaberLivePlayer?liveId=$($bag.live_id)" 'buyer'
Start-Sleep 18
$xml = Dump-Ui 'ui_i_live'
TapN 'Saco' $xml 700 | Out-Null
Start-Sleep 3
$xml = Dump-Ui 'ui_i_bag'
TapN 'Finalizar compra' $xml 750 | Out-Null
Start-Sleep 5
Copy-Item "$raw\seed_bag_desktop.json" '14-unified-commerce-phase5.4-final-visual-proof\raw\seed_bag.json' -Force
dart run tool/phase5_4_bag_zero_b.dart 2>&1 | Select-Object -Last 1
$xml = Dump-Ui 'ui_i_checkout'
$ms = [regex]::Matches($xml, 'content-desc="Pagar"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
if ($ms.Count -gt 0) {
  $m = $ms[$ms.Count-1]
  & $adb -s $Device shell input tap ([int](([int]$m.Groups[1].Value+[int]$m.Groups[3].Value)/2)) ([int](([int]$m.Groups[2].Value+[int]$m.Groups[4].Value)/2))
}
Start-Sleep 5
$xml = Dump-Ui 'ui_i_dialog'
if ($xml -like '*O saco mudou*') { Shot 'I_saco_mudou_REAL_desktop' } else { Shot 'I_saco_mudou_REAL_desktop_FAILED' }
& $adb -s $Device shell wm size reset

Get-ChildItem $out\G*,$out\H*,$out\I*,$out\K2*,$out\L2* | Format-Table Name, Length
