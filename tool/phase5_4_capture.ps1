# Phase 5.4 — REAL device screenshots (TCL). Requires profile/debug APK installed.
$ErrorActionPreference = 'Continue'
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$Device = 'JRK7AINR9DIJEQ8P'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$out = '14-unified-commerce-phase5.4-final-visual-proof\screenshots'
$raw = '14-unified-commerce-phase5.4-final-visual-proof\raw'
New-Item -ItemType Directory -Force -Path $out, $raw | Out-Null
function Read-Env([string]$Key) {
  $line = Get-Content tool\live_ops_staging.env | Where-Object { $_ -match "^$Key=" } | Select-Object -First 1
  if (-not $line) { throw "missing $Key in live_ops_staging.env" }
  return ($line.Substring($Key.Length + 1)).Trim()
}
$email = [uri]::EscapeDataString((Read-Env 'LIVE_OPS_TEST_SELLER_EMAIL'))
$sellerPass = [uri]::EscapeDataString((Read-Env 'LIVE_OPS_TEST_SELLER_PASSWORD'))
$buyerEmail = [uri]::EscapeDataString((Read-Env 'LIVE_OPS_TEST_BUYER_EMAIL'))
$buyerPass = [uri]::EscapeDataString((Read-Env 'LIVE_OPS_TEST_BUYER_PASSWORD'))

function Get-UiTexts {
  & $adb -s $Device shell uiautomator dump /sdcard/ui54.xml | Out-Null
  & $adb -s $Device pull /sdcard/ui54.xml "$raw\ui_last.xml" | Out-Null
  $xml = Get-Content "$raw\ui_last.xml" -Raw -ErrorAction SilentlyContinue
  if (-not $xml) { return @() }
  return [regex]::Matches($xml, 'content-desc="([^"]*)"') | ForEach-Object { $_.Groups[1].Value }
}

function Wait-UiContains([string[]]$NeedAny, [int]$TimeoutSec = 40) {
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    $texts = Get-UiTexts
    foreach ($n in $NeedAny) {
      if ($texts | Where-Object { $_ -like "*$n*" }) {
        return $true
      }
    }
    Start-Sleep 2
  }
  return $false
}

function Tap-ByDesc([string]$Needle) {
  $xml = Get-Content "$raw\ui_last.xml" -Raw
  $m = [regex]::Match($xml, ('content-desc="{0}"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"' -f [regex]::Escape($Needle)))
  if (-not $m.Success) {
    # multiline content-desc
    $m = [regex]::Match($xml, ('content-desc="[^"]*{0}[^"]*"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"' -f [regex]::Escape($Needle)))
  }
  if (-not $m.Success) { return $false }
  $x = [int](([int]$m.Groups[1].Value + [int]$m.Groups[3].Value) / 2)
  $y = [int](([int]$m.Groups[2].Value + [int]$m.Groups[4].Value) / 2)
  & $adb -s $Device shell input tap $x $y
  return $true
}

function Shot([string]$Name) {
  & $adb -s $Device shell screencap -p /sdcard/p54.png
  & $adb -s $Device pull /sdcard/p54.png "$out\$Name.png" | Out-Null
  $len = (Get-Item "$out\$Name.png").Length
  Write-Host "SHOT $Name bytes=$len"
}

function Open-Studio([string]$LiveId, [string]$Ops = 'queue', [int]$WaitSec = 22) {
  $next = [uri]::EscapeDataString("/maestroSellerStudio?liveId=$LiveId&opsSection=$Ops")
  $uri = "fleaber://fleaber.com/maestroAutologin?email=$email&password=$sellerPass&next=$next"
  & $adb -s $Device shell am force-stop pt.fleaber.app
  Start-Sleep 1
  & $adb -s $Device shell am start -a android.intent.action.VIEW -d "'$uri'" -n pt.fleaber.app/.MainActivity | Out-Null
  Start-Sleep $WaitSec
}

function Open-BuyerLive([string]$LiveId, [int]$WaitSec = 20) {
  $next = [uri]::EscapeDataString("/fleaberLivePlayer?liveId=$LiveId")
  $uri = "fleaber://fleaber.com/maestroAutologin?email=$buyerEmail&password=$buyerPass&next=$next"
  & $adb -s $Device shell am force-stop pt.fleaber.app
  Start-Sleep 1
  & $adb -s $Device shell am start -a android.intent.action.VIEW -d "'$uri'" -n pt.fleaber.app/.MainActivity | Out-Null
  Start-Sleep $WaitSec
}

