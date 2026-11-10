#!/usr/bin/env python3
"""Ponto 7 fecho — emit chat+proposta com chat_id real + dispatch (sem secrets/tokens)."""
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
ENV = ROOT / "tool" / "live_ops_production.env"
OUT = ROOT / "tool" / "reports" / "ponto7_push_fecho_20261030"
HANDLE = "agostinhomarina334"
REF = "bpmpkzwnrbmuqnhgdscf"
FN = f"https://{REF}.supabase.co/functions/v1/notify-dispatch"

PS = r"""
Add-Type @"
using System; using System.Runtime.InteropServices;
public class CredManP7F {
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
$pw = [CredManP7F]::Read('FleaberProdPostgres')
[Console]::Out.Write($pw)
"""


def load_env():
    out = {}
    for line in ENV.read_text(encoding="utf-8").splitlines():
        t = line.strip()
        if not t or t.startswith("#") or "=" not in t:
            continue
        k, v = t.split("=", 1)
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def http_json(url, *, headers=None, body=None, method="POST"):
    data = json.dumps(body).encode() if body is not None else None
    hdrs = dict(headers or {})
    if body is not None:
        hdrs.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=data, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        try:
            return e.code, json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            return e.code, {"raw": raw[:300]}


def connect(pw):
    import psycopg2

    return psycopg2.connect(
        host="aws-1-eu-west-1.pooler.supabase.com",
        port=5432,
        dbname="postgres",
        user="postgres.bpmpkzwnrbmuqnhgdscf",
        password=pw,
        sslmode="require",
        connect_timeout=20,
    )


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    phase = sys.argv[1] if len(sys.argv) > 1 else "probe"
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    env = load_env()
    pw = subprocess.check_output(
        ["powershell", "-NoProfile", "-Command", PS], text=True
    ).strip()
    conn = connect(pw)
    cur = conn.cursor()
    report: dict = {"ts": stamp, "phase": phase}

    cur.execute(
        """
        select id::text from public.profiles
        where handle ilike %s or full_name ilike %s
        limit 1
        """,
        (f"%{HANDLE}%", f"%{HANDLE}%"),
    )
    row = cur.fetchone()
    if not row:
        print("NO_USER")
        return 2
    uid = row[0]
    report["user_id"] = uid

    # Prefer chat where user participates
    cur.execute(
        """
        select c.id::text
        from public.chats c
        where c.user_a = %s::uuid or c.user_b = %s::uuid
        order by coalesce(c.last_message_time, c.created_at) desc nulls last
        limit 1
        """,
        (uid, uid),
    )
    chat_row = cur.fetchone()
    chat_id = chat_row[0] if chat_row else None
    report["chat_id"] = chat_id

    cur.execute(
        """
        select id::text, length(token), left(token,4), app_version, platform,
               (token like 'ponto7_test_token_%%') as artificial
        from public.device_push_tokens
        where user_id = %s::uuid and revoked_at is null
        order by coalesce(last_seen_at, created_at) desc
        """,
        (uid,),
    )
    tokens = [
        {
            "id": r[0],
            "len": r[1],
            "prefix4": r[2],
            "app_version": r[3],
            "platform": r[4],
            "artificial": r[5],
        }
        for r in cur.fetchall()
    ]
    report["tokens"] = tokens
    print("tokens", json.dumps(tokens))

    if phase == "probe":
        # inbox recent + delivery
        cur.execute(
            """
            select id::text, kind, title, left(coalesce(body,''),60), created_at::text
            from public.user_notifications
            where user_id = %s::uuid
            order by created_at desc limit 8
            """,
            (uid,),
        )
        report["inbox"] = [
            {
                "id": r[0],
                "kind": r[1],
                "title": r[2],
                "body": r[3],
                "created_at": r[4],
            }
            for r in cur.fetchall()
        ]
        conn.close()
        path = OUT / f"fecho_{phase}_{stamp}.json"
        path.write_text(json.dumps(report, indent=2), encoding="utf-8")
        print("WROTE", path.name)
        return 0 if tokens and not any(t["artificial"] for t in tokens) else 20

    kind = "chat_message" if "chat" in phase else "price_offer_accepted"
    title = "Fleaber chat" if kind == "chat_message" else "Fleaber proposta"
    body = (
        "Nova mensagem na conversa"
        if kind == "chat_message"
        else "Proposta actualizada — toca para abrir"
    )
    mode = phase.split("_")[-1]
    dedupe = f"ponto7_fecho_{kind}_{mode}_{stamp}_{uuid.uuid4().hex[:6]}"
    cur.execute(
        """
        select public.batata_emit_user_notification_trusted(
          %s::uuid, %s, %s, %s,
          %s::uuid, null, null, null, %s
        )
        """,
        (uid, kind, title, body, chat_id, dedupe),
    )
    nid = str(cur.fetchone()[0])
    conn.commit()

    # dedupe check: second emit same key → same id
    if phase.endswith("_dedupe"):
        cur.execute(
            """
            select public.batata_emit_user_notification_trusted(
              %s::uuid, %s, %s, %s,
              %s::uuid, null, null, null, %s
            )
            """,
            (uid, kind, title, body, chat_id, dedupe),
        )
        nid2 = str(cur.fetchone()[0])
        conn.commit()
        report["dedupe_same"] = nid == nid2
        print("dedupe_same", nid == nid2, nid, nid2)

    code, body_j = http_json(
        FN,
        headers={
            "apikey": env["SUPABASE_SERVICE_ROLE_KEY"],
            "Authorization": f"Bearer {env['SUPABASE_SERVICE_ROLE_KEY']}",
        },
        body={"notification_id": nid},
    )
    safe = {
        k: v
        for k, v in (body_j.items() if isinstance(body_j, dict) else [])
        if k in ("ok", "notification_id", "push", "email", "error")
        or str(k).startswith("push")
    }
    time.sleep(1.2)
    cur.execute(
        """
        select channel, status, kind, left(coalesce(error_text,''),120)
        from public.notification_delivery_log
        where notification_id = %s::uuid
        order by created_at desc
        """,
        (nid,),
    )
    logs = [
        {"channel": r[0], "status": r[1], "kind": r[2], "error": r[3]}
        for r in cur.fetchall()
    ]
    report["dispatch"] = {
        "mode": mode,
        "kind": kind,
        "notification_id": nid,
        "chat_id": chat_id,
        "dedupe_key": dedupe,
        "http": code,
        "body": safe,
        "delivery_log": logs,
    }
    print("dispatch", json.dumps(report["dispatch"], default=str))
    conn.close()
    path = OUT / f"fecho_{phase}_{stamp}.json"
    path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("WROTE", path.name)
    ok = safe.get("push") == "sent" or any(
        x.get("status") == "sent" for x in logs
    )
    return 0 if ok else 30


if __name__ == "__main__":
    raise SystemExit(main())
