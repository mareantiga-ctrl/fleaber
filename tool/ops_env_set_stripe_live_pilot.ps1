#Requires -Version 5.1
<#
.SYNOPSIS
  ZIP 181 — activa o piloto Stripe LIVE restrito (sem OPS_STRIPE_LIVE_GO=1).

  - OPS_STRIPE_LIVE_PILOT_ENABLED=1
  - OPS_STRIPE_LIVE_PILOT_MONEY_GO=0  (STOP dinheiro até confirmação)
  - Allowlists seller/buyer (UUIDs)
  - Teto em cêntimos (default 500 = 5,00 €)

.EXAMPLE
  powershell -File tool/ops_env_set_stripe_live_pilot.ps1 -SellerId '<uuid>' -BuyerId '<uuid>'
#>
param(
  [string]$ProjectRef = 'bpmpkzwnrbmuqnhgdscf',
  [Parameter(Mandatory = $true)][string]$SellerId,
  [Parameter(Mandatory = $true)][string]$BuyerId,
  [int]$MaxTotalCents = 500,
  [switch]$MoneyGo,
  [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$uuid = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
if ($SellerId -notmatch $uuid) { throw "SellerId inválido" }
if ($BuyerId -notmatch $uuid) { throw "BuyerId inválido" }
if ($MaxTotalCents -lt 1 -or $MaxTotalCents -gt 5000) {
  throw "MaxTotalCents fora do intervalo seguro (1..5000)"
}

$money = if ($MoneyGo) { '1' } else { '0' }
$pairs = @(
  'OPS_STRIPE_LIVE_GO=0'
  'OPS_STRIPE_LIVE_PILOT_ENABLED=1'
  ("OPS_STRIPE_LIVE_PILOT_MONEY_GO={0}" -f $money)
  ("OPS_STRIPE_LIVE_PILOT_SELLER_IDS={0}" -f $SellerId.Trim().ToLower())
  ("OPS_STRIPE_LIVE_PILOT_BUYER_IDS={0}" -f $BuyerId.Trim().ToLower())
  ("OPS_STRIPE_LIVE_PILOT_MAX_TOTAL_CENTS={0}" -f $MaxTotalCents)
)

Write-Host 'OPS_STRIPE_LIVE_GO=0 (global off)'
Write-Host 'OPS_STRIPE_LIVE_PILOT_ENABLED=1'
Write-Host ("OPS_STRIPE_LIVE_PILOT_MONEY_GO={0}" -f $money)
Write-Host ("SELLER allowlist set (len={0})" -f $SellerId.Length)
Write-Host ("BUYER allowlist set (len={0})" -f $BuyerId.Length)
Write-Host ("MAX_TOTAL_CENTS={0}" -f $MaxTotalCents)

if ($WhatIf) {
  Write-Host ("WhatIf: set {0} secrets on {1}" -f $pairs.Count, $ProjectRef)
  exit 0
}

$tmp = Join-Path $env:TEMP ("fleaber_stripe_pilot_{0}.env" -f [guid]::NewGuid().ToString('N'))
try {
  [System.IO.File]::WriteAllText(
    $tmp,
    (($pairs -join "`n") + "`n"),
    (New-Object System.Text.UTF8Encoding $false)
  )
  icacls $tmp /inheritance:r | Out-Null
  icacls $tmp /grant:r "${env:USERNAME}:F" | Out-Null
  & npx --yes supabase@latest secrets set --project-ref $ProjectRef --env-file $tmp --yes
  if ($LASTEXITCODE -ne 0) { throw 'secrets set failed' }
  Write-Host 'STRIPE_LIVE_PILOT_SECRETS_OK GO=0 MONEY_GO=' $money -ForegroundColor Green
}
finally {
  if (Test-Path $tmp) {
    [System.IO.File]::WriteAllBytes($tmp, (New-Object byte[] 4096))
    Remove-Item -Force $tmp -ErrorAction SilentlyContinue
  }
}
