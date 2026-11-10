Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class CredUtf8Z155 {
  [DllImport("Advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool CredReadW(string target, int type, int flags, out IntPtr cred);
  [DllImport("Advapi32.dll", SetLastError=true)] public static extern void CredFree(IntPtr cred);
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct CREDENTIAL {
    public int Flags; public int Type; public IntPtr TargetName; public IntPtr Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten; public int CredentialBlobSize;
    public IntPtr CredentialBlob; public int Persist; public int AttributeCount; public IntPtr Attributes;
    public IntPtr TargetAlias; public IntPtr UserName;
  }
  public static string ReadUtf8(string target) {
    IntPtr p; if (!CredReadW(target, 1, 0, out p)) return "";
    try {
      var c = (CREDENTIAL)Marshal.PtrToStructure(p, typeof(CREDENTIAL));
      byte[] b = new byte[c.CredentialBlobSize];
      Marshal.Copy(c.CredentialBlob, b, 0, c.CredentialBlobSize);
      return Encoding.UTF8.GetString(b).TrimEnd((char)0).Trim();
    } finally { CredFree(p); }
  }
}
"@
$env:SUPABASE_ACCESS_TOKEN = [CredUtf8Z155]::ReadUtf8('Supabase CLI:supabase')
if (-not $env:SUPABASE_ACCESS_TOKEN) { throw "No Supabase CLI token in CredMan" }
npx --yes supabase functions deploy amazon-importer-research --project-ref bpmpkzwnrbmuqnhgdscf --yes
npx --yes supabase functions deploy amazon-importer-external-research --project-ref bpmpkzwnrbmuqnhgdscf --yes
Write-Host "DEPLOY_OK"
