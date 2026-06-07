# Testes doc live-ops-testes-batata.md #3-#7 (automacao disponivel).
# Uso: powershell -File tool/run_doc_apk_tests.ps1 -Device emulator-5558 -SkipInstall
param(
  [string]$Device = "emulator-5558",
  [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:PATH = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"

$flowScript = Join-Path $root "tool\run_maestro_flow.ps1"
$results = New-Object System.Collections.Generic.List[object]

function Record([string]$name, [bool]$ok) {
  $r = if ($ok) { "PASS" } else { "FAIL" }
  $results.Add([pscustomobject]@{ Test = $name; Result = $r }) | Out-Null
}

Write-Host "=== V0 staging (logica #3 #4 #6 #7 BD/edge) ==="
dart run tool/live_ops_staging_check.dart
Record "V0 staging #3#4#6#7 (BD)" ($LASTEXITCODE -eq 0)

Write-Host ""
Write-Host "=== Preparar live + reserva ==="
dart run tool/maestro_prepare_live.dart
Record "prepare live + reserva" ($LASTEXITCODE -eq 0)

$skip = $SkipInstall.IsPresent

Write-Host ""
Write-Host "=== Doc #6 APK parcial - Pagar (v1_03) ==="
if ($skip) {
  & powershell -ExecutionPolicy Bypass -File $flowScript -FlowPath ".maestro/flows/v1_03_buyer_bag_sheet.yaml" -Device $Device -DriverHostPort 7003 -SkipInstall
} else {
  & powershell -ExecutionPolicy Bypass -File $flowScript -FlowPath ".maestro/flows/v1_03_buyer_bag_sheet.yaml" -Device $Device -DriverHostPort 7003
}
Record "Doc #6 APK parcial Pagar" ($LASTEXITCODE -eq 0)

Write-Host ""
Write-Host "=== Re-preparar live ==="
dart run tool/maestro_prepare_live.dart
Record "prepare 2a vez" ($LASTEXITCODE -eq 0)

Write-Host ""
Write-Host "=== Doc #4 APK - Cancelar saco ==="
if ($skip) {
  & powershell -ExecutionPolicy Bypass -File $flowScript -FlowPath ".maestro/flows/doc_04_buyer_cancel_bag.yaml" -Device $Device -DriverHostPort 7003 -SkipInstall
} else {
  & powershell -ExecutionPolicy Bypass -File $flowScript -FlowPath ".maestro/flows/doc_04_buyer_cancel_bag.yaml" -Device $Device -DriverHostPort 7003
}
Record "Doc #4 APK Cancelar saco" ($LASTEXITCODE -eq 0)

$results.Add([pscustomobject]@{ Test = "Doc #3 APK stock barra"; Result = "SKIP" }) | Out-Null
$results.Add([pscustomobject]@{ Test = "Doc #7 APK Stripe EUR"; Result = "SKIP" }) | Out-Null
Write-Host "SKIP Doc #3 e #7 UI completa (sem Maestro Stripe/stock bar)."

Write-Host ""
Write-Host "=== RESUMO ==="
$results | Format-Table -AutoSize
foreach ($row in $results) {
  if ($row.Result -eq "FAIL") { exit 1 }
}
exit 0
