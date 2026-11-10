#!/usr/bin/env python3
"""Run ZIP 128 smoke SQL on Fleaber Prod (rollback at end of script)."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL_PATH = ROOT / "tool/sql/zip128_financial_protection_smoke.sql"

PS_GET_PW = r"""
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CredManSmoke128 {
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
$pw = [CredManSmoke128]::Read('FleaberProdPostgres')
if (-not $pw) { $pw = [CredManSmoke128]::Read('Supabase CLI:supabase') }
[Console]::Out.Write($pw)
"""


def main() -> int:
    sql = SQL_PATH.read_text(encoding="utf-8")
    pw = subprocess.check_output(
        ["powershell", "-NoProfile", "-Command", PS_GET_PW],
        text=True,
    ).strip()
    if not pw:
        print("no CredMan password")
        return 2
    try:
        import psycopg2
        from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
    except ImportError:
        subprocess.check_call(
            [sys.executable, "-m", "pip", "install", "psycopg2-binary", "-q"]
        )
        import psycopg2
        from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT

    conn = psycopg2.connect(
        host="aws-1-eu-west-1.pooler.supabase.com",
        port=5432,
        dbname="postgres",
        user="postgres.bpmpkzwnrbmuqnhgdscf",
        password=pw,
        sslmode="require",
        connect_timeout=25,
    )
    conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
    cur = conn.cursor()
    try:
        cur.execute(sql)
        print("SMOKE_OK")
        return 0
    except Exception as e:
        print("SMOKE_FAIL", e)
        return 3
    finally:
        cur.close()
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
