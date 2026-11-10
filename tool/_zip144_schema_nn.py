#!/usr/bin/env python3
import json
import subprocess
import sys

import psycopg2
from psycopg2.extras import RealDictCursor

PS = r"""
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CredManNn144 {
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
[Console]::Out.Write([CredManNn144]::Read('FleaberProdPostgres'))
"""


def main() -> int:
    pw = subprocess.check_output(
        ["powershell", "-NoProfile", "-Command", PS], text=True
    ).strip()
    conn = psycopg2.connect(
        host="aws-1-eu-west-1.pooler.supabase.com",
        port=5432,
        dbname="postgres",
        user="postgres.bpmpkzwnrbmuqnhgdscf",
        password=pw,
        sslmode="require",
    )
    cur = conn.cursor(cursor_factory=RealDictCursor)
    out = {}
    for table in ("orders", "products"):
        cur.execute(
            """
          select column_name, is_nullable, column_default, data_type
          from information_schema.columns
          where table_schema='public' and table_name=%s and is_nullable='NO'
          order by ordinal_position
        """,
            (table,),
        )
        out[f"{table}_nn"] = list(cur.fetchall())

    cur.execute("select * from public.products limit 1")
    row = cur.fetchone()
    out["product_keys"] = sorted(row.keys()) if row else []
    out["product_sample"] = {
        k: row[k]
        for k in (
            "id",
            "title",
            "name",
            "seller_id",
            "user_id",
            "price",
            "price_cents",
            "status",
            "is_sold",
            "shipping_weight_kg",
            "shipping_weight_band",
        )
        if row and k in row
    }

    cur.execute(
        """
      select table_name from information_schema.tables
      where table_schema='public'
        and (table_name like '%notif%' or table_name like '%notification%')
      order by 1
    """
    )
    out["notif_tables"] = [r["table_name"] for r in cur.fetchall()]

    cur.execute(
        """
      select column_name from information_schema.columns
      where table_schema='public' and table_name='orders'
        and column_name ~* 'price|amount|total|product|shipping_method|buyer|seller|status'
      order by 1
    """
    )
    out["amount_cols"] = [r["column_name"] for r in cur.fetchall()]

    cur.execute("select * from public.orders where status='pago' order by created_at desc limit 1")
    paid = cur.fetchone()
    if paid:
        keep = [
            "id",
            "status",
            "buyer_id",
            "seller_id",
            "product_id",
            "shipping_method",
            "shipping_modality",
            "created_at",
        ]
        out["paid_template"] = {k: paid.get(k) for k in keep if k in paid}
        out["paid_template_extra_keys"] = sorted(paid.keys())[:40]

    print(json.dumps(out, default=str, indent=2))
    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
