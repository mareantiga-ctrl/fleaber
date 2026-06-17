# Preenche registo com resultados da corrida 20260616_110306 + CS08 PASS.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$stamp = "20260616_110306"
$log = "tool\logs"

function Set-Test($Id, $Status, $Reason = "", $Note = "") {
  & powershell -ExecutionPolicy Bypass -File tool\update_test_battery_status.ps1 `
    -TestId $Id -Status $Status -Stamp $stamp -FailReason $Reason -UxNote $Note | Out-Null
}

Set-Test T01 PASS
Set-Test T02 PASS
Set-Test T03 PASS
Set-Test T04 PASS
Set-Test T05 PASS
Set-Test T06 PASS
Set-Test T07a PASS "" "seller harness OK na corrida (prints cs01)"
Set-Test T07b PASS "" "doc_03 stock no harness OK"
Set-Test T07c FAIL "Buyer login: launch_fleaber_login nao encontrou Entrar em 120s (v2_buyer_raffle_bag)" "emulator-5556"
Set-Test T08a PASS
Set-Test T08b FAIL "Doc #4 buyer: provavel openLink/login ou Gerir reservas timeout" "emulator-5556"
Set-Test T08c FAIL "Doc #6 v1_03: saco Pagar nao visivel ou login" "emulator-5556"
Set-Test T08d FAIL "Doc #3 seller: Maestro driver timeout porta 7001 ou conflito sessao" "emulator-5554"
Set-Test T08e SKIP "manual Stripe"
Set-Test T09 PASS
Set-Test T10 PASS
Set-Test T11 FAIL "seller harness exit=1; buyer openLink Saco da live timeout/hang" "CS01 parcial"
Set-Test T18 PASS "" "CS08 PASS apos fix navegacao sheet (corrida 080302)"
Set-Test T21 SKIP "manual Stripe"

Write-Host "Registo inicial escrito em tool/TEST_BATTERY_LIVE.md"
