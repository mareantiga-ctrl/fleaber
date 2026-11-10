#!/usr/bin/env python3
"""GO-0 backup snapshot + GO-A apply ZIP 140-142 migrations to Fleaber PROD."""
from __future__ import annotations

import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKUP_DIR = ROOT / "tool" / "reports" / "144-prod-integrated-test-results" / "backup"
MIGRATIONS = [
    ROOT
    / "supabase/migrations/20261103200000_order_weight_shipping_delta_deadlines_batata.sql",
    ROOT
    / "supabase/migrations/20261103210000_order_shipping_delta_notify_c2_contract_batata.sql",
    ROOT
    / "supabase/migrations/20261103220000_shipping_delta_fee_policy_psd2_batata.sql",
]

PS_GET_PW = r"""
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CredManZip143 {
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
$pw = [CredManZip143]::Read('FleaberProdPostgres')
[Console]::Out.Write($pw)
"""


def connect():
    pw = subprocess.check_output(
        ["powershell", "-NoProfile", "-Command", PS_GET_PW], text=True
    ).strip()
    if not pw:
        raise SystemExit("no CredMan FleaberProdPostgres")
    try:
        import psycopg2
    except ImportError:
        subprocess.check_call(
            [sys.executable, "-m", "pip", "install", "psycopg2-binary", "-q"]
        )
        import psycopg2

    return psycopg2.connect(
        host="aws-1-eu-west-1.pooler.supabase.com",
        port=5432,
        dbname="postgres",
        user="postgres.bpmpkzwnrbmuqnhgdscf",
        password=pw,
        sslmode="require",
        connect_timeout=40,
    )


def main() -> int:
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    conn = connect()
    conn.autocommit = False
    cur = conn.cursor()

    # GO-0 snapshot (metadata only — no secrets)
    cur.execute(
        """
        select jsonb_build_object(
          'orders_count', (select count(*) from public.orders),
          'products_count', (select count(*) from public.products),
          'flags', coalesce((
            select jsonb_object_agg(key, enabled)
            from public.fleaber_feature_flags
            where key like 'order_%' or key like 'dpd_%'
          ), '{}'::jsonb),
          'has_order_shipping_adjustments', (
            select count(*) from information_schema.tables
            where table_schema='public' and table_name='order_shipping_adjustments'
          ),
          'has_weight_confirm_status', (
            select count(*) from information_schema.columns
            where table_schema='public' and table_name='orders'
              and column_name='weight_confirm_status'
          ),
          'has_batata_shipping_delta_charge', (
            select to_regprocedure('public.batata_shipping_delta_charge_cents(integer)')
              is not null
          ),
          'has_seller_confirm', (
            select to_regprocedure(
              'public.batata_seller_confirm_shipping_weight(uuid,numeric,text,text)'
            ) is not null
          )
        )
        """
    )
    pre = cur.fetchone()[0]
    pre_path = BACKUP_DIR / f"pre_snapshot_{stamp}.json"
    pre_path.write_text(json.dumps(pre, indent=2, default=str), encoding="utf-8")
    print("GO-0 snapshot", pre_path)

    # DDL dump of related objects for rollback reference
    cur.execute(
        """
        select column_name, data_type
        from information_schema.columns
        where table_schema='public' and table_name='orders'
          and column_name like 'shipping_%' or (
            table_schema='public' and table_name='orders'
            and column_name like 'weight_%' or (
              table_schema='public' and table_name='orders'
              and column_name like 'ship_%'
            )
          )
        order by column_name
        """
    )
    cols = cur.fetchall()
    (BACKUP_DIR / f"pre_orders_cols_{stamp}.txt").write_text(
        "\n".join(f"{a}\t{b}" for a, b in cols), encoding="utf-8"
    )

    conn.commit()

    for path in MIGRATIONS:
        sql = path.read_text(encoding="utf-8")
        print("APPLY", path.name, "bytes", len(sql))
        cur.execute(sql)
        conn.commit()
        print("  OK", path.name)

    cur.execute(
        """
        select jsonb_build_object(
          'flags', coalesce((
            select jsonb_object_agg(key, enabled)
            from public.fleaber_feature_flags
            where key like 'order_%'
          ), '{}'::jsonb),
          'has_order_shipping_adjustments', (
            select count(*) from information_schema.tables
            where table_schema='public' and table_name='order_shipping_adjustments'
          ),
          'has_weight_confirm_status', (
            select count(*) from information_schema.columns
            where table_schema='public' and table_name='orders'
              and column_name='weight_confirm_status'
          ),
          'has_batata_shipping_delta_charge', (
            select to_regprocedure('public.batata_shipping_delta_charge_cents(integer)')
              is not null
          ),
          'has_seller_confirm', (
            select to_regprocedure(
              'public.batata_seller_confirm_shipping_weight(uuid,numeric,text,text)'
            ) is not null
          ),
          'has_blocks_dpd', (
            select to_regprocedure('public.batata_order_blocks_dpd_create(uuid)')
              is not null
          ),
          'has_expire', (
            select to_regprocedure(
              'public.batata_expire_shipping_deltas_and_deadlines(timestamptz,integer)'
            ) is not null
          ),
          'adjustments_count', (
            select count(*) from public.order_shipping_adjustments
          )
        )
        """
    )
    post = cur.fetchone()[0]
    post_path = BACKUP_DIR / f"post_snapshot_{stamp}.json"
    post_path.write_text(json.dumps(post, indent=2, default=str), encoding="utf-8")
    print("GO-A post", json.dumps(post, indent=2, default=str))
    cur.close()
    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
