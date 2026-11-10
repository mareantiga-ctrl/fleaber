#!/usr/bin/env python3
"""Apply ZIP 135 DPD shipping rates / weight migration to Fleaber Prod."""
from __future__ import annotations

import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL_PATH = ROOT / (
    "supabase/migrations/20261103140000_dpd_shipping_rates_weight_batata.sql"
)
BACKUP_DIR = ROOT / "tool" / "reports" / "135-fleaber-dpd-implementacao-prod" / "backup"

PS_GET_PW = r"""
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CredManDpd135 {
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
$pw = [CredManDpd135]::Read('FleaberProdPostgres')
[Console]::Out.Write($pw)
"""


def main() -> int:
    sql = SQL_PATH.read_text(encoding="utf-8")
    pw = subprocess.check_output(
        ["powershell", "-NoProfile", "-Command", PS_GET_PW], text=True
    ).strip()
    if not pw:
        print("no CredMan FleaberProdPostgres")
        return 2
    try:
        import psycopg2
    except ImportError:
        subprocess.check_call(
            [sys.executable, "-m", "pip", "install", "psycopg2-binary", "-q"]
        )
        import psycopg2

    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
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

    # Pre-backup: snapshot counts + column presence
    cur.execute(
        """
        select
          (select count(*) from information_schema.tables
             where table_schema='public' and table_name='dpd_shipping_rates'),
          (select count(*) from information_schema.columns
             where table_name='products' and column_name='shipping_weight_kg'),
          (select count(*) from public.orders)
        """
    )
    pre = cur.fetchone()
    (BACKUP_DIR / f"pre_{stamp}.txt").write_text(
        f"dpd_shipping_rates_exists={pre[0]}\n"
        f"products_shipping_weight_kg={pre[1]}\n"
        f"orders_count={pre[2]}\n",
        encoding="utf-8",
    )

    cur.execute(sql)
    conn.commit()

    cur.execute(
        """
        select
          (select count(*) from public.dpd_shipping_rates),
          (select count(*) from public.fleaber_feature_flags where key like 'dpd_%'),
          (select count(*) from information_schema.columns
             where table_name='orders' and column_name='shipping_weight_kg'),
          (select to_regprocedure(
             'public.batata_dpd_quote_shipping(text,numeric,text,boolean)'
           ) is not null)
        """
    )
    post = cur.fetchone()
    print(
        "OK rates=",
        post[0],
        "flags=",
        post[1],
        "orders.weight_col=",
        post[2],
        "quote_fn=",
        post[3],
    )
    cur.close()
    conn.close()
    return 0 if post[0] >= 6 and post[3] else 1


if __name__ == "__main__":
    raise SystemExit(main())
