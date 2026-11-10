param(
  [string]$Device = "JRK7AINR9DIJEQ8P"
)

$ErrorActionPreference = "Stop"
$root = "c:\Users\Casa\Desktop\Fleaber\fleaber"
Set-Location $root
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$out = Join-Path $root "14-unified-commerce-phase5-live-seller-studio\screenshots"
New-Item -ItemType Directory -Force -Path $out | Out-Null

$envMap = @{}
Get-Content (Join-Path $root ".maestro\.env") | ForEach-Object {
  $t = $_.Trim()
  if ($t -eq "" -or $t.StartsWith("#")) { return }
  $i = $t.IndexOf("=")
  if ($i -lt 1) { return }
  $envMap[$t.Substring(0, $i).Trim()] = $t.Substring($i + 1).Trim()
}
$emailUrl = $envMap["MAESTRO_SELLER_EMAIL_URL"]
$pass = [uri]::EscapeDataString($envMap["MAESTRO_SELLER_PASSWORD"])
$base = $envMap["MAESTRO_DEEP_LINK_BASE"]
$seed = Get-Content (Join-Path $root "14-unified-commerce-phase5-live-seller-studio\raw\ui_seed_for_screenshots.json") -Raw | ConvertFrom-Json
$liveId = $seed.live_id

function Open-Deep([string]$pathAndQuery) {
  $uri = "$base$pathAndQuery"
  Write-Host "OPEN $uri"
  & $adb -s $Device shell am start -a android.intent.action.VIEW -d $uri | Out-Host
  Start-Sleep -Seconds 5
}

function Shot([string]$name) {
  $remote = "/sdcard/p5_$name.png"
  $local = Join-Path $out "$name.png"
  & $adb -s $Device shell screencap -p $remote
  & $adb -s $Device pull $remote $local | Out-Null
  & $adb -s $Device shell rm $remote | Out-Null
  if (Test-Path $local) {
    Write-Host "SHOT $name $((Get-Item $local).Length)"
  } else {
    Write-Host "FAIL $name"
  }
}

function Autologin-Next([string]$nextPath) {
  $nextEnc = [uri]::EscapeDataString($nextPath)
  Open-Deep "/maestroAutologin?email=$emailUrl&password=$pass&next=$nextEnc"
  Start-Sleep -Seconds 7
}

function Get-Dump([string]$localName) {
  $remote = "/sdcard/p5_ui.xml"
  $local = Join-Path $out $localName
  & $adb -s $Device shell uiautomator dump $remote | Out-Null
  & $adb -s $Device pull $remote $local | Out-Null
  if (Test-Path $local) {
    return Get-Content $local -Raw -ErrorAction SilentlyContinue
  }
  return ""
}

function Tap-Text([string]$xml, [string]$text) {
  $pattern = 'text="' + [regex]::Escape($text) + '"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'
  $m = [regex]::Match($xml, $pattern)
  if (-not $m.Success) { return $false }
  $cx = [int](([int]$m.Groups[1].Value + [int]$m.Groups[3].Value) / 2)
  $cy = [int](([int]$m.Groups[2].Value + [int]$m.Groups[4].Value) / 2)
  Write-Host "TAP $text @$cx,$cy"
  & $adb -s $Device shell input tap $cx $cy
  Start-Sleep -Seconds 2
  return $true
}

Write-Host "=== Phase 5 real screenshots Device=$Device live=$liveId ==="
& $adb -s $Device shell input keyevent KEYCODE_WAKEUP
& $adb -s $Device shell input keyevent 82
Start-Sleep -Seconds 1

# B — Definições
Autologin-Next "/contaDefinicoes"
Shot "B01_conta_definicoes"
& $adb -s $Device shell input swipe 540 1600 540 500 350
Start-Sleep -Seconds 1
& $adb -s $Device shell input swipe 540 1600 540 500 350
Start-Sleep -Seconds 1
Shot "B02_definicoes_scrolled"

$xml = Get-Dump "_ui_definicoes.xml"
$tapped = Tap-Text $xml "Reservas no directo"
if ($tapped) {
  Shot "B03_reservas_expanded"
  $xml = Get-Dump "_ui_definicoes2.xml"
}

$tappedCfg = Tap-Text $xml "Configurar reservas"
if (-not $tappedCfg) {
  $xml = Get-Dump "_ui_definicoes3.xml"
  $tappedCfg = Tap-Text $xml "Configurar reservas"
}

if ($tappedCfg) {
  Shot "B_policy_sheet_full"
  Shot "C_mode_pedir_autorizacao"
  $xmlP = Get-Dump "_ui_policy.xml"
  $okPay = Tap-Text $xmlP "Só o pagamento garante"
  if (-not $okPay) {
    # encoding fallback: find partial
    if ($xmlP -match 'pagamento garante[^"]*"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"') {
      $cx = [int](([int]$Matches[1] + [int]$Matches[3]) / 2)
      $cy = [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
      & $adb -s $Device shell input tap $cx $cy
      Start-Sleep -Seconds 1
    }
  }
  Shot "D_mode_so_pagamento_garante"
  $xmlP2 = Get-Dump "_ui_policy2.xml"
  if (-not (Tap-Text $xmlP2 "Cancelar")) {
    & $adb -s $Device shell input keyevent 4
  }
}

# A — gate
Write-Host "=== Gate A ==="
dart run tool/phase5_policy_gate_toggle.dart clear
Autologin-Next "/criarDirecto"
Start-Sleep -Seconds 4
Shot "A_first_live_policy_gate"
$xmlG = Get-Dump "_ui_gate.xml"
if ($xmlG -match "primeiro directo|autoriza|reservas") {
  Shot "A2_gate_confirmed"
}
dart run tool/phase5_policy_gate_toggle.dart restore
& $adb -s $Device shell input keyevent 4
Start-Sleep -Seconds 1

# Studio
Write-Host "=== Studio ==="
Autologin-Next "/maestroSellerStudio?liveId=$liveId&opsSection=queue"
Start-Sleep -Seconds 10
Shot "E_studio_pending_and_queue"
Shot "H_studio_guaranteed_row"
& $adb -s $Device shell input swipe 540 1500 540 700 350
Start-Sleep -Seconds 1
Shot "E2_studio_scrolled"

Write-Host "=== DONE ==="
Get-ChildItem $out -Filter "*.png" | Sort-Object LastWriteTime -Descending | Select-Object -First 25 Name, Length | Format-Table -AutoSize
