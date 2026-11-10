$ErrorActionPreference = 'Stop'
Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text;
public class CredManMailUtf8 {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct CREDENTIAL {
    public int Flags; public int Type; public string TargetName; public string Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten; public int CredentialBlobSize;
    public IntPtr CredentialBlob; public int Persist; public int AttributeCount; public IntPtr Attributes;
    public string TargetAlias; public string UserName;
  }
  [DllImport("advapi32", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);
  [DllImport("advapi32")] public static extern bool CredFree(IntPtr cred);
  public static string Read(string target) {
    IntPtr nCred;
    if (!CredRead(target, 1, 0, out nCred)) return null;
    var cred = (CREDENTIAL)Marshal.PtrToStructure(nCred, typeof(CREDENTIAL));
    byte[] bytes = new byte[cred.CredentialBlobSize];
    Marshal.Copy(cred.CredentialBlob, bytes, 0, cred.CredentialBlobSize);
    CredFree(nCred);
    return Encoding.UTF8.GetString(bytes);
  }
}
'@
$token = ([CredManMailUtf8]::Read('Supabase CLI:supabase')).Trim()
if (-not $token) { Write-Host 'NO_TOKEN'; exit 2 }
Write-Host ("token_len={0} jwt={1}" -f $token.Length, ($token.StartsWith('eyJ')))
if (-not $token.StartsWith('eyJ')) { Write-Host 'TOKEN_NOT_JWT'; exit 4 }
$headers = @{ Authorization = ("Bearer {0}" -f $token); Accept = 'application/json' }
$r = Invoke-RestMethod -Uri 'https://api.supabase.com/v1/projects/bpmpkzwnrbmuqnhgdscf/config/auth' -Headers $headers
$out = [ordered]@{}
$tplDir = 'tool/reports/ponto7_email_audit_20261030/prod_live_templates'
New-Item -ItemType Directory -Force -Path $tplDir | Out-Null
foreach ($p in $r.PSObject.Properties) {
  $k = $p.Name; $lk = $k.ToLower(); $v = $p.Value
  if ($lk -notmatch 'mail|smtp|subject|sender|template|autoconfirm|confirm|recover|invite|magic|otp|rate') { continue }
  if ($lk -match 'pass|secret|key') {
    $out[$k] = if ($v) { '(set)' } else { '(empty)' }
    continue
  }
  if (($v -is [string]) -and $v.Length -gt 180 -and ($lk -match 'content|body|html|template')) {
    $safe = ($k -replace '[^a-zA-Z0-9_]', '_')
    Set-Content -Path "$tplDir/$safe.html" -Value $v -Encoding UTF8
    $out[$k] = "(saved len=$($v.Length) file=$safe.html)"
  } else {
    $out[$k] = $v
  }
}
($out | ConvertTo-Json -Depth 6) | Set-Content -Path 'tool/reports/ponto7_email_audit_20261030/prod_auth_mailer_config.json' -Encoding UTF8
$out.GetEnumerator() | ForEach-Object { Write-Host ("{0}={1}" -f $_.Key, $_.Value) }
