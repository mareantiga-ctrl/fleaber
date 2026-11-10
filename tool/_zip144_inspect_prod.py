#!/usr/bin/env python3
"""Inspect PROD for ZIP 144 harness prep."""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

PS = r"""
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CredManIns144 {
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
[Console]::Out.Write([CredManIns144]::Read('FleaberProdPostgres'))
"""


def main() -> int:
    try:
        import psycopg2
        from psycopg2.extras import RealDictCursor
    except ImportError:
        subprocess.check_call(
            [sys.executable, "-m", "pip", "install", "psycopg2-binary", "-q"]
        )
        import psycopg2
        from psycopg2.extras import RealDictCursor

    pw = subprocess.check_output(
        ["powershell", "-NoProfile", "-Command", PS], text=True
    ).strip()
    if not pw:
        print("no password")
        return 2

    conn = psycopg2.connect(
        host="aws-1-eu-west-1.pooler.supabase.com",
        port=5432,
        dbname="postgres",
        user="postgres.bpmpkzwnrbmuqnhgdscf",
        password=pw,
        sslmode="require",
        connect_timeout=25,
    )
    cur = conn.cursor(cursor_factory=RealDictCursor)
    out: dict = {}

    cur.execute(
        """
      select key, enabled from public.fleaber_feature_flags
      where key like 'order_%' or key like '%shipping%' or key like '%dpd%'
      order by key
    """
    )
    out["flags"] = list(cur.fetchall())

    cur.execute(
        """
      select column_name from information_schema.columns
      where table_schema='public' and table_name='orders'
        and (column_name like '%weight%' or column_name like '%ship%'
             or column_name like '%delta%' or column_name like '%shipping%')
      order by 1
    """
    )
    out["order_cols"] = [r["column_name"] for r in cur.fetchall()]

    cur.execute(
        """
      select column_name from information_schema.columns
      where table_schema='public' and table_name='products'
        and (column_name like '%weight%' or column_name like '%shipping%')
      order by 1
    """
    )
    out["product_weight_cols"] = [r["column_name"] for r in cur.fetchall()]

    cur.execute(
        """
      select id::text, email from auth.users
      where email ilike '%teste%' or email ilike '%test%' or email ilike '%zip143%'
         or email ilike '%fleaber%'
      order by created_at desc nulls last limit 30
    """
    )
    out["test_users"] = list(cur.fetchall())

    cur.execute(
        """
      select column_name from information_schema.columns
      where table_schema='public' and table_name='products'
      order by ordinal_position
    """
    )
    out["product_all_cols_sample"] = [
        r["column_name"] for r in cur.fetchall() if r["column_name"] in (
            "id", "title", "name", "seller_id", "user_id", "price", "price_cents",
            "status", "is_sold", "shipping_weight_kg", "shipping_weight_band",
            "created_at",
        )
    ]

    cur.execute(
        """
      select proname from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public'
        and (
          proname like 'batata_%shipping%'
          or proname like 'batata_%weight%'
          or proname like 'batata_%ship%'
          or proname like 'batata_order_blocks%'
          or proname like 'batata_expire%'
          or proname like 'batata_add_business%'
          or proname like 'batata_dpd_weight%'
          or proname like 'batata_flag%'
          or proname like 'batata_mark_shipping%'
        )
      order by 1
    """
    )
    out["rpcs"] = [r["proname"] for r in cur.fetchall()]

    # orders table has what for notes/title?
    cur.execute(
        """
      select column_name from information_schema.columns
      where table_schema='public' and table_name='orders'
        and column_name in (
          'id','status','buyer_id','seller_id','payment_status','shipping_cents',
          'shipping_modality','total_cents','product_id','is_sold','created_at',
          'stripe_payment_intent_id','paid_at','shipping_cents_charged'
        )
      order by 1
    """
    )
    out["key_order_cols"] = [r["column_name"] for r in cur.fetchall()]

    cur.execute(
        """
      select column_name from information_schema.columns
      where table_schema='public' and table_name='orders'
      order by ordinal_position
    """
    )
    out["orders_all_cols"] = [r["column_name"] for r in cur.fetchall()]

    cur.execute(
        """
      select id::text, status, buyer_id::text, seller_id::text,
             shipping_modality, shipping_weight_charged_band, weight_confirm_status,
             shipping_delta_status, created_at::text
      from public.orders
      order by created_at desc nulls last
      limit 5
    """
    )
    out["recent_orders"] = list(cur.fetchall())

    # two most recent users for seller/buyer candidates
    cur.execute(
        """
      select id::text, email, created_at::text
      from auth.users
      order by created_at desc nulls last
      limit 15
    """
    )
    out["recent_users"] = list(cur.fetchall())

    cur.execute(
        """
      select modality, weight_band, price_eur, active
      from public.dpd_shipping_rates
      where active
      order by modality, weight_band
    """
    )
    out["dpd_rates"] = list(cur.fetchall())

    try:
        cur.execute(
            """
          select jobid::text, jobname, schedule, command
          from cron.job
          where jobname ilike '%ship%' or command ilike '%deadline%'
             or command ilike '%shipping%' or jobname ilike '%order%'
        """
        )
        out["cron_jobs"] = list(cur.fetchall())
    except Exception as e:
        out["cron_jobs_err"] = str(e)
        conn.rollback()

    # Célia rate helper presence
    cur.execute(
        """
      select proname from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and proname like 'batata_dpd%'
      order by 1
    """
    )
    out["dpd_rpcs"] = [r["proname"] for r in cur.fetchall()]

    print(json.dumps(out, default=str, indent=2))
    Path("tool/reports/144-prod-integrated-test-results/inspect_prod.json").write_text(
        json.dumps(out, default=str, indent=2), encoding="utf-8"
    )
    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
