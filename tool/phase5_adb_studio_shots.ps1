param(
  [string]$Device = "JRK7AINR9DIJEQ8P",
  [string]$LiveId = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$out = Join-Path $root "14-unified-commerce-phase5-live-seller-studio\screenshots"
New-Item -ItemType Directory -Force -Path $out | Out-Null

function Shot([string]$name) {
  $remote = "/sdcard/p5_$name.png"
  $local = Join-Path $out "$name.png"
  & $adb -s $Device shell screencap -p $remote
  & $adb -s $Device pull $remote $local 2>&1 | Out-Null
  & $adb -s $Device shell rm $remote 2>&1 | Out-Null
  if (Test-Path $local) {
    Write-Host "SHOT $name ($((Get-Item $local).Length) bytes)"
  } else {
    Write-Host "FAIL $name"
  }
}

# Load live id from seed if not passed
if ([string]::IsNullOrWhiteSpace($LiveId)) {
  $seed = Get-Content (Join-Path $root "14-unified-commerce-phase5-live-seller-studio\raw\ui_seed_for_screenshots.json") -Raw | ConvertFrom-Json
  $LiveId = $seed.live_id
}

Write-Host "LiveId=$LiveId Device=$Device"

# Open seller studio / live player deep link style via flutter route
# App uses go_router paths like /fleaberLivePlayer?liveId=
& $adb -s $Device shell am start -a android.intent.action.VIEW -d "fleaber://fleaber.pt/fleaberLivePlayer?liveId=$LiveId" 2>&1 | Out-Host
Start-Sleep -Seconds 4
Shot "E_studio_open_attempt"

# Fallback: try https deep link / explicit activity
& $adb -s $Device shell am start -n pt.fleaber.app/.MainActivity 2>&1 | Out-Null
Start-Sleep -Seconds 2
# Push route via intent extra is unreliable; use Maestro for studio later.

Write-Host "Done adb helper shots"
