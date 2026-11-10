#Requires -Version 5.1
<#
.SYNOPSIS
  Recusa deploy de Edge Functions destrutivas/staging-only para o projecto Prod.

.EXAMPLE
  powershell -File tool/deploy_edge_functions_safe.ps1 -ProjectRef bpmpkzwnrbmuqnhgdscf -Functions create-payment-intent,stripe-webhook
  powershell -File tool/deploy_edge_functions_safe.ps1 -ProjectRef fxdknzrqjenzqcvnwqqq -Functions delete-test-account -AllowDestructiveStaging
#>
param(
  [Parameter(Mandatory = $true)][string]$ProjectRef,
  [Parameter(Mandatory = $true)][string]$Functions,
  [switch]$AllowDestructiveStaging
)

$ErrorActionPreference = 'Stop'
$prodRef = 'bpmpkzwnrbmuqnhgdscf'
$stagingRef = 'fxdknzrqjenzqcvnwqqq'

$denyOnProd = @(
  'delete-test-account',
  'sec-fase2-e2e-oversell'
)

$names = @($Functions.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($names.Count -eq 0) { throw 'Lista -Functions vazia.' }

$isProd = $ProjectRef -eq $prodRef
$isStaging = $ProjectRef -eq $stagingRef

foreach ($fn in $names) {
  if ($denyOnProd -contains $fn) {
    if ($isProd) {
      throw "RECUSADO: nao fazer deploy de '$fn' para PRODUCAO ($prodRef)."
    }
    if (-not $isStaging) {
      throw "RECUSADO: '$fn' so pode ir para staging ($stagingRef), nao para '$ProjectRef'."
    }
    if (-not $AllowDestructiveStaging) {
      throw "RECUSADO: deploy de '$fn' exige -AllowDestructiveStaging (staging apenas)."
    }
  }
}

Write-Host "Deploy seguro: project=$ProjectRef functions=$($names -join ',')" -ForegroundColor Cyan
foreach ($fn in $names) {
  & npx --yes supabase functions deploy $fn --project-ref $ProjectRef --yes
  if ($LASTEXITCODE -ne 0) { throw "Deploy falhou: $fn" }
}
Write-Host 'OK' -ForegroundColor Green
