#!/usr/bin/env python3
"""Ponto 7 — backup + apply notifications SQL on Fleaber Prod only.

Never prints DB password. Staging not used.
"""
from __future__ import annotations

import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL_PATH = ROOT / "supabase" / "sql" / "ponto7_notifications_batata.sql"
BACKUP_DIR = ROOT / "tool" / "backups" / "ponto7_sql_prod"
REPORT_DIR = ROOT / "tool" / "reports" / "ponto7_implementacao_20261030"

PS_GET_PW = r"""
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CredManPonto7 {
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
$pw = [CredManPonto7]::Read('FleaberProdPostgres')
if (-not $pw) { $pw = [CredManPonto7]::Read('Supabase CLI:supabase') }
[Console]::Out.Write($pw)
"""

PREFLIGHT_SQL = r"""
select jsonb_build_object(
  'db', current_database(),
  'user_notifications_exists', to_regclass('public.user_notifications') is not null,
  'dedupe_key_exists', exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='user_notifications' and column_name='dedupe_key'
  ),
  'device_push_tokens_exists', to_regclass('public.device_push_tokens') is not null,
  'delivery_log_exists', to_regclass('public.notification_delivery_log') is not null,
  'rpc_emit_exists', exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='batata_emit_user_notification'
  ),
  'chat_messages_text_col', exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='chat_messages' and column_name='text'
  ),
  'chat_messages_is_reservation_col', exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='chat_messages' and column_name='is_reservation'
  ),
  'product_offers_status_col', exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='product_offers' and column_name='status'
  ),
  'existing_chat_notify_tg', exists (
    select 1 from pg_trigger where tgname='batata_chat_messages_notify_tg'
  ),
  'existing_offer_outcome_tg', exists (
    select 1 from pg_trigger where tgname='batata_product_offers_outcome_notify_tg'
  ),
  'user_notifications_insert_policies', (
    select coalesce(jsonb_agg(policyname), '[]'::jsonb)
    from pg_policies
    where schemaname='public' and tablename='user_notifications' and cmd='INSERT'
  )
) as preflight;
"""

BACKUP_SQL = r"""
select jsonb_build_object(
  'ts', now(),
  'user_notifications_cols', (
    select coalesce(jsonb_agg(jsonb_build_object('column_name', column_name, 'data_type', data_type) order by ordinal_position), '[]'::jsonb)
    from information_schema.columns
    where table_schema='public' and table_name='user_notifications'
  ),
  'user_notifications_policies', (
    select coalesce(jsonb_agg(jsonb_build_object('policy', policyname, 'cmd', cmd, 'roles', roles)), '[]'::jsonb)
    from pg_policies where schemaname='public' and tablename='user_notifications'
  ),
  'chat_messages_triggers', (
    select coalesce(jsonb_agg(jsonb_build_object('tgname', t.tgname, 'tgenabled', t.tgenabled)), '[]'::jsonb)
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='chat_messages' and not t.tgisinternal
  ),
  'product_offers_triggers', (
    select coalesce(jsonb_agg(jsonb_build_object('tgname', t.tgname, 'tgenabled', t.tgenabled)), '[]'::jsonb)
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='product_offers' and not t.tgisinternal
  ),
  'batata_notify_price_offer_def', (
    select pg_get_functiondef(p.oid)
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='batata_notify_price_offer'
    limit 1
  )
) as backup;
"""

POSTCHECK_SQL = r"""
select jsonb_build_object(
  'dedupe_key_exists', exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='user_notifications' and column_name='dedupe_key'
  ),
  'device_push_tokens_exists', to_regclass('public.device_push_tokens') is not null,
  'delivery_log_exists', to_regclass('public.notification_delivery_log') is not null,
  'rpc_emit_exists', exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='batata_emit_user_notification'
  ),
  'rpc_trusted_exists', exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='batata_emit_user_notification_trusted'
  ),
  'rpc_register_token_exists', exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='batata_register_push_token'
  ),
  'chat_tg', exists (select 1 from pg_trigger where tgname='batata_chat_messages_notify_tg'),
  'offer_tg', exists (select 1 from pg_trigger where tgname='batata_product_offers_outcome_notify_tg'),
  'user_notifications_insert_policies', (
    select coalesce(jsonb_agg(policyname), '[]'::jsonb)
    from pg_policies
    where schemaname='public' and tablename='user_notifications' and cmd='INSERT'
  ),
  'device_push_rls', (
    select relrowsecurity from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='device_push_tokens'
  ),
  'delivery_log_rls', (
    select relrowsecurity from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='notification_delivery_log'
  )
) as postcheck;
"""


def get_pw() -> str:
    pw = subprocess.check_output(
        ["powershell", "-NoProfile", "-Command", PS_GET_PW],
        text=True,
    ).strip()
    if not pw:
        raise SystemExit("no CredMan password (FleaberProdPostgres)")
    return pw


def connect(pw: str):
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
        ("db.bpmpkzwnrbmuqnhgdscf.supabase.co", 5432),
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
                connect_timeout=20,
            )
            conn.autocommit = False
            print(f"connected host={host} port={port}")
            return conn
        except Exception as e:  # noqa: BLE001
            last_err = e
            print(f"connect_fail host={host}: {type(e).__name__}")
    raise SystemExit(f"connect failed: {last_err}")


def fetch_json(cur, sql: str, key: str):
    cur.execute(sql)
    row = cur.fetchone()
    return row[0] if row else None


