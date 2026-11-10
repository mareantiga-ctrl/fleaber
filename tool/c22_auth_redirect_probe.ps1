Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text;
public class CredMan {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct CREDENTIAL { public int Flags; public int Type; public string TargetName; public string Comment; public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten; public int CredentialBlobSize; public IntPtr CredentialBlob; public int Persist; public int AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName; }
  [DllImport("advapi32", SetLastError=true, CharSet=CharSet.Unicode)] public static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);
  [DllImport("advapi32")] public static extern bool CredFree(IntPtr cred);
  public static string Read(string target) { IntPtr nCred; if(!CredRead(target,1,0,out nCred)) return null; var cred=(CREDENTIAL)Marshal.PtrToStructure(nCred,typeof(CREDENTIAL)); byte[] bytes=new byte[cred.CredentialBlobSize]; Marshal.Copy(cred.CredentialBlob,bytes,0,cred.CredentialBlobSize); CredFree(nCred); return Encoding.UTF8.GetString(bytes);} }
'@
$env:SUPABASE_ACCESS_TOKEN = ([CredMan]::Read('Supabase CLI:supabase')).Trim()
Set-Location $PSScriptRoot\..
dart run tool/c22_auth_redirect_probe.dart
