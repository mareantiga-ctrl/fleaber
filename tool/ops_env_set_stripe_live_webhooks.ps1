#Requires -Version 5.1
<#
.SYNOPSIS
  ZIP 174 — instala só Stripe LIVE (sk + 2 whsec) a partir do CredMan.
  NUNCA imprime valores. NUNCA liga OPS_STRIPE_LIVE_GO. Não mexe em TEST/DPD.

CredMan:
  FleaberStripeSecretLive           → STRIPE_SECRET_KEY_LIVE
  FleaberStripeWebhookLive          → STRIPE_WEBHOOK_SECRET_LIVE        (Your account)
  FleaberStripeWebhookLiveConnect   → STRIPE_WEBHOOK_SECRET_LIVE_CONNECT (Connected)

.EXAMPLE
  powershell -File tool/ops_env_set_stripe_live_webhooks.ps1
#>
param(
  [string]$ProjectRef = 'bpmpkzwnrbmuqnhgdscf',
  [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

Add-Type @"
using System; using System.Runtime.InteropServices;
public class Cred174s {
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

function Get-Cred([string]$Target) { return ([Cred174s]::Read($Target)).Trim() }

$map = [ordered]@{
  'FleaberStripeSecretLive'         = @{ Env='STRIPE_SECRET_KEY_LIVE'; Prefix=@('sk_live_','rk_live_') }
  'FleaberStripeWebhookLive'        = @{ Env='STRIPE_WEBHOOK_SECRET_LIVE'; Prefix=@('whsec_') }
  'FleaberStripeWebhookLiveConnect' = @{ Env='STRIPE_WEBHOOK_SECRET_LIVE_CONNECT'; Prefix=@('whsec_') }
}

$pairs = @()
$missing = @()
foreach ($t in $map.Keys) {
  $m = $map[$t]
  $v = Get-Cred $t
  if ([string]::IsNullOrWhiteSpace($v)) {
    $missing += $t
    Write-Host ("ABSENT  {0} -> {1}" -f $t, $m.Env)
    continue
  }
  $okPrefix = $false
  foreach ($p in $m.Prefix) { if ($v.StartsWith($p)) { $okPrefix = $true; break } }
  if (-not $okPrefix) { throw ("INVALID_PREFIX {0}" -f $t) }
  Write-Host ("OK      {0} -> {1} prefix={2} len={3}" -f $t, $m.Env, $v.Substring(0,8), $v.Length)
  $pairs += ('{0}={1}' -f $m.Env, $v)
}
$pairs += 'OPS_STRIPE_LIVE_GO=0'
Write-Host 'OK      OPS_STRIPE_LIVE_GO=0'

if ($missing.Count -gt 0) {
  Write-Host 'Falta no CredMan:' -ForegroundColor Yellow
  $missing | ForEach-Object { Write-Host ("  {0}" -f $_) }
  exit 2
}

if ($WhatIf) {
  Write-Host ("WhatIf: set {0} secrets on {1}" -f $pairs.Count, $ProjectRef)
  exit 0
}

$tmp = Join-Path $env:TEMP ("fleaber_stripe_live_{0}.env" -f [guid]::NewGuid().ToString('N'))
try {
  [System.IO.File]::WriteAllText($tmp, (($pairs -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding $false))
  icacls $tmp /inheritance:r | Out-Null
  icacls $tmp /grant:r "${env:USERNAME}:F" | Out-Null
  & npx --yes supabase@latest secrets set --project-ref $ProjectRef --env-file $tmp --yes
  if ($LASTEXITCODE -ne 0) { throw "secrets set failed" }
  Write-Host 'STRIPE_LIVE_SECRETS_SET_OK GO=0' -ForegroundColor Green
}
finally {
  if (Test-Path $tmp) {
    [System.IO.File]::WriteAllBytes($tmp, (New-Object byte[] 4096))
    Remove-Item -Force $tmp -ErrorAction SilentlyContinue
  }
}
