#Requires -Version 5.1
<#
.SYNOPSIS
  ZIP 174 — carrega credenciais Stripe LIVE / DPD comercial do CredMan para
  Supabase Edge Secrets. NUNCA imprime valores. NUNCA liga GO.

.DESCRIPTION
  Targets CredMan (Generic):
    FleaberStripeSecretLive      → STRIPE_SECRET_KEY_LIVE (sk_live_… / rk_live_…)
    FleaberStripeWebhookLive     → STRIPE_WEBHOOK_SECRET_LIVE (whsec_…)
    FleaberDpdLiveUsername       → DPD_LIVE_USERNAME
    FleaberDpdLivePassword       → DPD_LIVE_PASSWORD
    FleaberDpdLiveClientId       → DPD_LIVE_CLIENT_ID
    FleaberDpdLiveClientSecret   → DPD_LIVE_CLIENT_SECRET

  Opcional TEST explícito (se quiseres separar do legado):
    FleaberStripeSecretTest      → STRIPE_SECRET_KEY_TEST
    FleaberStripeWebhookTest     → STRIPE_WEBHOOK_SECRET_TEST

  Depois de set: GO permanece 0 (OPS_STRIPE_LIVE_GO / OPS_DPD_COMMERCIAL_GO /
  DPD_LIVE_CREATE_ENABLED).

.EXAMPLE
  powershell -File tool/ops_env_set_real_credentials.ps1
  powershell -File tool/ops_env_set_real_credentials.ps1 -WhatIf
#>
param(
  [string]$ProjectRef = 'bpmpkzwnrbmuqnhgdscf',
  [switch]$WhatIf,
  [switch]$AllowPartial
)

