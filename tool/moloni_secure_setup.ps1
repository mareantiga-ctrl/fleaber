# ZIP 170-C2 — configurar Moloni sem colocar secrets no chat/git/ZIP.
# Uso:
#   powershell -ExecutionPolicy Bypass -File tool\moloni_secure_setup.ps1
# Lê Client ID / Secret / company_id via prompt local (não echo) → CredMan → Supabase Secrets.
# Depois abre o URL OAuth no browser.

param(
  [string]$ProjectRef = "bpmpkzwnrbmuqnhgdscf",
  [switch]$SkipOAuthBrowser,
  [switch]$FromCredManOnly
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public class CredManMoloni170 {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct CREDENTIAL {
    public int Flags; public int Type; public string TargetName; public string Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
    public int CredentialBlobSize; public IntPtr CredentialBlob; public int Persist;
    public int AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName;
  }
  [DllImport("advapi32", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool CredRead(string target, int type, int flags, out IntPtr cred);
  [DllImport("advapi32", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern bool CredWrite(ref CREDENTIAL userCredential, uint flags);
  [DllImport("advapi32")] public static extern bool CredFree(IntPtr cred);
  public static string Read(string target) {
    IntPtr p; if (!CredRead(target, 1, 0, out p)) return null;
    var c = (CREDENTIAL)Marshal.PtrToStructure(p, typeof(CREDENTIAL));
    byte[] b = new byte[c.CredentialBlobSize];
    Marshal.Copy(c.CredentialBlob, b, 0, c.CredentialBlobSize);
    CredFree(p); return Encoding.UTF8.GetString(b);
  }
  public static void Write(string target, string user, string secret) {
    byte[] b = Encoding.UTF8.GetBytes(secret ?? "");
    IntPtr ptr = Marshal.AllocHGlobal(b.Length);
    Marshal.Copy(b, 0, ptr, b.Length);
    var c = new CREDENTIAL();
    c.Type = 1; c.TargetName = target; c.UserName = user ?? "";
    c.CredentialBlobSize = b.Length; c.CredentialBlob = ptr; c.Persist = 2;
    if (!CredWrite(ref c, 0)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    Marshal.FreeHGlobal(ptr);
  }
}
"@

function Read-Secret([string]$label) {
  $sec = Read-Host -AsSecureString $label
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

$redirect = "https://$ProjectRef.supabase.co/functions/v1/moloni-api/callback"

if (-not $FromCredManOnly) {
  Write-Host ""
  Write-Host "=== Moloni secure setup (ZIP 170) ===" -ForegroundColor Cyan
  Write-Host "Callback a configurar na Moloni Developers:"
  Write-Host "  $redirect"
  Write-Host "Valores NAO sao gravados em ficheiros do repo nem no chat."
  Write-Host ""

  $clientId = Read-Host "MOLONI_CLIENT_ID (Developer ID)"
  $clientSecret = Read-Secret "MOLONI_CLIENT_SECRET (oculto)"
  $companyId = Read-Host "MOLONI_COMPANY_ID (pode deixar vazio e preencher apos read_companies)"

  if ([string]::IsNullOrWhiteSpace($clientId) -or [string]::IsNullOrWhiteSpace($clientSecret)) {
    throw "Client ID e Client Secret sao obrigatorios."
  }

  [CredManMoloni170]::Write("FleaberMoloniClientId", "moloni", $clientId.Trim())
  [CredManMoloni170]::Write("FleaberMoloniClientSecret", "moloni", $clientSecret.Trim())
  if (-not [string]::IsNullOrWhiteSpace($companyId)) {
    [CredManMoloni170]::Write("FleaberMoloniCompanyId", "moloni", $companyId.Trim())
  }
  Write-Host "CredMan local OK (FleaberMoloni*)."
}

$clientId = [CredManMoloni170]::Read("FleaberMoloniClientId")
$clientSecret = [CredManMoloni170]::Read("FleaberMoloniClientSecret")
$companyId = [CredManMoloni170]::Read("FleaberMoloniCompanyId")
if (-not $clientId -or -not $clientSecret) {
  throw "CredMan FleaberMoloniClientId/Secret em falta. Corra sem -FromCredManOnly."
}

$sbToken = [CredManMoloni170]::Read("Supabase CLI:supabase")
if (-not $sbToken) { throw "CredMan 'Supabase CLI:supabase' em falta." }
$env:SUPABASE_ACCESS_TOKEN = $sbToken.Trim()

$secretArgs = @(
  "MOLONI_CLIENT_ID=$clientId",
  "MOLONI_CLIENT_SECRET=$clientSecret",
  "MOLONI_REDIRECT_URI=$redirect",
  "MOLONI_MODE=readonly"
)
if ($companyId) { $secretArgs += "MOLONI_COMPANY_ID=$companyId" }

Write-Host "A definir secrets no projecto $ProjectRef (valores ocultos)..."
& npx --yes supabase@latest secrets set --project-ref $ProjectRef --yes @secretArgs
if ($LASTEXITCODE -ne 0) { throw "supabase secrets set falhou" }

Write-Host "Deploy moloni-api..."
& npx --yes supabase@latest functions deploy moloni-api --project-ref $ProjectRef --no-verify-jwt --yes
if ($LASTEXITCODE -ne 0) {
  Write-Host "Retry deploy com verify-jwt default..."
  & npx --yes supabase@latest functions deploy moloni-api --project-ref $ProjectRef --yes
}

$authUrl =
  "https://www.moloni.pt/ac/root/oauth/?response_type=code" +
  "&client_id=$([uri]::EscapeDataString($clientId))" +
  "&redirect_uri=$([uri]::EscapeDataString($redirect))"

Write-Host ""
Write-Host "Secrets + deploy OK. Modo: readonly (escritas bloqueadas)." -ForegroundColor Green
Write-Host "1) Na consola Moloni Developers, Redirect URL = exactamente:"
Write-Host "   $redirect"
Write-Host "2) Autorize OAuth (abre o browser):"
Write-Host "   $authUrl"
if (-not $SkipOAuthBrowser) {
  Start-Process $authUrl
}
Write-Host "3) Depois do callback OK, corra o teste de leitura ZIP 170."
