# Phase 5.4 — recapture G/H/I via real buyer live checkout
$ErrorActionPreference = 'Continue'
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$Device = 'JRK7AINR9DIJEQ8P'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$out = '14-unified-commerce-phase5.4-final-visual-proof\screenshots'
$raw = '14-unified-commerce-phase5.4-final-visual-proof\raw'

function Read-Env([string]$Key) {
  $line = Get-Content tool\live_ops_staging.env | Where-Object { $_ -match "^$Key=" } | Select-Object -First 1
  return ($line.Substring($Key.Length + 1)).Trim()
}
$buyerEmail = [uri]::EscapeDataString((Read-Env 'LIVE_OPS_TEST_BUYER_EMAIL'))
$buyerPass = [uri]::EscapeDataString((Read-Env 'LIVE_OPS_TEST_BUYER_PASSWORD'))

function Get-UiTexts {
  & $adb -s $Device shell uiautomator dump /sdcard/ui54.xml | Out-Null
  & $adb -s $Device pull /sdcard/ui54.xml "$raw\ui_bag2.xml" | Out-Null
  $xml = Get-Content "$raw\ui_bag2.xml" -Raw -ErrorAction SilentlyContinue
  if (-not $xml) { return @() }
  return [regex]::Matches($xml, 'content-desc="([^"]*)"') | ForEach-Object { $_.Groups[1].Value }
}

function Wait-UiContains([string[]]$NeedAny, [int]$TimeoutSec = 30) {
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    $texts = Get-UiTexts
    foreach ($n in $NeedAny) {
      if ($texts | Where-Object { $_ -like "*$n*" }) { return $true }
    }
    Start-Sleep 2
  }
  return $false
}

function Tap-ByDesc([string]$Needle) {
  $xml = Get-Content "$raw\ui_bag2.xml" -Raw
  $m = [regex]::Match($xml, ('content-desc="[^"]*{0}[^"]*"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"' -f [regex]::Escape($Needle)))
  if (-not $m.Success) { return $false }
  $x = [int](([int]$m.Groups[1].Value + [int]$m.Groups[3].Value) / 2)
  $y = [int](([int]$m.Groups[2].Value + [int]$m.Groups[4].Value) / 2)
  & $adb -s $Device shell input tap $x $y
  Write-Host "TAP $Needle -> $x,$y"
  return $true
}

function Shot([string]$Name) {
  & $adb -s $Device shell screencap -p /sdcard/p54.png
  & $adb -s $Device pull /sdcard/p54.png "$out\$Name.png" | Out-Null
  Write-Host "SHOT $Name $((Get-Item "$out\$Name.png").Length)"
}

Write-Host 'Reseed bag…'
dart run tool/phase5_4_seed.dart bag 2>&1 | Select-Object -Last 1
$bag = Get-Content "$raw\seed_bag.json" -Raw | ConvertFrom-Json
Write-Host "live=$($bag.live_id) begin_err=$($bag.begin_without_confirm.error)"

$next = [uri]::EscapeDataString("/fleaberLivePlayer?liveId=$($bag.live_id)")
$uri = "fleaber://fleaber.com/maestroAutologin?email=$buyerEmail&password=$buyerPass&next=$next"
& $adb -s $Device shell am force-stop pt.fleaber.app
Start-Sleep 1
& $adb -s $Device shell am start -a android.intent.action.VIEW -d "'$uri'" -n pt.fleaber.app/.MainActivity | Out-Null
Start-Sleep 20

# dismiss any leftover error dialog
Get-UiTexts | Out-Null
if (Tap-ByDesc 'OK') { Start-Sleep 1 }

# Open Saco
Get-UiTexts | Out-Null
$opened = $false
foreach ($l in @('Saco','Saco da live')) {
  if (Tap-ByDesc $l) { $opened = $true; break }
}
Start-Sleep 3
Get-UiTexts | Out-Null
# If preview, open finalize
foreach ($l in @('Pagar','Finalizar','Continuar para pagar')) {
  if (Tap-ByDesc $l) { break }
}
Start-Sleep 4
Wait-UiContains @('Finalizar compra','Pagar','Envio') 20 | Out-Null
Get-UiTexts | Out-Null
Copy-Item "$raw\ui_bag2.xml" "$raw\ui_bag_checkout_open.xml" -Force

