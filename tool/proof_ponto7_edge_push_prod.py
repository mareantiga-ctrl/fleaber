#!/usr/bin/env python3
"""Ponto 7 Edge PROD — prova push FCM (sem imprimir secrets).

Fluxo:
1) AuthZ smoke (sem JWT → 401)
2) Contar tokens seller
3) Emit trusted chat_message + price_offer_*
4) Invoke notify-dispatch com service_role
5) Ler notification_delivery_log (status only)

Nunca escreve tokens FCM, chaves ou PEM em disco de relatório.
"""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = ROOT / "tool" / "live_ops_production.env"
OUT_DIR = ROOT / "tool" / "reports" / "ponto7_edge_prod_20261030"
SELLER_ID = "ee7dbdb2-d2e1-4538-800f-7546d72f064a"
REF = "bpmpkzwnrbmuqnhgdscf"
FN_URL = f"https://{REF}.supabase.co/functions/v1/notify-dispatch"


def load_env(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not path.is_file():
        return out
    for line in path.read_text(encoding="utf-8").splitlines():
        t = line.strip()
        if not t or t.startswith("#") or "=" not in t:
            continue
        k, v = t.split("=", 1)
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def http_json(
    url: str,
    *,
    method: str = "GET",
    headers: dict[str, str] | None = None,
    body: dict | None = None,
    timeout: float = 45,
) -> tuple[int, dict | list | str]:
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
            parsed: dict | list | str = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            parsed = raw[:500]
        return e.code, parsed


def rest(
    env: dict[str, str],
    path: str,
    *,
    method: str = "GET",
    body: dict | None = None,
    prefer: str | None = None,
) -> tuple[int, dict | list | str]:
    url = env["SUPABASE_URL"].rstrip("/") + path
    headers = {
        "apikey": env["SUPABASE_SERVICE_ROLE_KEY"],
        "Authorization": f"Bearer {env['SUPABASE_SERVICE_ROLE_KEY']}",
    }
    if prefer:
        headers["Prefer"] = prefer
    return http_json(url, method=method, headers=headers, body=body)


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    env = load_env(ENV_PATH)
    for need in ("SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_ANON_KEY"):
        if need not in env or len(env[need]) < 20:
            print(f"MISSING_ENV:{need}")
            return 2

    report: dict = {
        "ts": stamp,
        "project_ref": REF,
        "seller_id": SELLER_ID,
        "edge": "notify-dispatch",
        "steps": {},
    }

    # 1) unauthorized
    code, body = http_json(
        FN_URL,
        method="POST",
        headers={"Content-Type": "application/json", "apikey": env["SUPABASE_ANON_KEY"]},
        body={"notification_id": "00000000-0000-0000-0000-000000000001"},
    )
    report["steps"]["unauth"] = {
        "http": code,
        "error": (body.get("error") if isinstance(body, dict) else str(body)[:120]),
        "pass": code == 401
        and isinstance(body, dict)
        and body.get("error") == "unauthorized",
    }
    print("unauth:", report["steps"]["unauth"])

    # 2) tokens
    code, tokens = rest(
        env,
        f"/rest/v1/device_push_tokens?user_id=eq.{SELLER_ID}&revoked_at=is.null&select=id,platform,created_at,updated_at",
    )
    token_rows = tokens if isinstance(tokens, list) else []
    report["steps"]["tokens"] = {
        "http": code,
        "count": len(token_rows),
        "platforms": sorted({str(r.get("platform")) for r in token_rows}),
        "ids": [str(r.get("id")) for r in token_rows][:5],
    }
    print("tokens:", report["steps"]["tokens"])

    # 3+4 emit + dispatch for chat + offer
    cases = [
        ("chat_message", "Ponto7 chat push", "Mensagem de teste chat"),
        ("price_offer_accepted", "Ponto7 proposta", "Proposta aceite (teste)"),
    ]
    case_results = []
    for kind, title, body_txt in cases:
        dedupe = f"ponto7_edge_push_{kind}_{stamp}"
        code, rpc = rest(
            env,
            "/rest/v1/rpc/batata_emit_user_notification_trusted",
            method="POST",
            body={
                "p_recipient_id": SELLER_ID,
                "p_kind": kind,
                "p_title": title,
                "p_body": body_txt,
                "p_chat_id": None,
                "p_product_id": None,
                "p_offer_id": None,
                "p_actor_id": None,
                "p_dedupe_key": dedupe,
            },
        )
        nid = rpc if isinstance(rpc, str) else (rpc.get("id") if isinstance(rpc, dict) else None)
        if isinstance(rpc, str) and rpc.startswith('"') and rpc.endswith('"'):
            nid = json.loads(rpc)
        entry = {
            "kind": kind,
            "dedupe_key": dedupe,
            "emit_http": code,
            "notification_id": nid,
        }
        if not nid:
            entry["emit_body"] = str(rpc)[:200]
            entry["dispatch"] = None
            case_results.append(entry)
            print("emit_fail:", entry)
            continue

        d_code, d_body = http_json(
            FN_URL,
            method="POST",
            headers={
                "Content-Type": "application/json",
                "apikey": env["SUPABASE_SERVICE_ROLE_KEY"],
                "Authorization": f"Bearer {env['SUPABASE_SERVICE_ROLE_KEY']}",
            },
            body={"notification_id": nid},
        )
        entry["dispatch_http"] = d_code
        if isinstance(d_body, dict):
            # strip any accidental token fields
            safe = {
                k: v
                for k, v in d_body.items()
                if k
                in (
                    "ok",
                    "notification_id",
                    "push",
                    "email",
                    "error",
                    "push_ok",
                    "push_failed",
                )
                or k.startswith("push")
            }
            entry["dispatch"] = safe
        else:
            entry["dispatch"] = str(d_body)[:200]
        case_results.append(entry)
        print("case:", json.dumps(entry, default=str))

        time.sleep(1.2)

    report["steps"]["cases"] = case_results

    # 5) delivery log (no tokens)
    code, logs = rest(
        env,
        f"/rest/v1/notification_delivery_log?user_id=eq.{SELLER_ID}&order=created_at.desc&limit=8&select=id,channel,kind,status,error_text,dedupe_key,created_at",
    )
    log_rows = logs if isinstance(logs, list) else []
    # redact long error bodies that might contain FCM payloads
    safe_logs = []
    for r in log_rows:
        err = r.get("error_text")
        if isinstance(err, str) and len(err) > 180:
            err = err[:180] + "…"
        safe_logs.append(
            {
                "id": r.get("id"),
                "channel": r.get("channel"),
                "kind": r.get("kind"),
                "status": r.get("status"),
                "error_text": err,
                "dedupe_key": r.get("dedupe_key"),
                "created_at": r.get("created_at"),
            }
        )
    report["steps"]["delivery_log"] = {"http": code, "rows": safe_logs}

    push_sent = any(r.get("status") == "sent" and r.get("channel") == "push" for r in safe_logs)
    push_statuses = [
        (c.get("dispatch") or {}).get("push")
        for c in case_results
        if isinstance(c.get("dispatch"), dict)
    ]
    report["verdict"] = {
        "unauth_401": report["steps"]["unauth"]["pass"],
        "token_count": report["steps"]["tokens"]["count"],
        "dispatch_push_statuses": push_statuses,
        "delivery_log_has_sent": push_sent,
        "pass_edge_authz": report["steps"]["unauth"]["pass"],
        "pass_real_push": push_sent
        or any(s == "sent" or s is True for s in push_statuses),
    }

    out = OUT_DIR / f"edge_push_proof_{stamp}.json"
    out.write_text(json.dumps(report, indent=2, default=str), encoding="utf-8")
    print("WROTE", out.name)
    print("VERDICT", json.dumps(report["verdict"]))
    if not report["verdict"]["pass_edge_authz"]:
        return 10
    if report["steps"]["tokens"]["count"] == 0:
        print("NEED_TOKEN: open seller app once on TCL after notification permission")
        return 20
    if not report["verdict"]["pass_real_push"]:
        return 30
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
