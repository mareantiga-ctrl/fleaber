# List credential target names only (no secrets)
$sig = @'
[DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
public static extern bool CredEnumerate(string filter, int flag, out int count, out IntPtr pCredentials);
[DllImport("advapi32.dll")] public static extern bool CredFree(IntPtr buffer);
[StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
public struct CREDENTIAL {
  public int Flags; public int Type; public IntPtr TargetName; public IntPtr Comment;
  public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten; public int CredentialBlobSize;
  public IntPtr CredentialBlob; public int Persist; public int AttributeCount; public IntPtr Attributes;
  public IntPtr TargetAlias; public IntPtr UserName;
}
'@
Add-Type -MemberDefinition $sig -Name CredEnum -Namespace Win32 -ErrorAction SilentlyContinue
$count = 0; $ptr = [IntPtr]::Zero
# CredEnumerate with null filter may need CRED_ENUMERATE_ALL_CREDENTIALS = 0x1
$ok = [Win32.CredEnum]::CredEnumerate([NullString]::Value, 1, [ref]$count, [ref]$ptr)
if (-not $ok) {
  Write-Host "enumerate_failed err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
  # fallback: known targets probe
  $known = @(
    'Supabase CLI:supabase',
    'Supabase Access Token',
    'FleaberSupabaseAccessToken',
    'supabase',
    'git:https://supabase.com'
  )
  Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text;
public class CredProbe {
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
  public static string Len(string target) {
    IntPtr n; if (!CredRead(target,1,0,out n)) return "missing";
    var c=(CREDENTIAL)Marshal.PtrToStructure(n,typeof(CREDENTIAL));
    int len=c.CredentialBlobSize; CredFree(n); return "len="+len;
  }
}
'@
  foreach ($t in $known) { Write-Host ("{0} => {1}" -f $t, [CredProbe]::Len($t)) }
  exit 0
}
Write-Host "count=$count"
