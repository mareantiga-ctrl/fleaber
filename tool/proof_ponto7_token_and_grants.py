#!/usr/bin/env python3
"""Login seller → register fake token via RPC → probe grants → dispatch.

Secrets never printed. Proves whether Edge can read tokens.
"""
from __future__ import annotations

import json
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = ROOT / "tool" / "live_ops_production.env"
OUT_DIR = ROOT / "tool" / "reports" / "ponto7_edge_prod_20261030"
REF = "bpmpkzwnrbmuqnhgdscf"
FN_URL = f"https://{REF}.supabase.co/functions/v1/notify-dispatch"

PS = r"""
Add-Type @"
using System; using System.Runtime.InteropServices;
public class CredManP7G2 {
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
$pw = [CredManP7G2]::Read('FleaberProdPostgres')
[Console]::Out.Write($pw)
"""


def load_env(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        t = line.strip()
        if not t or t.startswith("#") or "=" not in t:
            continue
        k, v = t.split("=", 1)
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def http_json(url, *, method="GET", headers=None, body=None, timeout=45):
    data = None
    hdrs = dict(headers or {})
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        hdrs.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=data, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            try:
                return resp.status, json.loads(raw) if raw else {}
            except json.JSONDecodeError:
                return resp.status, raw[:500]
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            parsed = raw[:500]
        return e.code, parsed


def connect_pg(pw: str):
    import psycopg2

    hosts = [
        ("aws-1-eu-west-1.pooler.supabase.com", 5432, "postgres.bpmpkzwnrbmuqnhgdscf"),
        ("aws-0-eu-west-1.pooler.supabase.com", 6543, "postgres.bpmpkzwnrbmuqnhgdscf"),
        ("db.bpmpkzwnrbmuqnhgdscf.supabase.co", 5432, "postgres"),
    ]
    last = None
    for host, port, user in hosts:
        try:
            conn = psycopg2.connect(
                host=host,
                port=port,
                dbname="postgres",
                user=user,
                password=pw,
                sslmode="require",
                connect_timeout=12,
            )
            print(f"pg_ok host={host} port={port}")
            return conn
        except Exception as e:  # noqa: BLE001
            last = e
            print(f"pg_fail host={host}: {type(e).__name__}")
    raise RuntimeError(f"no pg: {last}")


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    env = load_env(ENV_PATH)
    seller_id = env.get("PROD_TEST_SELLER_ID", "").strip()
    email = env.get("PROD_TEST_SELLER_EMAIL", "").strip()
    password = env.get("PROD_TEST_SELLER_PASSWORD", "").strip()
    report: dict = {"ts": stamp, "steps": {}}

    # Auth seller (password never logged)
    code, auth = http_json(
        env["SUPABASE_URL"].rstrip("/") + "/auth/v1/token?grant_type=password",
        method="POST",
        headers={
            "apikey": env["SUPABASE_ANON_KEY"],
            "Content-Type": "application/json",
        },
        body={"email": email, "password": password},
    )
    access = auth.get("access_token") if isinstance(auth, dict) else None
    uid = (auth.get("user") or {}).get("id") if isinstance(auth, dict) else None
    report["steps"]["seller_login"] = {
        "http": code,
        "uid_match": uid == seller_id,
        "uid_prefix": (uid or "")[:8],
    }
    print("login", report["steps"]["seller_login"])
    if not access:
        print("LOGIN_FAIL")
        (OUT_DIR / f"token_grants_{stamp}.json").write_text(
            json.dumps(report, indent=2), encoding="utf-8"
        )
        return 3

    fake_token = f"ponto7_test_token_{stamp}_{uuid.uuid4().hex[:12]}"
    code, reg = http_json(
        env["SUPABASE_URL"].rstrip("/") + "/rest/v1/rpc/batata_register_push_token",
        method="POST",
        headers={
            "apikey": env["SUPABASE_ANON_KEY"],
            "Authorization": f"Bearer {access}",
            "Content-Type": "application/json",
        },
        body={"p_token": fake_token, "p_platform": "android", "p_app_version": "ponto7-edge"},
    )
    report["steps"]["register_token"] = {
        "http": code,
        "ok": code == 200,
        "token_prefix": fake_token[:22],
    }
    print("register", report["steps"]["register_token"])

    # Grants + counts via postgres
    pw = subprocess.check_output(
        ["powershell", "-NoProfile", "-Command", PS], text=True
    ).strip()
    conn = connect_pg(pw)
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
    report["steps"]["grants_service_role"] = [
        {"table": r[0], "select": r[1], "insert": r[2], "update": r[3]}
        for r in cur.fetchall()
    ]
    cur.execute(
        """
        select count(*) from public.device_push_tokens
        where user_id = %s::uuid and revoked_at is null
        """,
        (seller_id,),
    )
    report["steps"]["seller_active_tokens"] = cur.fetchone()[0]
    print("grants", report["steps"]["grants_service_role"])
    print("seller_tokens", report["steps"]["seller_active_tokens"])

    # Emit + dispatch
    dedupe = f"ponto7_grant_probe_{stamp}"
    cur.execute(
        """
        select public.batata_emit_user_notification_trusted(
          %s::uuid, 'chat_message', 'Ponto7 grant probe', 'teste',
          null, null, null, null, %s
        )
        """,
        (seller_id, dedupe),
    )
    nid = str(cur.fetchone()[0])
    conn.commit()
    report["steps"]["emit_id"] = nid

    d_code, d_body = http_json(
        FN_URL,
        method="POST",
        headers={
            "apikey": env["SUPABASE_SERVICE_ROLE_KEY"],
            "Authorization": f"Bearer {env['SUPABASE_SERVICE_ROLE_KEY']}",
            "Content-Type": "application/json",
        },
        body={"notification_id": nid},
    )
    safe = {}
    if isinstance(d_body, dict):
        safe = {
            k: v
            for k, v in d_body.items()
            if k in ("ok", "notification_id", "push", "email", "error")
            or str(k).startswith("push")
        }
    report["steps"]["dispatch"] = {"http": d_code, "body": safe}
    print("dispatch", report["steps"]["dispatch"])

    time.sleep(0.8)
    cur.execute(
        """
        select channel, status, left(coalesce(error_text,''),120)
        from public.notification_delivery_log
        where notification_id = %s::uuid
        order by created_at desc
        """,
        (nid,),
    )
    report["steps"]["delivery_for_nid"] = [
        {"channel": r[0], "status": r[1], "error": r[2]} for r in cur.fetchall()
    ]

    # cleanup fake token + smoke notif
    cur.execute(
        "update public.device_push_tokens set revoked_at = now() where token = %s",
        (fake_token,),
    )
    cur.execute(
        "delete from public.user_notifications where dedupe_key = %s", (dedupe,)
    )
    conn.commit()
    conn.close()

    grants = report["steps"]["grants_service_role"]
    token_sel = next(
        (g["select"] for g in grants if g["table"] == "device_push_tokens"), False
    )
    report["verdict"] = {
        "seller_login_ok": report["steps"]["seller_login"]["uid_match"],
        "register_token_ok": report["steps"]["register_token"]["ok"],
        "service_role_can_select_tokens": token_sel,
        "dispatch_push": safe.get("push"),
        "blocker": None
        if token_sel
        else "service_role lacks SELECT on device_push_tokens — Edge cannot load FCM tokens",
    }
    out = OUT_DIR / f"token_grants_{stamp}.json"
    out.write_text(json.dumps(report, indent=2, default=str), encoding="utf-8")
    print("WROTE", out.name)
    print("VERDICT", json.dumps(report["verdict"]))
    return 0 if token_sel and safe.get("push") not in (None, "skipped_no_tokens") else 30


if __name__ == "__main__":
    raise SystemExit(main())