# Prefer hand delivery to avoid invalid portes
if (Tap-ByDesc 'Envio') {
  Start-Sleep 1
  Get-UiTexts | Out-Null
  foreach ($l in @('Entrega em Mão','Entrega em mão','mão','0,00')) {
    if (Tap-ByDesc $l) { break }
  }
  Start-Sleep 1
}

Get-UiTexts | Out-Null
# Ensure both items selected if visible
foreach ($l in @('Calças ganga','Calcas ganga')) {
  Tap-ByDesc $l | Out-Null
}

# Tap sticky Pagar
$payTapped = $false
foreach ($l in @('Pagar')) {
  if (Tap-ByDesc $l) { $payTapped = $true; break }
}
if (-not $payTapped) {
  # bottom sticky approximate
  & $adb -s $Device shell input tap 360 1380
}
Start-Sleep 4

$okG = Wait-UiContains @('O saco mudou') 20
Get-UiTexts | Out-Null
Copy-Item "$raw\ui_bag2.xml" "$raw\ui_G_attempt.xml" -Force
($null = Get-UiTexts); (Get-UiTexts) -join "`n" | Set-Content "$raw\ui_G_texts.txt"

if ($okG) {
  Shot 'G_saco_mudou_REAL_390'
  if (Tap-ByDesc 'Continuar') {
    Start-Sleep 5
    Wait-UiContains @('Pagar','Finalizar','Camisa') 15 | Out-Null
    # ensure dialog gone and Calças gone
    Get-UiTexts | Out-Null
    Copy-Item "$raw\ui_bag2.xml" "$raw\ui_H.xml" -Force
    Shot 'H_checkout_depois_continuar_REAL_390'
  } else {
    Write-Host 'H NOT CAPTURED — Continuar missing'
  }
} else {
  Write-Host 'G NOT CAPTURED — dumping fail shot'
  Shot 'G_saco_mudou_REAL_390_FAILED2'
}

# Desktop-ish
& $adb -s $Device shell wm size 1280x800
Start-Sleep 2
# Re-open pay to get dialog again if possible — reseed first for clean state
dart run tool/phase5_4_seed.dart bag 2>&1 | Select-Object -Last 1
$bag = Get-Content "$raw\seed_bag.json" -Raw | ConvertFrom-Json
$next = [uri]::EscapeDataString("/fleaberLivePlayer?liveId=$($bag.live_id)")
$uri = "fleaber://fleaber.com/maestroAutologin?email=$buyerEmail&password=$buyerPass&next=$next"
& $adb -s $Device shell am force-stop pt.fleaber.app
Start-Sleep 1
& $adb -s $Device shell am start -a android.intent.action.VIEW -d "'$uri'" -n pt.fleaber.app/.MainActivity | Out-Null
Start-Sleep 18
Get-UiTexts | Out-Null
foreach ($l in @('Saco','Saco da live')) { if (Tap-ByDesc $l) { break } }
Start-Sleep 3
Get-UiTexts | Out-Null
foreach ($l in @('Pagar')) { if (Tap-ByDesc $l) { break } }
Start-Sleep 4
Get-UiTexts | Out-Null
if (Tap-ByDesc 'Envio') {
  Start-Sleep 1; Get-UiTexts | Out-Null
  foreach ($l in @('Entrega em Mão','mão','0,00')) { if (Tap-ByDesc $l) { break } }
}
Get-UiTexts | Out-Null
foreach ($l in @('Pagar')) { if (Tap-ByDesc $l) { break } }
Start-Sleep 4
$okI = Wait-UiContains @('O saco mudou') 15
if ($okI) {
  Shot 'I_saco_mudou_REAL_desktop'
  Copy-Item "$raw\ui_bag2.xml" "$raw\ui_I.xml" -Force
} else {
  Write-Host 'I NOT CAPTURED'
  Shot 'I_saco_mudou_REAL_desktop_FAILED2'
}
& $adb -s $Device shell wm size reset

Get-ChildItem $out\G*,$out\H*,$out\I* | Format-Table Name, Length
