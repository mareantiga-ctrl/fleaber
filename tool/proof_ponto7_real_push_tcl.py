#!/usr/bin/env python3
"""Ponto 7 — prova push real PROD após GRANT (sem imprimir secrets/tokens).

- Resolve user do TCL por handle (agostinhomarina334) ou seller QA
- Lista tokens activos: classifica real vs artificial (ponto7_test_*)
- Emit chat + proposta + notify-dispatch (service_role)
- Lê notification_delivery_log (status/error truncado)
"""
from __future__ import annotations

import json
import subprocess
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = ROOT / "tool" / "live_ops_production.env"
OUT = ROOT / "tool" / "reports" / "ponto7_grant_push_20261030"
REF = "bpmpkzwnrbmuqnhgdscf"
FN_URL = f"https://{REF}.supabase.co/functions/v1/notify-dispatch"
HANDLE = "agostinhomarina334"

PS = r"""
Add-Type @"
using System; using System.Runtime.InteropServices;
public class CredManP7Push {
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
$pw = [CredManP7Push]::Read('FleaberProdPostgres')
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


def http_json(url, *, method="GET", headers=None, body=None, timeout=60):
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

    for host, port in [
        ("aws-1-eu-west-1.pooler.supabase.com", 5432),
        ("aws-0-eu-west-1.pooler.supabase.com", 6543),
    ]:
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
            print(f"pg_ok {host}")
            return conn
        except Exception as e:  # noqa: BLE001
            print(f"pg_fail {host}: {type(e).__name__}")
    raise SystemExit("no_pg")


def classify_token(token: str) -> str:
    t = (token or "").strip()
    if not t:
        return "empty"
    if t.startswith("ponto7_test_token_"):
        return "artificial_test"
    # FCM registration tokens are typically long opaque strings
    if len(t) >= 80 and " " not in t:
        return "likely_real_fcm"
    return "suspicious_short"


def token_meta(token: str) -> dict:
    return {
        "class": classify_token(token),
        "len": len(token or ""),
        "prefix4": (token or "")[:4],
        "has_colon": ":" in (token or ""),
    }


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    phase = (Path.cwd() / "tool" / "_push_phase.txt").read_text(encoding="utf-8").strip() if (ROOT / "tool" / "_push_phase.txt").exists() else "all"
    # allow env override via argv-less file written by shell
    import sys

    phase = sys.argv[1] if len(sys.argv) > 1 else "probe"
    env = load_env(ENV_PATH)
    pw = subprocess.check_output(
        ["powershell", "-NoProfile", "-Command", PS], text=True
    ).strip()
    conn = connect_pg(pw)
    cur = conn.cursor()

    report: dict = {"ts": stamp, "phase": phase, "steps": {}}

    # Resolve TCL user by handle / full_name
    cur.execute(
        """
        select id::text, coalesce(handle, full_name, '')
        from public.profiles
        where lower(coalesce(handle,'')) = lower(%s)
           or handle ilike %s
           or full_name ilike %s
        limit 1
        """,
        (HANDLE, f"%{HANDLE}%", f"%{HANDLE}%"),
    )
    row = cur.fetchone()
    if not row:
        report["steps"]["profile_lookup"] = {"found": False, "handle": HANDLE}
        print(json.dumps(report["steps"]["profile_lookup"]))
        conn.close()
        (OUT / f"push_{phase}_{stamp}.json").write_text(
            json.dumps(report, indent=2), encoding="utf-8"
        )
        return 4

    user_id, uname = row[0], row[1]
    report["steps"]["profile"] = {"user_id": user_id, "name": uname}

    # grants check
    cur.execute(
        """
        select table_name,
          has_table_privilege('service_role', format('public.%I', table_name), 'SELECT') as sel,
          has_table_privilege('service_role', format('public.%I', table_name), 'INSERT') as ins,
          has_table_privilege('service_role', format('public.%I', table_name), 'UPDATE') as upd
        from (values ('device_push_tokens'),('notification_delivery_log')) v(table_name);
        """
    )
    report["steps"]["grants"] = [
        {"table": r[0], "select": r[1], "insert": r[2], "update": r[3]}
        for r in cur.fetchall()
    ]

    if phase == "revoke_artificial":
        cur.execute(
            """
            update public.device_push_tokens
            set revoked_at = now()
            where user_id = %s::uuid
              and revoked_at is null
              and token like 'ponto7_test_token_%%'
            returning id::text
            """,
            (user_id,),
        )
        revoked = [r[0] for r in cur.fetchall()]
        conn.commit()
        report["steps"]["revoked_artificial"] = len(revoked)
        print("revoked_artificial", len(revoked))

    # list tokens (never dump full token)
    cur.execute(
        """
        select id::text, platform, token, created_at::text, last_seen_at::text, revoked_at::text
        from public.device_push_tokens
        where user_id = %s::uuid and revoked_at is null
        order by coalesce(last_seen_at, created_at) desc
        """,
        (user_id,),
    )
    tokens = []
    for r in cur.fetchall():
        meta = token_meta(r[2])
        tokens.append(
            {
                "id": r[0],
                "platform": r[1],
                "created_at": r[3],
                "last_seen_at": r[4],
                **meta,
            }
        )
    report["steps"]["active_tokens"] = tokens
    real_tokens = [t for t in tokens if t["class"] == "likely_real_fcm"]
    report["steps"]["real_token_count"] = len(real_tokens)
    print(
        "tokens",
        json.dumps(
            {
                "active": len(tokens),
                "real": len(real_tokens),
                "classes": [t["class"] for t in tokens],
                "lens": [t["len"] for t in tokens],
            }
        ),
    )

    if phase == "probe":
        conn.close()
        (OUT / f"push_{phase}_{stamp}.json").write_text(
            json.dumps(report, indent=2), encoding="utf-8"
        )
        print("WROTE", f"push_{phase}_{stamp}.json")
        return 0 if real_tokens else 20

    if phase.startswith("dispatch_"):
        kind = (
            "chat_message"
            if "chat" in phase
            else "price_offer_accepted"
        )
        title = "Fleaber chat" if kind == "chat_message" else "Fleaber proposta"
        body = "Nova mensagem (prova GRANT)" if kind == "chat_message" else "Proposta actualizada (prova GRANT)"
        mode = phase.split("_", 2)[-1]  # fg / bg / killed
        dedupe = f"ponto7_real_{kind}_{mode}_{stamp}_{uuid.uuid4().hex[:8]}"
        cur.execute(
            """
            select public.batata_emit_user_notification_trusted(
              %s::uuid, %s, %s, %s,
              null, null, null, null, %s
            )
            """,
            (user_id, kind, title, body, dedupe),
        )
        nid = str(cur.fetchone()[0])
        conn.commit()
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
        time.sleep(1.5)
        cur.execute(
            """
            select channel, status, kind, left(coalesce(error_text,''),160), created_at::text
            from public.notification_delivery_log
            where notification_id = %s::uuid
            order by created_at desc
            """,
            (nid,),
        )
        logs = [
            {
                "channel": r[0],
                "status": r[1],
                "kind": r[2],
                "error": r[3],
                "created_at": r[4],
            }
            for r in cur.fetchall()
        ]
        report["steps"]["dispatch"] = {
            "mode": mode,
            "kind": kind,
            "notification_id": nid,
            "dedupe_key": dedupe,
            "http": d_code,
            "body": safe,
            "delivery_log": logs,
            "had_real_token": len(real_tokens) > 0,
        }
        print("dispatch", json.dumps(report["steps"]["dispatch"], default=str))
        conn.close()
        (OUT / f"push_{phase}_{stamp}.json").write_text(
            json.dumps(report, indent=2), encoding="utf-8"
        )
        print("WROTE", f"push_{phase}_{stamp}.json")
        push_ok = safe.get("push") == "sent" or any(
            x.get("status") == "sent" and x.get("channel") == "push" for x in logs
        )
        return 0 if push_ok else 30

    conn.close()
    (OUT / f"push_{phase}_{stamp}.json").write_text(
        json.dumps(report, indent=2), encoding="utf-8"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
