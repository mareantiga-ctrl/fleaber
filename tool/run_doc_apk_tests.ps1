# Testes doc live-ops-testes-batata.md #3-#7 (automacao disponivel).
param(
  [string]$Device = "emulator-5556",
  [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:PATH = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"

$results = New-Object System.Collections.Generic.List[object]
$skip = $SkipInstall.IsPresent

function Record([string]$name, [bool]$ok) {
  $r = if ($ok) { "PASS" } else { "FAIL" }
  $results.Add([pscustomobject]@{ Test = $name; Result = $r }) | Out-Null
}

Write-Host "=== V0 staging (logica #3 #4 #6 #7 BD/edge) ==="
dart run tool/live_ops_staging_check.dart
Record "V0 staging #3#4#6#7 (BD)" ($LASTEXITCODE -eq 0)

function Invoke-MaestroTimed {
  param(
    [string]$Flow,
    [string]$Device,
    [int]$Port,
    [string]$LogName
  )
  $log = Join-Path $root "tool\logs\$LogName.log"
  $inner = @(
    "-File", (Join-Path $root "tool\run_maestro_flow.ps1"),
    "-FlowPath", $Flow,
    "-Device", $Device,
    "-DriverHostPort", "$Port"
  )
  if ($skip) { $inner += "-SkipInstall" }
  & (Join-Path $root "tool\run_ps_with_timeout.ps1") -TimeoutSec 300 -LogFile $log -PsArgs $inner
  return ($LASTEXITCODE -eq 0)
}

Write-Host ""
Write-Host "=== Doc #4 APK - Cancelar saco (com reserva no saco) ==="
& powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\maestro_cooldown.ps1") -Device $Device -Seconds 5
dart run tool/maestro_prepare_live.dart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Record "Doc #4 APK Cancelar saco" (Invoke-MaestroTimed ".maestro/flows/doc_04_buyer_cancel_bag.yaml" $Device 7002 "doc04_cancel")

Write-Host ""
Write-Host "=== Preparar live + reserva (Doc #6) ==="
& powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\maestro_cooldown.ps1") -Device $Device -Seconds 5
dart run tool/maestro_prepare_live.dart
Record "prepare para Doc #6" ($LASTEXITCODE -eq 0)

Write-Host ""
Write-Host "=== Doc #6 APK parcial - Pagar (v1_03) ==="
Record "Doc #6 APK parcial Pagar" (Invoke-MaestroTimed ".maestro/flows/v1_03_buyer_bag_sheet.yaml" $Device 7002 "doc06_pagar")

Write-Host ""
Write-Host "=== Doc #3 APK - Adicionar stock (seller Maestro, UX nav) ==="
& powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\stop_maestro_stale.ps1") | Out-Null
& powershell -ExecutionPolicy Bypass -File (Join-Path $root "tool\maestro_cooldown.ps1") -Device "emulator-5554" -Seconds 10
$doc3Ok = $false
if (Invoke-MaestroTimed ".maestro/flows/open_seller_studio_nav.yaml" "emulator-5554" 7001 "doc03_nav") {
  if (Invoke-MaestroTimed ".maestro/flows/open_seller_studio_catalog.yaml" "emulator-5554" 7001 "doc03_catalog") {
    $doc3Ok = Invoke-MaestroTimed ".maestro/flows/doc_03_seller_stock_add.yaml" "emulator-5554" 7001 "doc03_stock"
  }
}
Record "Doc #3 APK Adicionar stock" $doc3Ok

$results.Add([pscustomobject]@{ Test = "Doc #7 APK Stripe EUR"; Result = "SKIP" }) | Out-Null
Write-Host "SKIP Doc #7 Stripe (browser real - telemovel USB quando necessario)."

Write-Host ""
Write-Host "=== RESUMO ==="
$results | Format-Table -AutoSize
foreach ($row in $results) {
  if ($row.Result -eq "FAIL") { exit 1 }
}
exit 0
