#!/usr/bin/env python3
"""Apply ZIP 128 financial protection migration to Fleaber Prod (bpmp…)."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL_PATH = ROOT / (
    "supabase/migrations/"
    "20261101180000_financial_protection_fase1_batata.sql"
)

PS_GET_PW = r"""
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CredManApply128 {
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
$pw = [CredManApply128]::Read('FleaberProdPostgres')
if (-not $pw) { $pw = [CredManApply128]::Read('Supabase CLI:supabase') }
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
                connect_timeout=25,
                sslmode="require",
            )
            conn.autocommit = False
            cur = conn.cursor()
            print(f"connected {host}:{port}")
            cur.execute(sql)
            conn.commit()
            # smoke checks
            cur.execute(
                """
                select
                  (select count(*) from information_schema.columns
                     where table_schema='public' and table_name='orders'
                       and column_name='funds_hold_until') as orders_hold,
                  (select count(*) from information_schema.columns
                     where table_schema='public' and table_name='wallets'
                       and column_name='held_balance') as wallet_held,
                  (select to_regprocedure(
                     'public.batata_apply_stripe_dispute_freeze(text,uuid,uuid,integer,text,text,text,text,text,timestamptz,jsonb)'
                   ) is not null) as freeze_rpc,
                  (select to_regprocedure(
                     'public.batata_start_consumer_withdrawal(uuid)'
                   ) is not null) as withdrawal_rpc
                """
            )
            row = cur.fetchone()
            print("smoke:", row)
            cur.close()
            conn.close()
            print("OK applied ZIP 128 migration")
            return 0
        except Exception as e:
            last_err = e
            print(f"fail {host}:{port}: {e}")
    print("FAILED", last_err)
    return 3


if __name__ == "__main__":
    raise SystemExit(main())
