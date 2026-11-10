#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import sys

PS = r"""
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CredManSmoke1199 {
  [DllImport("Advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool CredRead(string target, int type, int flags, out IntPtr cred);
  [DllImport("Advapi32.dll", SetLastError=true)]
  public static extern bool CredFree(IntPtr cred);
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
$pw = [CredManSmoke1199]::Read('FleaberProdPostgres')
if (-not $pw) { $pw = [CredManSmoke1199]::Read('Supabase CLI:supabase') }
[Console]::Out.Write($pw)
"""


def main() -> int:
    pw = subprocess.check_output(
        ["powershell", "-NoProfile", "-Command", PS], text=True
    ).strip()
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
        select column_name from information_schema.columns
        where table_schema='public' and table_name='seller_trade_profiles'
          and column_name like 'leave%'
        order by 1
        """
    )
    print("cols", cur.fetchall())
    cur.execute(
        """
        select proname from pg_proc
        where proname in (
          'seller_trade_request_leave',
          'seller_trade_admin_decide_leave',
          'seller_trade_public_info'
        )
        order by 1
        """
    )
    print("fns", cur.fetchall())
    cur.execute(
        """
        select contact_email is null, contact_phone is null, count(*)
        from seller_trade_public_info(
          array(
            select user_id from seller_trade_profiles
            where verification_status='verified' limit 5
          )
        )
        group by 1,2
        """
    )
    print("public_contacts_null", cur.fetchall())
    conn.close()
    print("smoke ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
