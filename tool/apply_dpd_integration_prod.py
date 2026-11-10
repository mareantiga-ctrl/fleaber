#!/usr/bin/env python3
"""Apply DPD integration migration to Fleaber Prod (schema only — no Live DPD)."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL_PATH = ROOT / (
    "supabase/migrations/20261102120000_dpd_integration_fase1_batata.sql"
)

PS_GET_PW = r"""
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CredManDpdMig {
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
$pw = [CredManDpdMig]::Read('FleaberProdPostgres')
if (-not $pw) { $pw = [CredManDpdMig]::Read('Supabase CLI:supabase') }
[Console]::Out.Write($pw)
"""


def main() -> int:
    sql = SQL_PATH.read_text(encoding="utf-8")
    pw = subprocess.check_output(
        ["powershell", "-NoProfile", "-Command", PS_GET_PW], text=True
    ).strip()
    if not pw:
        print("no CredMan password")
        return 2
    try:
        import psycopg2
    except ImportError:
        subprocess.check_call(
            [sys.executable, "-m", "pip", "install", "psycopg2-binary", "-q"]
        )
        import psycopg2

    conn = psycopg2.connect(
        host="aws-1-eu-west-1.pooler.supabase.com",
        port=5432,
        dbname="postgres",
        user="postgres.bpmpkzwnrbmuqnhgdscf",
        password=pw,
        sslmode="require",
        connect_timeout=25,
    )
    conn.autocommit = False
    cur = conn.cursor()
    cur.execute(sql)
    conn.commit()
    cur.execute(
        """
        select
          (select count(*) from information_schema.columns
             where table_name='orders' and column_name='dpd_service'),
          (select to_regprocedure(
             'public.batata_set_order_delivery_pickup(uuid,text,text,text,text,text,text)'
           ) is not null)
        """
    )
    print("smoke:", cur.fetchone())
    cur.close()
    conn.close()
    print("OK dpd migration applied (create Live NOT enabled)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
