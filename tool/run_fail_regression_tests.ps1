# APP-065 / APP-095 — regressão automatizada (lógica + unit tests)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host '=== FAIL regression: APP-065 + APP-095 + APP-200 allow-list ==='
flutter test `
  test/bundle_order_status_util_test.dart `
  test/reservation_reminder_timing_test.dart `
  test/live_catalog_sync_allowlist_test.dart

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host 'PASS — testes unitários (065/095/200 lógica)'