$ErrorActionPreference = 'Stop'

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Cred174 {
  [DllImport("Advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool CredRead(string target, int type, int flags, out IntPtr cred);
  [DllImport("Advapi32.dll", SetLastError=true)] public static extern void CredFree(IntPtr cred);
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct CREDENTIAL {
    public int Flags; public int Type; public string TargetName; public string Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten; public int CredentialBlobSize;
    public IntPtr CredentialBlob; public int Persist; public int AttributeCount; public IntPtr Attributes;
    public string TargetAlias; public string UserName;
  }
  public static string Read(string target) {
    IntPtr p; if (!CredRead(target, 1, 0, out p)) return "";
    try {
      var c = (CREDENTIAL)Marshal.PtrToStructure(p, typeof(CREDENTIAL));
      if (c.CredentialBlob == IntPtr.Zero || c.CredentialBlobSize <= 0) return "";
      return Marshal.PtrToStringUni(c.CredentialBlob, c.CredentialBlobSize / 2) ?? "";
    } finally { CredFree(p); }
  }
}
"@

function Get-Cred([string]$Target) {
  return ([Cred174]::Read($Target)).Trim()
}

function Test-Prefix([string]$Value, [string[]]$Prefixes) {
  foreach ($p in $Prefixes) {
    if ($Value.StartsWith($p)) { return $true }
  }
  return $false
}

$map = [ordered]@{
  'FleaberStripeSecretLive'    = @{ Env='STRIPE_SECRET_KEY_LIVE'; Prefixes=@('sk_live_','rk_live_'); Required=$true }
  'FleaberStripeWebhookLive'   = @{ Env='STRIPE_WEBHOOK_SECRET_LIVE'; Prefixes=@('whsec_'); Required=$true }
  'FleaberDpdLiveUsername'     = @{ Env='DPD_LIVE_USERNAME'; Prefixes=@(); Required=$true }
  'FleaberDpdLivePassword'     = @{ Env='DPD_LIVE_PASSWORD'; Prefixes=@(); Required=$true }
  'FleaberDpdLiveClientId'     = @{ Env='DPD_LIVE_CLIENT_ID'; Prefixes=@(); Required=$true }
  'FleaberDpdLiveClientSecret' = @{ Env='DPD_LIVE_CLIENT_SECRET'; Prefixes=@(); Required=$true }
  'FleaberStripeSecretTest'    = @{ Env='STRIPE_SECRET_KEY_TEST'; Prefixes=@('sk_test_','rk_test_'); Required=$false }
  'FleaberStripeWebhookTest'   = @{ Env='STRIPE_WEBHOOK_SECRET_TEST'; Prefixes=@('whsec_'); Required=$false }
}

$pairs = @()
$missing = @()
$invalid = @()

foreach ($target in $map.Keys) {
  $meta = $map[$target]
  $val = Get-Cred $target
  if ([string]::IsNullOrWhiteSpace($val)) {
    if ($meta.Required) { $missing += $target }
    Write-Host ("ABSENT  {0} -> {1}" -f $target, $meta.Env)
    continue
  }
  if ($meta.Prefixes.Count -gt 0 -and -not (Test-Prefix $val $meta.Prefixes)) {
    $invalid += ("{0} (expected prefix {1})" -f $target, ($meta.Prefixes -join '|'))
    Write-Host ("INVALID {0} -> {1} (prefix)" -f $target, $meta.Env) -ForegroundColor Yellow
    continue
  }
  $fp = if ($val.Length -ge 8) { $val.Substring(0, 8) + '…' } else { '(short)' }
  Write-Host ("OK      {0} -> {1} fingerprint={2} len={3}" -f $target, $meta.Env, $fp, $val.Length)
  $pairs += ('{0}={1}' -f $meta.Env, $val)
}

# GO always off
$pairs += 'OPS_STRIPE_LIVE_GO=0'
$pairs += 'OPS_DPD_COMMERCIAL_GO=0'
$pairs += 'DPD_LIVE_CREATE_ENABLED=0'
Write-Host 'OK      GO flags forced OFF (0)'

if ($invalid.Count -gt 0) {
  throw ("Prefixos inválidos: {0}" -f ($invalid -join '; '))
}
if ($missing.Count -gt 0 -and -not $AllowPartial) {
  Write-Host ''
  Write-Host 'Credenciais LIVE/COMERCIAL em falta no CredMan:' -ForegroundColor Yellow
  $missing | ForEach-Object { Write-Host ("  - {0}" -f $_) }
  Write-Host ''
  Write-Host 'Como guardar (PowerShell, sem eco no histórico se usares prompt):'
  Write-Host '  cmdkey /generic:FleaberStripeSecretLive /user:fleaber /pass:"sk_live_…"'
  Write-Host '  cmdkey /generic:FleaberStripeWebhookLive /user:fleaber /pass:"whsec_…"'
  Write-Host '  cmdkey /generic:FleaberDpdLiveUsername /user:fleaber /pass:"…"'
  Write-Host '  cmdkey /generic:FleaberDpdLivePassword /user:fleaber /pass:"…"'
  Write-Host '  cmdkey /generic:FleaberDpdLiveClientId /user:fleaber /pass:"…"'
  Write-Host '  cmdkey /generic:FleaberDpdLiveClientSecret /user:fleaber /pass:"…"'
  Write-Host 'Depois: powershell -File tool/ops_env_set_real_credentials.ps1'
  exit 2
}

if ($WhatIf) {
  Write-Host ("WhatIf: iria definir {0} secrets no project {1} (valores omitidos)." -f $pairs.Count, $ProjectRef)
  exit 0
}

# Pass via env file temp with restrictive ACL — avoid command-line leakage in process list
$tmp = Join-Path $env:TEMP ("fleaber_ops174_{0}.env" -f [guid]::NewGuid().ToString('N'))
try {
  $utf8 = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($tmp, ($pairs -join "`n") + "`n", $utf8)
  icacls $tmp /inheritance:r | Out-Null
  icacls $tmp /grant:r "${env:USERNAME}:F" | Out-Null

  # supabase secrets set --env-file
  & npx --yes supabase@latest secrets set --project-ref $ProjectRef --env-file $tmp --yes
  if ($LASTEXITCODE -ne 0) { throw "supabase secrets set failed: $LASTEXITCODE" }
  Write-Host 'SECRETS_SET_OK (GO=0)' -ForegroundColor Green
}
finally {
  if (Test-Path $tmp) {
    # overwrite then delete
    $zeros = New-Object byte[] 4096
    [System.IO.File]::WriteAllBytes($tmp, $zeros)
    Remove-Item -Force $tmp -ErrorAction SilentlyContinue
  }
}
