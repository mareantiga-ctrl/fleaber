#!/usr/bin/env python3
"""Read-only probe: service_role grants + token count (no secrets printed)."""
from __future__ import annotations

import json
import subprocess
import sys

import psycopg2

PS = r"""
Add-Type @"
using System; using System.Runtime.InteropServices;
public class CredManP7G {
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
$pw = [CredManP7G]::Read('FleaberProdPostgres')
[Console]::Out.Write($pw)
"""


def main() -> int:
    pw = subprocess.check_output(
        ["powershell", "-NoProfile", "-Command", PS], text=True
    ).strip()
    if not pw:
        print("NO_CREDMAN")
        return 2
    conn = psycopg2.connect(
        host="db.bpmpkzwnrbmuqnhgdscf.supabase.co",
        port=5432,
        dbname="postgres",
        user="postgres",
        password=pw,
        sslmode="require",
    )
    cur = conn.cursor()
    cur.execute(
        """
        select table_name,
          has_table_privilege('service_role', format('public.%I', table_name), 'SELECT') as sel,
          has_table_privilege('service_role', format('public.%I', table_name), 'INSERT') as ins,
          has_table_privilege('service_role', format('public.%I', table_name), 'UPDATE') as upd
        from (values ('device_push_tokens'),('notification_delivery_log'),('user_notifications')) v(table_name);
        """
    )
    grants = [
        {"table": r[0], "select": r[1], "insert": r[2], "update": r[3]}
        for r in cur.fetchall()
    ]
    cur.execute(
        """
        select grantee, table_name, privilege_type
        from information_schema.role_table_grants
        where table_schema='public'
          and table_name in ('device_push_tokens','notification_delivery_log')
        order by 2,1,3;
        """
    )
    role_grants = cur.fetchall()
    cur.execute(
        "select count(*) from public.device_push_tokens where revoked_at is null"
    )
    token_count = cur.fetchone()[0]
    cur.execute(
        """
        select channel, status, kind, left(coalesce(error_text,''),100), created_at::text
        from public.notification_delivery_log
        order by created_at desc limit 8
        """
    )
    logs = cur.fetchall()
    # SQL file grants present?
    cur.execute(
        """
        select p.proname,
          has_function_privilege('service_role', p.oid, 'EXECUTE') as svc_exec,
          has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec
        from pg_proc p
        join pg_namespace n on n.oid=p.pronamespace
        where n.nspname='public'
          and p.proname in (
            'batata_register_push_token',
            'batata_revoke_push_token',
            'batata_emit_user_notification',
            'batata_emit_user_notification_trusted'
          )
        order by 1;
        """
    )
    rpcs = [
        {"fn": r[0], "service_exec": r[1], "auth_exec": r[2]} for r in cur.fetchall()
    ]
    conn.close()
    out = {
        "grants_service_role": grants,
        "role_table_grants": role_grants,
        "active_token_count": token_count,
        "delivery_log_recent": logs,
        "rpcs": rpcs,
    }
    print(json.dumps(out, indent=2, default=str))
    Path = __import__("pathlib").Path
    dest = Path("tool/reports/ponto7_edge_prod_20261030/grants_probe.json")
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(out, indent=2, default=str), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
