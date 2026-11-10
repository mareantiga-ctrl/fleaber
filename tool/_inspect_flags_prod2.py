#!/usr/bin/env python3
import subprocess
import sys

PS = open(__file__.replace("_inspect_flags_prod2.py", "_inspect_flags_prod.py"), encoding="utf-8").read()
# reuse password fetch from sibling by importing logic inline
PS = r"""
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CredManInspect2 {
  [DllImport("Advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool CredRead(string target, int type, int flags, out IntPtr cred);
  [DllImport("Advapi32.dll", SetLastError=true)]
  public static extern void CredFree(IntPtr cred);
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
      return Marshal.PtrToStringUni(c.CredentialBlob, c.CredentialBlobSize / 2);
    } finally { CredFree(p); }
  }
}
"@
[Console]::Out.Write([CredManInspect2]::Read('FleaberProdPostgres'))
"""
pw = subprocess.check_output(["powershell", "-NoProfile", "-Command", PS], text=True).strip()
try:
    import psycopg2
except ImportError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "psycopg2-binary", "-q"])
    import psycopg2

conn = psycopg2.connect(
    host="aws-1-eu-west-1.pooler.supabase.com",
    port=5432,
    dbname="postgres",
    user="postgres.bpmpkzwnrbmuqnhgdscf",
    password=pw,
    sslmode="require",
)
cur = conn.cursor()
cur.execute(
    """
    select conname, pg_get_constraintdef(oid)
    from pg_constraint
    where conrelid = 'public.fleaber_feature_flags'::regclass
    """
)
print("CONS", cur.fetchall())
cur.execute(
    """
    select indexdef from pg_indexes
    where tablename='fleaber_feature_flags' and schemaname='public'
    """
)
print("IDX", cur.fetchall())
for name in (
    "batata_flag_enabled",
    "batata_is_admin",
    "batata_dpd_weight_band",
    "batata_emit_user_notification",
    "batata_notify_is_service_role",
):
    cur.execute(
        "select oid::regprocedure::text from pg_proc where pronamespace='public'::regnamespace and proname=%s",
        (name,),
    )
    print(name, cur.fetchall())
conn.close()
