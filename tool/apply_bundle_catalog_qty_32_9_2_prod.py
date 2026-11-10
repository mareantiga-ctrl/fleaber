#!/usr/bin/env python3
"""Apply 32.9.2 catalog_subtotal unnest (qty) to Fleaber Prod."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL_PATH = ROOT / (
    "supabase/migrations/"
    "20261029120000_bundle_catalog_subtotal_qty_unnest_batata.sql"
)

PS_GET_PW = r"""
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CredManApply3292 {
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
$pw = [CredManApply3292]::Read('FleaberProdPostgres')
if (-not $pw) { $pw = [CredManApply3292]::Read('Supabase CLI:supabase') }
[Console]::Out.Write($pw)
"""


def main() -> int:
    sql = SQL_PATH.read_text(encoding="utf-8")
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
        import psycopg2
    except ImportError:
        subprocess.check_call(
            [sys.executable, "-m", "pip", "install", "psycopg2-binary", "-q"]
        )
        import psycopg2

    hosts = [
        ("aws-1-eu-west-1.pooler.supabase.com", 5432),
        ("aws-0-eu-west-1.pooler.supabase.com", 6543),
    ]
    last_err: Exception | None = None
    for host, port in hosts:
        try:
            conn = psycopg2.connect(
                host=host,
                port=port,
                dbname="postgres",
                user="postgres.bpmpkzwnrbmuqnhgdscf",
                password=pw,
                sslmode="require",
                connect_timeout=30,
            )
            conn.autocommit = True
            with conn.cursor() as cur:
                cur.execute(sql)
                cur.execute(
                    """
                    select public.batata_product_bundles_catalog_subtotal(array[
                      'c78c84d6-7268-4bea-bc74-15fa7237261e'::uuid,
                      'b9baaaa6-014f-4822-8a2b-ca7c2cc398ff'::uuid,
                      'b9baaaa6-014f-4822-8a2b-ca7c2cc398ff'::uuid
                    ]::uuid[]);
                    """
                )
                print("verify qty2 subtotal", cur.fetchone()[0])
            conn.close()
            print(f"OK applied via {host}:{port}")
            return 0
        except Exception as e:
            last_err = e
            print(f"fail {host}:{port}: {e}")
    print("FAILED", last_err)
    return 3


if __name__ == "__main__":
    raise SystemExit(main())
