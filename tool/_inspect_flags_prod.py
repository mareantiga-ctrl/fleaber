#!/usr/bin/env python3
import subprocess
import sys

PS = r"""
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CredManInspect {
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
[Console]::Out.Write([CredManInspect]::Read('FleaberProdPostgres'))
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
    select column_name, data_type
    from information_schema.columns
    where table_schema='public' and table_name='fleaber_feature_flags'
    order by ordinal_position
    """
)
print("COLS", cur.fetchall())
cur.execute("select key, enabled from public.fleaber_feature_flags order by key")
print("ROWS", cur.fetchall())
cur.execute(
    """
    select column_name from information_schema.columns
    where table_schema='public' and table_name='orders'
      and (column_name like '%weight%' or column_name like 'ship_%'
           or column_name like 'shipping_delta%' or column_name like 'shipping_modality%'
           or column_name like 'shipping_cents%')
    order by 1
    """
)
print("ORDER_COLS", [r[0] for r in cur.fetchall()])
conn.close()
