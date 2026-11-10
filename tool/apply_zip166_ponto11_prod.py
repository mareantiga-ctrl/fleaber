#!/usr/bin/env python3
"""Apply ZIP 166 Ponto 11 migration to Fleaber Prod (bpmp…)."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL_PATH = ROOT / (
    "supabase/migrations/"
    "20261106090000_ponto11_wallet_connect_notify_batata.sql"
)
SMOKE_PATH = ROOT / "tool/sql/zip166_ponto11_wallet_smoke.sql"

PS_GET_PW = r"""
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CredManApply166 {
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
$pw = [CredManApply166]::Read('FleaberProdPostgres')
if (-not $pw) { $pw = [CredManApply166]::Read('Supabase CLI:supabase') }
[Console]::Out.Write($pw)
"""


def connect(pw: str):
    import psycopg2

    hosts = [
        ("aws-1-eu-west-1.pooler.supabase.com", 5432),
        ("aws-0-eu-west-1.pooler.supabase.com", 6543),
    ]
    last = None
    for host, port in hosts:
        try:
            conn = psycopg2.connect(
                host=host,
                port=port,
                dbname="postgres",
                user="postgres.bpmpkzwnrbmuqnhgdscf",
                password=pw,
                sslmode="require",
                connect_timeout=25,
            )
            conn.autocommit = True
            return conn
        except Exception as e:  # noqa: BLE001
            last = e
    raise RuntimeError(last)


def main() -> int:
    sql = SQL_PATH.read_text(encoding="utf-8")
    smoke = SMOKE_PATH.read_text(encoding="utf-8")
    if not sql.strip():
        print("empty sql")
        return 1
    pw = subprocess.check_output(
        ["powershell", "-NoProfile", "-Command", PS_GET_PW],
        text=True,
    ).strip()
    if not pw:
        print("no CredMan password")
        return 2

    try:
        import psycopg2  # noqa: F401
    except ImportError:
        subprocess.check_call(
            [sys.executable, "-m", "pip", "install", "psycopg2-binary", "-q"]
        )

    conn = connect(pw)
    try:
        with conn.cursor() as cur:
            print("APPLY", SQL_PATH.name)
            cur.execute(sql)
            print("APPLY_OK")
            print("SMOKE", SMOKE_PATH.name)
            cur.execute(smoke)
            # notices
            for notice in conn.notices[-8:]:
                print(notice.strip())
            print("SMOKE_DONE")
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
