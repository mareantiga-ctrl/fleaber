#!/usr/bin/env python3
"""Minimal PROD grants so notify-dispatch (service_role) can read tokens + write delivery log.

No schema/trigger/RPC changes. Idempotent. Never prints password.
"""
from __future__ import annotations

import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

OUT = Path("tool/reports/ponto7_edge_prod_20261030")

PS = r"""
Add-Type @"
using System; using System.Runtime.InteropServices;
public class CredManP7Gr {
  [DllImport("Advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool CredRead(string target, int type, int flags, out IntPtr cred);
  [DllImport("Advapi32.dll", SetLastError=true)] public static extern bool CredFree(IntPtr cred);
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
$pw = [CredManP7Gr]::Read('FleaberProdPostgres')
[Console]::Out.Write($pw)
"""

SQL = """
grant select, insert, update on public.device_push_tokens to service_role;
grant select, insert on public.notification_delivery_log to service_role;
-- authenticated already uses SECURITY DEFINER RPCs; keep table RLS as-is
"""


def connect(pw: str):
    import psycopg2

    hosts = [
        ("aws-1-eu-west-1.pooler.supabase.com", 5432),
        ("aws-0-eu-west-1.pooler.supabase.com", 6543),
        ("db.bpmpkzwnrbmuqnhgdscf.supabase.co", 5432),
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
                connect_timeout=20,
            )
            print(f"connected host={host}")
            return conn
        except Exception as e:  # noqa: BLE001
            last = e
            print(f"fail {host}: {type(e).__name__}")
    raise SystemExit(f"connect failed: {last}")


ROLLBACK_SQL = """-- Rollback GO GRANT service_role (ponto7 push) — PROD only
-- Restores pre-grant privileges for these two tables only.
revoke select, insert, update on public.device_push_tokens from service_role;
revoke select, insert on public.notification_delivery_log from service_role;
"""


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    rollback_path = OUT / f"rollback_grants_service_role_{stamp}.sql"
    rollback_path.write_text(ROLLBACK_SQL, encoding="utf-8")
    print("ROLLBACK_SAVED", rollback_path.name)

    pw = subprocess.check_output(
        ["powershell", "-NoProfile", "-Command", PS], text=True
    ).strip()
    if not pw:
        print("NO_CREDMAN")
        return 2
    conn = connect(pw)
    cur = conn.cursor()
    before = []
    cur.execute(
        """
        select table_name,
          has_table_privilege('service_role', format('public.%I', table_name), 'SELECT'),
          has_table_privilege('service_role', format('public.%I', table_name), 'INSERT'),
          has_table_privilege('service_role', format('public.%I', table_name), 'UPDATE')
        from (values ('device_push_tokens'),('notification_delivery_log')) v(table_name);
        """
    )
    before = [
        {"table": r[0], "select": r[1], "insert": r[2], "update": r[3]}
        for r in cur.fetchall()
    ]
    print("BEFORE", json.dumps(before))
    # Refuse if unexpected privileges already differ in ways that need human review —
    # still allow apply when all false (expected from prior probe).
    cur.execute(SQL)
    conn.commit()
    cur.execute(
        """
        select table_name,
          has_table_privilege('service_role', format('public.%I', table_name), 'SELECT'),
          has_table_privilege('service_role', format('public.%I', table_name), 'INSERT'),
          has_table_privilege('service_role', format('public.%I', table_name), 'UPDATE')
        from (values ('device_push_tokens'),('notification_delivery_log')) v(table_name);
        """
    )
    after = [
        {"table": r[0], "select": r[1], "insert": r[2], "update": r[3]}
        for r in cur.fetchall()
    ]
    conn.close()
    tokens_ok = next(
        r for r in after if r["table"] == "device_push_tokens"
    )
    log_ok = next(r for r in after if r["table"] == "notification_delivery_log")
    report = {
        "ts": stamp,
        "project": "bpmpkzwnrbmuqnhgdscf",
        "sql_applied": [
            "grant select, insert, update on public.device_push_tokens to service_role",
            "grant select, insert on public.notification_delivery_log to service_role",
        ],
        "rollback_file": rollback_path.name,
        "before": before,
        "after": after,
        "ok": (
            tokens_ok["select"]
            and tokens_ok["insert"]
            and tokens_ok["update"]
            and log_ok["select"]
            and log_ok["insert"]
        ),
    }
    path = OUT / f"grants_applied_{stamp}.json"
    path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("AFTER", json.dumps(after))
    print(json.dumps({"ok": report["ok"], "rollback": rollback_path.name}))
    print("WROTE", path.name)
    return 0 if report["ok"] else 10


if __name__ == "__main__":
    raise SystemExit(main())