function Open-SellerSettings([int]$WaitSec = 16) {
  $next = [uri]::EscapeDataString('/contaDefinicoes')
  $uri = "fleaber://fleaber.com/maestroAutologin?email=$email&password=$sellerPass&next=$next"
  & $adb -s $Device shell am force-stop pt.fleaber.app
  Start-Sleep 1
  & $adb -s $Device shell am start -a android.intent.action.VIEW -d "'$uri'" -n pt.fleaber.app/.MainActivity | Out-Null
  Start-Sleep $WaitSec
}

Write-Host '=== SEED ==='
dart run tool/phase5_4_seed.dart realistic 2>&1 | Select-Object -Last 1
dart run tool/phase5_4_seed.dart guaranteed 2>&1 | Select-Object -Last 1
dart run tool/phase5_4_seed.dart cancel 2>&1 | Select-Object -Last 1
dart run tool/phase5_4_seed.dart expiry 2>&1 | Select-Object -Last 1
dart run tool/phase5_4_seed.dart pending 2>&1 | Select-Object -Last 1
dart run tool/phase5_4_seed.dart bag 2>&1 | Select-Object -Last 1

$real = Get-Content "$raw\seed_realistic.json" -Raw | ConvertFrom-Json
$guar = Get-Content "$raw\seed_guaranteed.json" -Raw | ConvertFrom-Json
$canc = Get-Content "$raw\seed_cancel.json" -Raw | ConvertFrom-Json
$exp = Get-Content "$raw\seed_expiry.json" -Raw | ConvertFrom-Json
$pend = Get-Content "$raw\seed_pending.json" -Raw | ConvertFrom-Json
$bag = Get-Content "$raw\seed_bag.json" -Raw | ConvertFrom-Json

Write-Host '=== A pending Recusar ==='
Open-Studio $pend.live_id 'queue' 24
$null = Wait-UiContains @('Recusar','Aceitar','Pendentes') 30
Shot 'A_studio_pending_REAL'
Copy-Item "$raw\ui_last.xml" "$raw\ui_A.xml" -Force

Write-Host '=== B guaranteed ==='
Open-Studio $guar.live_id 'payments' 26
$okB = Wait-UiContains @('Aguardam pagamento','aguarda pagamento','reserva') 35
if (-not $okB) { Wait-UiContains @('A receber','Operação') 10 | Out-Null }
# Ensure not spinner-only: require readable content
$textsB = Get-UiTexts
($textsB -join "`n") | Set-Content "$raw\ui_B_texts.txt"
if ($textsB -match 'Aguardam|aguarda|Maria|Vestido|VF04|reserva') {
  Shot 'B_studio_guaranteed_REAL'
} else {
  Write-Host 'B VISUAL EVIDENCE NOT CAPTURED — UI not stable'
  Shot 'B_studio_guaranteed_REAL_FAILED'
}
Copy-Item "$raw\ui_last.xml" "$raw\ui_B.xml" -Force

Write-Host '=== K trust + L extend ==='
Open-Studio $guar.live_id 'payments' 20
Wait-UiContains @('reserva','A receber','Aguardam') 25 | Out-Null
Get-UiTexts | Out-Null
# open item reservations sheet
if (-not (Tap-ByDesc '1 reserva')) {
  Tap-ByDesc 'reserva' | Out-Null
}
Start-Sleep 3
Get-UiTexts | Out-Null
Copy-Item "$raw\ui_last.xml" "$raw\ui_KL_sheet.xml" -Force
if (Tap-ByDesc 'Confiar') {
  Start-Sleep 2
  $okK = Wait-UiContains @('Marcar como cliente de confiança') 8
  Shot 'K_confianca_REAL'
  Copy-Item "$raw\ui_last.xml" "$raw\ui_K.xml" -Force
  & $adb -s $Device shell input keyevent 4
  Start-Sleep 1
} else {
  Write-Host 'K VISUAL EVIDENCE NOT CAPTURED — Confiar not found'
  Shot 'K_confianca_REAL_FAILED'
}

Get-UiTexts | Out-Null
if (-not (Tap-ByDesc '1 reserva')) { Tap-ByDesc 'reserva' | Out-Null }
Start-Sleep 2
Get-UiTexts | Out-Null
if (Tap-ByDesc 'Prolongar') {
  Start-Sleep 2
  Wait-UiContains @('Prolongar reserva') 8 | Out-Null
  Shot 'L_prolongar_REAL'
  Copy-Item "$raw\ui_last.xml" "$raw\ui_L.xml" -Force
  & $adb -s $Device shell input keyevent 4
} else {
  Write-Host 'L VISUAL EVIDENCE NOT CAPTURED — Prolongar not found'
  Shot 'L_prolongar_REAL_FAILED'
}