def main() -> int:
    sql = SQL_PATH.read_text(encoding="utf-8")
    if "staging" in sql.lower() and "bpmp" not in "prod":
        pass
    # Hard stop markers
    forbidden = ["drop table public.user_notifications", "truncate public.orders"]
    low = sql.lower()
    for f in forbidden:
        if f in low:
            print(f"FORBIDDEN in SQL: {f}")
            return 3

    # Pre-verify SQL completeness
    required_snippets = [
        "dedupe_key",
        "device_push_tokens",
        "notification_delivery_log",
        "batata_emit_user_notification",
        "batata_emit_user_notification_trusted",
        "batata_register_push_token",
        "batata_chat_messages_notify_tg",
        "batata_product_offers_outcome_notify_tg",
        "grant execute on function public.batata_emit_user_notification",
    ]
    missing = [s for s in required_snippets if s not in sql]
    if missing:
        print("SQL incomplete, missing:", missing)
        return 4

    rollback = (REPORT_DIR / "rollback_ponto7.sql").read_text(encoding="utf-8")
    for must in [
        "batata_chat_messages_notify_tg",
        "batata_product_offers_outcome_notify_tg",
    ]:
        if must not in rollback:
            print("rollback incomplete:", must)
            return 5

    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    pw = get_pw()
    conn = connect(pw)
    cur = conn.cursor()

    print("=== PREFLIGHT ===")
    pre = fetch_json(cur, PREFLIGHT_SQL, "preflight")
    print(json.dumps(pre, indent=2, default=str))
    (BACKUP_DIR / f"preflight_{stamp}.json").write_text(
        json.dumps(pre, indent=2, default=str), encoding="utf-8"
    )

    if not pre.get("user_notifications_exists"):
        print("STOP: user_notifications missing")
        conn.close()
        return 10
    if not pre.get("chat_messages_text_col") or not pre.get(
        "chat_messages_is_reservation_col"
    ):
        print("STOP: chat_messages columns unexpected")
        conn.close()
        return 11
    if not pre.get("product_offers_status_col"):
        print("STOP: product_offers.status missing")
        conn.close()
        return 12
    # Must NOT open INSERT policies for authenticated on user_notifications after apply either
    insert_pols = pre.get("user_notifications_insert_policies") or []
    print("pre_insert_policies=", insert_pols)

    print("=== BACKUP ===")
    backup = fetch_json(cur, BACKUP_SQL, "backup")
    backup_path = BACKUP_DIR / f"schema_backup_{stamp}.json"
    backup_path.write_text(json.dumps(backup, indent=2, default=str), encoding="utf-8")
    # Also copy SQL + rollback next to backup
    (BACKUP_DIR / f"applied_sql_{stamp}.sql").write_text(sql, encoding="utf-8")
    (BACKUP_DIR / f"rollback_{stamp}.sql").write_text(rollback, encoding="utf-8")
    print(f"backup_ok path={backup_path.name}")

    print("=== APPLY ===")
    try:
        cur.execute(sql)
        conn.commit()
        print("apply_ok")
    except Exception as e:  # noqa: BLE001
        conn.rollback()
        print(f"APPLY_FAILED: {type(e).__name__}: {e}")
        conn.close()
        return 20

    print("=== POSTCHECK ===")
    post = fetch_json(cur, POSTCHECK_SQL, "postcheck")
    print(json.dumps(post, indent=2, default=str))
    (BACKUP_DIR / f"postcheck_{stamp}.json").write_text(
        json.dumps(post, indent=2, default=str), encoding="utf-8"
    )

    ok = all(
        [
            post.get("dedupe_key_exists"),
            post.get("device_push_tokens_exists"),
            post.get("delivery_log_exists"),
            post.get("rpc_emit_exists"),
            post.get("rpc_trusted_exists"),
            post.get("rpc_register_token_exists"),
            post.get("chat_tg"),
            post.get("offer_tg"),
            post.get("device_push_rls") is True,
            post.get("delivery_log_rls") is True,
        ]
    )
    insert_after = post.get("user_notifications_insert_policies") or []
    if insert_after:
        print("WARN: INSERT policies on user_notifications:", insert_after)

    # Technical RPC smoke as service (auth.uid null but jwt role may be absent on direct SQL)
    # Direct SQL as postgres = bypass; test trusted insert + dedupe
    print("=== TECH SMOKE ===")
    smoke = {}
    try:
        cur.execute(
            """
            select public.batata_emit_user_notification_trusted(
              (select id from auth.users limit 1),
              'chat_message',
              'Ponto7 smoke',
              'teste tecnico',
              null, null, null, null,
              'ponto7_smoke_dedupe_v1'
            );
            """
        )
        nid1 = cur.fetchone()[0]
        cur.execute(
            """
            select public.batata_emit_user_notification_trusted(
              (select id from auth.users limit 1),
              'chat_message',
              'Ponto7 smoke',
              'teste tecnico',
              null, null, null, null,
              'ponto7_smoke_dedupe_v1'
            );
            """
        )
        nid2 = cur.fetchone()[0]
        smoke["dedupe_same_id"] = nid1 == nid2 and nid1 is not None
        smoke["notif_id"] = str(nid1)
        # cleanup smoke row
        cur.execute(
            "delete from public.user_notifications where dedupe_key = 'ponto7_smoke_dedupe_v1'"
        )
        conn.commit()
        smoke["cleanup_ok"] = True
    except Exception as e:  # noqa: BLE001
        conn.rollback()
        smoke["error"] = f"{type(e).__name__}: {e}"
        smoke["dedupe_same_id"] = False

    print(json.dumps(smoke, indent=2, default=str))
    (BACKUP_DIR / f"smoke_{stamp}.json").write_text(
        json.dumps(smoke, indent=2, default=str), encoding="utf-8"
    )

    conn.close()
    if not ok or not smoke.get("dedupe_same_id"):
        print("POSTCHECK_OR_SMOKE_FAILED")
        return 30
    print("ALL_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
