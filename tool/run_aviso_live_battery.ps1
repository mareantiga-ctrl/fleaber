# Bateria APP-218 + SEC-020 — mesma live (sem create Mux se quota cheia).
param(
  [string]$SellerDevice = "95B6HUZ9GEGQPBRG",
  [string]$BuyerDevice = "d6pnqgz5jvnnbm9x",
  [switch]$SkipInstall,
  [switch]$SkipActivate
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:PATH = "C:\src\flutter\bin;C:\Program Files\Git\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportRoot = Join-Path $root "tool\reports\battery_aviso_live_2026-08-23"
$shotDir = Join-Path $reportRoot "screenshots"
$logDir = Join-Path $reportRoot "logs"
$bdDir = Join-Path $reportRoot "bd"
New-Item -ItemType Directory -Force -Path $shotDir, $logDir, $bdDir | Out-Null

$masterLog = Join-Path $logDir "aviso_live_$stamp.log"
function Write-Log([string]$Msg) {
  $line = "[$(Get-Date -Format 'HH:mm:ss')] $Msg"
  Write-Host $line
  Add-Content -Path $masterLog -Value $line
}

function Merge-LiveEnv {
  $envFile = Join-Path $root ".maestro\.env"
  if (-not (Test-Path $envFile)) { dart run tool/maestro_prepare_live.dart 2>&1 | Out-Null }
  $liveEnv = Join-Path $bdDir "live.env"
  $existing = @{}
  Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq "" -or $line.StartsWith("#")) { return }
    $i = $line.IndexOf("=")
    if ($i -lt 1) { return }
    $existing[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1).Trim()
  }
  if (Test-Path $liveEnv) {
    Get-Content $liveEnv | ForEach-Object {
      $line = $_.Trim()
      if ($line -eq "" -or $line.StartsWith("#")) { return }
      $i = $line.IndexOf("=")
      if ($i -lt 1) { return }
      $existing[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1).Trim()
    }
  }
  $existing["MAESTRO_DEVICE_SELLER"] = $SellerDevice
  $existing["MAESTRO_DEVICE_BUYER"] = $BuyerDevice
  $existing["MAESTRO_DEVICE_DEFAULT"] = $SellerDevice
  $lines = $existing.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }
  Set-Content -Path $envFile -Value ($lines -join "`n") -Encoding UTF8
}

function Invoke-MaestroFlow([string]$Flow, [string]$LogLabel, [string]$Device, [int]$Port) {
  $stepLog = Join-Path $logDir "${LogLabel}_run.log"
  $psArgs = @(
    "-File", (Join-Path $root "tool\run_maestro_flow.ps1"),
    "-FlowPath", $Flow,
    "-Device", $Device,
    "-DriverHostPort", "$Port"
  )
  if ($SkipInstall) { $psArgs += "-SkipInstall" }
  & powershell -ExecutionPolicy Bypass @psArgs *> $stepLog
  Write-Log "$LogLabel [$Device] maestro exit=$LASTEXITCODE"
  return ($LASTEXITCODE -eq 0)
}

Write-Log "=== AVISO LIVE 218+SEC020 stamp=$stamp ==="

try {
  if (-not $SkipActivate) {
    Write-Log "Activate scheduled live (no Mux create)"
    dart run tool/aviso_live_activate.dart 2>&1 | Tee-Object -FilePath (Join-Path $logDir "activate.log")
    if ($LASTEXITCODE -ne 0) { throw "activate failed" }
  }
  Merge-LiveEnv

  Write-Log "Seller studio open"
  $okS = Invoke-MaestroFlow ".maestro/flows/aviso_218_seller_studio.yaml" "aviso218_seller" $SellerDevice 7020

  Write-Log "Buyer chat message"
  & powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\maestro_cooldown.ps1") -Device $BuyerDevice -Seconds 5
  $okB = Invoke-MaestroFlow ".maestro/flows/aviso_218_buyer_chat.yaml" "aviso218_buyer" $BuyerDevice 7021

  Write-Log "Seller chat check"
  $okS2 = Invoke-MaestroFlow ".maestro/flows/aviso_218_seller_chat_check.yaml" "aviso218_seller_check" $SellerDevice 7020

  Write-Log "SEC-020 FOMO trigger"
  dart run tool/aviso_sec020_fomo_trigger.dart 2>&1 | Tee-Object -FilePath (Join-Path $logDir "sec020_trigger.log")

  Write-Log "SEC-020 buyer UI"
  & powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\maestro_cooldown.ps1") -Device $BuyerDevice -Seconds 3
  $okF = Invoke-MaestroFlow ".maestro/flows/aviso_sec020_buyer_fomo.yaml" "sec020_buyer" $BuyerDevice 7021

  $results = @{
    "APP-218_seller_open" = $(if ($okS) { "PASS" } else { "FAIL" })
    "APP-218_buyer_msg" = $(if ($okB) { "PASS" } else { "FAIL" })
    "APP-218_seller_check" = $(if ($okS2) { "PASS" } else { "FAIL" })
    "SEC-020_buyer" = $(if ($okF) { "PASS" } else { "FAIL" })
  }
  Write-Log ("RESULTS: " + (($results.GetEnumerator() | ForEach-Object { $_.Key + "=" + $_.Value }) -join "; "))
}
finally {
  Write-Log "END LIVE + force-stop (BATATA)"
  dart run tool/aviso_live_end.dart 2>&1 | Tee-Object -FilePath (Join-Path $logDir "end_live.log")
  $adb = Join-Path $env:ANDROID_HOME "platform-tools\adb.exe"
  & $adb -s $SellerDevice shell am force-stop pt.fleaber.app 2>$null
  & $adb -s $BuyerDevice shell am force-stop pt.fleaber.app 2>$null
  Write-Log "apps force-stopped"
}

$brief = Join-Path $reportRoot "BRIEFING_LIVE.md"
@(
  "# AVISO LIVE $stamp",
  "",
  "Seller=$SellerDevice Buyer=$BuyerDevice",
  "",
  "Ver prints em screenshots/ e logs/"
) | Set-Content $brief -Encoding UTF8

$zip = Join-Path $reportRoot "audit_aviso_live_$stamp.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path @($shotDir, $logDir, $bdDir, $brief) -DestinationPath $zip -Force
Write-Log "ZIP: $zip"
