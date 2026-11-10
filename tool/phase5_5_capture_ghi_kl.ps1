# Phase 5.5 — G/H/I + K2/L2 real captures (nav-safe Finalizar tap)
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
$buyerEmail = [uri]::EscapeDataString((Read-Env 'LIVE_OPS_TEST_BUYER_EMAIL'))
$buyerPass = [uri]::EscapeDataString((Read-Env 'LIVE_OPS_TEST_BUYER_PASSWORD'))
$email = [uri]::EscapeDataString((Read-Env 'LIVE_OPS_TEST_SELLER_EMAIL'))
$sellerPass = [uri]::EscapeDataString((Read-Env 'LIVE_OPS_TEST_SELLER_PASSWORD'))

function Dump([string]$n) {
  & $adb -s $Device shell uiautomator dump /sdcard/ui55.xml | Out-Null
  & $adb -s $Device pull /sdcard/ui55.xml "$raw\$n.xml" | Out-Null
  return (Get-Content "$raw\$n.xml" -Raw -ErrorAction SilentlyContinue)
}
function Shot([string]$n) {
  & $adb -s $Device shell screencap -p /sdcard/p55.png
  & $adb -s $Device pull /sdcard/p55.png "$out\$n.png" | Out-Null
  Write-Host "SHOT $n $((Get-Item "$out\$n.png").Length)"
}
function ListDesc($xml, [int]$n = 30) {
  [regex]::Matches($xml, 'content-desc="([^"]{4,})"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -First $n
}
function Bounds([string]$needle, $xml) {
  $m = [regex]::Match($xml, ('content-desc="[^"]*{0}[^"]*"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"' -f [regex]::Escape($needle)))
  if (-not $m.Success) { return $null }
  return @{
    x1 = [int]$m.Groups[1].Value; y1 = [int]$m.Groups[2].Value
    x2 = [int]$m.Groups[3].Value; y2 = [int]$m.Groups[4].Value
    x  = [int](([int]$m.Groups[1].Value + [int]$m.Groups[3].Value) / 2)
    y  = [int](([int]$m.Groups[2].Value + [int]$m.Groups[4].Value) / 2)
  }
}
# Tap near top of control to avoid Android nav bar eating the hit
function TapTop([string]$needle, $xml, [int]$ymax = 1320) {
  $b = Bounds $needle $xml
  if (-not $b) { Write-Host "MISS $needle"; return $false }
  $y = [Math]::Min($b.y1 + 18, $ymax)
  & $adb -s $Device shell input tap $b.x $y
  Write-Host "TAP-TOP $needle $($b.x),$y (bounds $($b.y1)-$($b.y2))"
  return $true
}
function TapCenter([string]$needle, $xml, [int]$ymax = 1360) {
  $b = Bounds $needle $xml
  if (-not $b) { Write-Host "MISS $needle"; return $false }
  $y = [Math]::Min($b.y, $ymax)
  & $adb -s $Device shell input tap $b.x $y
  Write-Host "TAP $needle $($b.x),$y"
  return $true
}
function Open-Buyer([string]$liveId) {
  $next = [uri]::EscapeDataString("/fleaberLivePlayer?liveId=$liveId")
  $uri = "fleaber://fleaber.com/maestroAutologin?email=$buyerEmail&password=$buyerPass&next=$next"
  & $adb -s $Device shell am force-stop pt.fleaber.app
  Start-Sleep 1
  & $adb -s $Device shell am start -a android.intent.action.VIEW -d "'$uri'" -n pt.fleaber.app/.MainActivity | Out-Null
}
function Open-Studio([string]$liveId, [string]$ops) {
  $next = [uri]::EscapeDataString("/maestroSellerStudio?liveId=$liveId&opsSection=$ops")
  $uri = "fleaber://fleaber.com/maestroAutologin?email=$email&password=$sellerPass&next=$next"
  & $adb -s $Device shell am force-stop pt.fleaber.app
  Start-Sleep 1
  & $adb -s $Device shell am start -a android.intent.action.VIEW -d "'$uri'" -n pt.fleaber.app/.MainActivity | Out-Null
}
function Wait-Has([string[]]$need, [int]$sec = 30) {
  $deadline = (Get-Date).AddSeconds($sec)
  while ((Get-Date) -lt $deadline) {
    $xml = Dump 'wait'
    foreach ($n in $need) { if ($xml -like "*$n*") { return $xml } }
    Start-Sleep 2
  }
  return (Dump 'wait_fail')
}
function Sync-SeedBag {
  Copy-Item "$raw\seed_bag.json" '14-unified-commerce-phase5.4-final-visual-proof\raw\seed_bag.json' -Force
}
function Zero-B {
  Sync-SeedBag
  dart run tool/phase5_4_bag_zero_b.dart 2>&1 | Tee-Object "$raw\bag_zero_b.log" | Select-Object -Last 1
  if (Test-Path '14-unified-commerce-phase5.4-final-visual-proof\raw\bag_zero_b.json') {
    Copy-Item '14-unified-commerce-phase5.4-final-visual-proof\raw\bag_zero_b.json' "$raw\bag_zero_b.json" -Force
  }
}
function Open-Bag-Then-Checkout([int]$ymax = 1320) {
  $xml = Dump 'live'
  TapCenter 'Saco' $xml $ymax | Out-Null
  $got = $false
  for ($i = 0; $i -lt 16; $i++) {
    Start-Sleep 2
    $xml = Dump "bag$i"
    if ($xml -like '*Finalizar compra*') {
      if (TapTop 'Finalizar compra' $xml $ymax) { $got = $true; break }
    }
    Write-Host "bag wait $i"
  }
  if (-not $got) { return $null }
  Start-Sleep 5
  $xml = Dump 'after_fin'
  # multi-select pay picker?
  if ($xml -like '*Escolhe as reservas*') {
    Write-Host 'pay picker — select all rows'
    foreach ($n in @('Camisa','Calças','Calcas','ganga','branca')) {
      TapCenter $n $xml $ymax | Out-Null
    }
    Start-Sleep 1
    $xml = Dump 'picker2'
    if (-not (TapTop 'Continuar pagamento' $xml $ymax)) {
      TapCenter 'Continuar' $xml $ymax | Out-Null
    }
    Start-Sleep 5
    $xml = Dump 'after_picker'
  }
  # checkout sheet?
  if ($xml -like '*Escolhe o que queres*' -or $xml -like '*Pagar*' -or $xml -like '*Finalizar compra*') {
    if ($xml -like '*Envio*') {
      TapCenter 'Envio' $xml $ymax | Out-Null
      Start-Sleep 1
      $xml = Dump 'envio'
      foreach ($n in @('Entrega em M','0,00','mão','mao')) {
        if (TapCenter $n $xml $ymax) { break }
      }
      Start-Sleep 1
      $xml = Dump 'checkout_ready'
    }
    return $xml
  }
  Write-Host 'checkout not open'
  ListDesc $xml 25
  return $null
}
function Tap-Sticky-Pagar($xml, [int]$ymax = 1350) {
  $ms = [regex]::Matches($xml, 'content-desc="Pagar"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
  Write-Host "Pagar matches $($ms.Count)"
  if ($ms.Count -eq 0) {
    & $adb -s $Device shell input tap 360 ([Math]::Min(1280, $ymax))
    return
  }
  $m = $ms[$ms.Count - 1]
  $x = [int](([int]$m.Groups[1].Value + [int]$m.Groups[3].Value) / 2)
  $y1 = [int]$m.Groups[2].Value
  $y = [Math]::Min($y1 + 18, $ymax)
  & $adb -s $Device shell input tap $x $y
  Write-Host "TAP sticky Pagar $x,$y"
}

Write-Host '=== G/H mobile ==='
& $adb -s $Device shell wm size reset
dart run tool/phase5_5_clear_buyer_bag.dart 2>&1 | Select-Object -Last 1
dart run tool/phase5_4_seed.dart bag 2>&1 | Select-Object -Last 1
Copy-Item '14-unified-commerce-phase5.4-final-visual-proof\raw\seed_bag.json' "$raw\seed_bag.json" -Force
$bag = Get-Content "$raw\seed_bag.json" -Raw | ConvertFrom-Json
Write-Host "live=$($bag.live_id)"

Open-Buyer $bag.live_id
Start-Sleep 20
$co = Open-Bag-Then-Checkout 1320
if ($null -eq $co) {
  Shot 'G_saco_mudou_REAL_390_FAILED'
  Write-Host 'G FAIL — no checkout'
} else {
  Write-Host 'checkout open — zero B then Pagar'
  ListDesc $co 20
  Zero-B
  $xml = Dump 'before_pay'
  Tap-Sticky-Pagar $xml 1350
  Start-Sleep 5
  $xml = Dump 'g_dialog'
  ListDesc $xml 20
  if ($xml -like '*O saco mudou*') {
    Shot 'G_saco_mudou_REAL_390'
    Copy-Item "$raw\g_dialog.xml" "$raw\ui_G.xml" -Force
    TapCenter 'Continuar' $xml 1360 | Out-Null
    Start-Sleep 5
    Dump 'h' | Out-Null
    Shot 'H_checkout_depois_continuar_REAL_390'
    Copy-Item "$raw\h.xml" "$raw\ui_H.xml" -Force
  } else {
    Write-Host 'G FAIL — no dialog'
    Shot 'G_saco_mudou_REAL_390_FAILED'
  }
}

Write-Host '=== I desktop ==='
& $adb -s $Device shell wm size 1280x800
dart run tool/phase5_5_clear_buyer_bag.dart 2>&1 | Select-Object -Last 1
dart run tool/phase5_4_seed.dart bag 2>&1 | Select-Object -Last 1
Copy-Item '14-unified-commerce-phase5.4-final-visual-proof\raw\seed_bag.json' "$raw\seed_bag_desktop.json" -Force
$bag = Get-Content "$raw\seed_bag_desktop.json" -Raw | ConvertFrom-Json
Open-Buyer $bag.live_id
Start-Sleep 18
$co = Open-Bag-Then-Checkout 720
if ($null -eq $co) {
  Shot 'I_saco_mudou_REAL_desktop_FAILED'
} else {
  Copy-Item "$raw\seed_bag_desktop.json" "$raw\seed_bag.json" -Force
  Zero-B
  $xml = Dump 'i_before_pay'
  Tap-Sticky-Pagar $xml 750
  Start-Sleep 5
  $xml = Dump 'i_dialog'
  if ($xml -like '*O saco mudou*') {
    Shot 'I_saco_mudou_REAL_desktop'
    Copy-Item "$raw\i_dialog.xml" "$raw\ui_I.xml" -Force
  } else {
    Write-Host 'I FAIL'
    ListDesc $xml 20
    Shot 'I_saco_mudou_REAL_desktop_FAILED'
  }
}
& $adb -s $Device shell wm size reset

Write-Host '=== K2/L2 trust+extend ==='
dart run tool/phase5_4_seed.dart guaranteed 2>&1 | Select-Object -Last 1
Copy-Item '14-unified-commerce-phase5.4-final-visual-proof\raw\seed_guaranteed.json' "$raw\seed_guaranteed.json" -Force
$guar = Get-Content "$raw\seed_guaranteed.json" -Raw | ConvertFrom-Json
Open-Studio $guar.live_id 'payments'
Start-Sleep 24
$xml = Wait-Has @('Aguardam pagamento','aguarda pagamento','1 reserva','VF04') 30
# Tap the reservation chip — prefer exact "1 reserva" near top of bounds
$opened = $false
foreach ($n in @('1 reserva','Ref VF04','Vestido floral')) {
  if (TapTop $n $xml 1400) { $opened = $true; break }
}
if (-not $opened) {
  # try all matches of reserva
  $ms = [regex]::Matches($xml, 'content-desc="[^"]*reserva[^"]*"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
  foreach ($m in $ms) {
    $x = [int](([int]$m.Groups[1].Value + [int]$m.Groups[3].Value) / 2)
    $y = [int]$m.Groups[2].Value + 12
    & $adb -s $Device shell input tap $x $y
    Write-Host "TAP reserva-ish $x,$y"
    Start-Sleep 2
    $xml = Dump 'k_try'
    if ($xml -like '*Confiar*' -or $xml -like '*Prolongar*') { $opened = $true; break }
  }
}
Start-Sleep 3
$xml = Dump 'k_sheet'
ListDesc $xml 25
if ($xml -like '*Confiar*') {
  TapCenter 'Confiar' $xml 1400 | Out-Null
  Start-Sleep 2
  Dump 'k2' | Out-Null
  Shot 'K2_confianca_REAL'
  Copy-Item "$raw\k2.xml" "$raw\ui_K2.xml" -Force
  & $adb -s $Device shell input keyevent 4
  Start-Sleep 1
} else {
  Shot 'K2_confianca_REAL_FAILED'
}

$xml = Dump 'k_reopen'
foreach ($n in @('1 reserva','Ref VF04','Vestido floral')) {
  if (TapTop $n $xml 1400) { break }
}
Start-Sleep 3
$xml = Dump 'l_sheet'
if ($xml -like '*Prolongar*') {
  TapCenter 'Prolongar' $xml 1400 | Out-Null
  Start-Sleep 2
  Dump 'l2' | Out-Null
  Shot 'L2_prolongar_REAL'
  Copy-Item "$raw\l2.xml" "$raw\ui_L2.xml" -Force
} else {
  Shot 'L2_prolongar_REAL_FAILED'
  ListDesc $xml 20
}

Write-Host '=== DONE ==='
Get-ChildItem $out\G*,$out\H*,$out\I*,$out\K2*,$out\L2*,$out\P*,$out\S1* -ErrorAction SilentlyContinue | Format-Table Name, Length