Write-Host '=== D cancel history ==='
dart run tool/phase5_4_cancel.dart 2>&1 | Select-Object -Last 1
Open-Studio $canc.live_id 'history' 26
$okD = Wait-UiContains @('cancelou a reserva','Histórico') 35
Shot 'D_studio_historico_cancel_REAL'
Copy-Item "$raw\ui_last.xml" "$raw\ui_D.xml" -Force
if (-not $okD) { Write-Host 'D WARNING: cancel copy not visible in UI dump' }

Write-Host '=== E expiry history ==='
dart run tool/phase5_4_expire.dart 2>&1 | Select-Object -Last 1
Open-Studio $exp.live_id 'history' 26
$okE = Wait-UiContains @('expirou','Histórico') 35
Shot 'E_studio_historico_expiry_REAL'
Copy-Item "$raw\ui_last.xml" "$raw\ui_E.xml" -Force

Write-Host '=== R realistic studio ==='
Open-Studio $real.live_id 'payments' 26
Wait-UiContains @('Novidades de Outono','Casaco','Maria','CB01','Aguardam') 35 | Out-Null
Shot 'R_studio_realistic_REAL'
Copy-Item "$raw\ui_last.xml" "$raw\ui_R.xml" -Force

Write-Host '=== J policy ==='
Open-SellerSettings 18
Wait-UiContains @('Configurar reservas','Defini') 20 | Out-Null
Get-UiTexts | Out-Null
if (Tap-ByDesc 'Configurar reservas') {
  Start-Sleep 3
  Wait-UiContains @('Pedir autorização','pagamento garante','confiança') 15 | Out-Null
  Shot 'J_politica_reservas_REAL'
  Copy-Item "$raw\ui_last.xml" "$raw\ui_J.xml" -Force
} else {
  Write-Host 'J VISUAL EVIDENCE NOT CAPTURED'
  Shot 'J_politica_reservas_REAL_FAILED'
}

Write-Host '=== G/H bag changed via buyer live ==='
Open-BuyerLive $bag.live_id 22
Wait-UiContains @('Saco','Pagar','Reserv','Artigo') 25 | Out-Null
Get-UiTexts | Out-Null
Copy-Item "$raw\ui_last.xml" "$raw\ui_bag_entry.xml" -Force
# Try open bag / pay
$tapped = $false
foreach ($label in @('Pagar','Saco','Ver saco','Reservas')) {
  if (Tap-ByDesc $label) { $tapped = $true; break }
}
Start-Sleep 3
Get-UiTexts | Out-Null
if (-not (Wait-UiContains @('O saco mudou') 5)) {
  foreach ($label in @('Pagar')) {
    if (Tap-ByDesc $label) { break }
  }
  Start-Sleep 3
}
$okG = Wait-UiContains @('O saco mudou') 12
if ($okG) {
  Shot 'G_saco_mudou_REAL_390'
  Copy-Item "$raw\ui_last.xml" "$raw\ui_G.xml" -Force
  if (Tap-ByDesc 'Continuar') {
    Start-Sleep 4
    Wait-UiContains @('Pagar','Artigo','Total') 15 | Out-Null
    Shot 'H_checkout_depois_continuar_REAL_390'
    Copy-Item "$raw\ui_last.xml" "$raw\ui_H.xml" -Force
  } else {
    Write-Host 'H VISUAL EVIDENCE NOT CAPTURED — Continuar missing'
    Shot 'H_checkout_depois_continuar_REAL_390_FAILED'
  }
} else {
  Write-Host 'G/H VISUAL EVIDENCE NOT CAPTURED — bag changed dialog not reached via live player'
  Shot 'G_saco_mudou_REAL_390_FAILED'
  Shot 'H_checkout_depois_continuar_REAL_390_FAILED'
}

Write-Host '=== I desktop proportions via wm size ==='
& $adb -s $Device shell wm size 1280x800
Start-Sleep 2
# Re-trigger bag dialog if possible: reopen buyer live + pagar
Open-BuyerLive $bag.live_id 18
Get-UiTexts | Out-Null
foreach ($label in @('Pagar','Saco','Ver saco')) {
  if (Tap-ByDesc $label) { break }
}
Start-Sleep 3
foreach ($label in @('Pagar')) { if (Tap-ByDesc $label) { break } }
Start-Sleep 3
$okI = Wait-UiContains @('O saco mudou') 12
if ($okI) {
  Shot 'I_saco_mudou_REAL_desktop'
  Copy-Item "$raw\ui_last.xml" "$raw\ui_I.xml" -Force
} else {
  Write-Host 'I VISUAL EVIDENCE NOT CAPTURED'
  Shot 'I_saco_mudou_REAL_desktop_FAILED'
}
& $adb -s $Device shell wm size reset
Start-Sleep 1

Write-Host '=== DONE shots ==='
Get-ChildItem $out\*.png | Format-Table Name, Length
