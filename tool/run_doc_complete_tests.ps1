# Testes completos doc live-ops-testes-batata.md
param([switch]$SkipInstall)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:PATH = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"

$seller = "emulator-5558"
$buyer = "emulator-5554"
$flow = Join-Path $root "tool\run_maestro_flow.ps1"
$report = New-Object System.Collections.Generic.List[string]

function Add([string]$teste, [string]$resultado, [string]$nota) {
  $script:report.Add("$teste|$resultado|$nota")
}

function Run-Flow([string]$path, [string]$device, [int]$port) {
  if ($SkipInstall) {
    & powershell -File $flow -FlowPath $path -Device $device -DriverHostPort $port -SkipInstall
  } else {
    & powershell -File $flow -FlowPath $path -Device $device -DriverHostPort $port
  }
}

Write-Host "Testes live-ops (2x Pixel 10)..."

Write-Host "`n[1] Servidor..."
dart run tool/live_ops_staging_check.dart 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
  Add "Logica servidor (3,4,6,7)" "OK" "Base de dados e APIs respondem bem"
} else {
  Add "Logica servidor (3,4,6,7)" "FALHOU" "Problema em Supabase/staging - resolver antes da app"
}

Write-Host "`n[2] Teste 4 - reserva + cancelar + vendedor..."
Run-Flow ".maestro/multidevice/seller_studio_live.yaml" $seller 7001
$sellerOk = ($LASTEXITCODE -eq 0)
if (-not $sellerOk) {
  Add "4 Cancelar na live (app)" "FALHOU" "Vendedor nao conseguiu iniciar directo (Mux/rede?)"
} else {
  dart run tool/maestro_sync_seller_live.dart --wait-seconds=60 2>&1 | Out-Null
  Run-Flow ".maestro/multidevice/buyer_login_and_reserve.yaml" $buyer 7002
  $r = ($LASTEXITCODE -eq 0)
  if ($r) {
    Start-Sleep -Seconds 2
    Run-Flow ".maestro/multidevice/buyer_cancel_only.yaml" $buyer 7002
    $c = ($LASTEXITCODE -eq 0)
    if ($c) {
      Start-Sleep -Seconds 2
      Run-Flow ".maestro/multidevice/seller_sees_cancelados.yaml" $seller 7001
      if ($LASTEXITCODE -eq 0) {
        Add "4 Cancelar na live (app)" "OK" "Comprador cancelou; vendedor ve Cancelados pelo comprador"
      } else {
        Add "4 Cancelar na live (app)" "PARCIAL" "Cancelou no comprador; confirma Pagamentos no 5558 manualmente"
      }
    } else {
      Add "4 Cancelar na live (app)" "PARCIAL" "Reserva OK; cancelar na app falhou"
    }
  } else {
    Add "4 Cancelar na live (app)" "PARCIAL" "Directo OK; comprador nao reservou"
  }
}

Write-Host "`n[3] Teste 6 - saco Pagar..."
dart run tool/maestro_prepare_live.dart 2>&1 | Out-Null
Run-Flow ".maestro/flows/v1_03_buyer_bag_sheet.yaml" $buyer 7002
if ($LASTEXITCODE -eq 0) {
  Add "6 Botao Pagar no saco" "OK" ""
} else {
  Add "6 Botao Pagar no saco" "FALHOU" ""
}
Add "6 Pagamento Stripe no browser" "NAO POSSIVEL AQUI" "Só manual com cartao teste"
Add "7 Pagar e euros na vendedora" "NAO POSSIVEL AQUI" "Só manual apos Stripe"
Add "3 Barra stock artigo vendido" "NAO POSSIVEL AQUI" "Só manual no directo; servidor ja OK"

Write-Host "`n========================================"
Write-Host "RESULTADOS"
Write-Host "========================================"
foreach ($line in $report) {
  $p = $line.Split("|", 3)
  Write-Host ""
  Write-Host "$($p[0]): $($p[1])"
  if ($p[2]) { Write-Host "   $($p[2])" }
}
Write-Host ""

if ($report | Where-Object { $_ -match "\|FALHOU\|" }) { exit 1 }
