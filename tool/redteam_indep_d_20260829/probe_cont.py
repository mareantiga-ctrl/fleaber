#!/usr/bin/env python3
"""Continuation + Pass 2/3 of independent blind RT (staging only)."""
from __future__ import annotations

import json
import random
import string
import sys
import time
import traceback
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent
ENV_PATH = Path(__file__).resolve().parents[1] / "live_ops_staging.env"
BASE = "https://fxdknzrqjenzqcvnwqqq.supabase.co"
REST = BASE + "/rest/v1/"
AUTH = BASE + "/auth/v1/"
FN = BASE + "/functions/v1/"

matrix: list[dict[str, Any]] = []
findings: list[dict[str, Any]] = []
invariants: dict[str, Any] = {}
races: list[dict[str, Any]] = []
stripe_tests: list[dict[str, Any]] = []
gaps: list[str] = []
inventory: dict[str, Any] = {}
cleanup_ids: dict[str, list[str]] = {"products": [], "orders": []}


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


def clip(x: Any, n: int = 1000) -> str:
    s = x if isinstance(x, str) else json.dumps(x, ensure_ascii=False, default=str)
    return s if len(s) <= n else s[: n - 3] + "..."


def http(method, url, *, token=None, apikey=None, body=None, extra=None, timeout=45, prefer="return=representation", raw=None):
    headers = {"Accept": "application/json"}
    key = apikey or ANON
    headers["apikey"] = key
    headers["Authorization"] = f"Bearer {token or key}"
    if prefer:
        headers["Prefer"] = prefer
    if extra:
        headers.update(extra)
    data = raw
    if data is None and body is not None and method.upper() not in ("GET", "HEAD"):
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, headers=headers, method=method.upper())
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            rawb = resp.read().decode("utf-8", errors="replace")
            try:
                parsed = json.loads(rawb) if rawb else None
            except json.JSONDecodeError:
                parsed = rawb
            return {"ok": 200 <= resp.status < 300, "status": resp.status, "body": parsed, "raw": rawb[:4000], "ms": int((time.time() - t0) * 1000)}
    except urllib.error.HTTPError as e:
        rawb = e.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(rawb) if rawb else None
        except json.JSONDecodeError:
            parsed = rawb
        return {"ok": False, "status": e.code, "body": parsed, "raw": rawb[:4000], "ms": int((time.time() - t0) * 1000)}
    except Exception as e:
        return {"ok": False, "status": 0, "body": str(e), "raw": str(e), "ms": int((time.time() - t0) * 1000)}


def rest(token, method, path, **kw):
    svc = kw.pop("svc", False)
    tok = SVC if svc else token
    key = SVC if svc else ANON
    return http(method, REST + path.lstrip("/"), token=tok, apikey=key, **kw)


def rpc(token, name, params=None, svc=False):
    return rest(token, "POST", f"rpc/{name}", body=params or {}, svc=svc)


def fn(token, name, body=None, method="POST", qs=""):
    return http(method, FN + name + (("?" + qs) if qs else ""), token=token or ANON, apikey=ANON, body=body, prefer=None)


def rec(surface, attack, identity, result, impact, severity, evidence, finding=False, title=None, pre="", state="OPEN"):
    row = {"surface": surface, "attack": attack, "identity": identity, "result": result, "impact": impact, "severity": severity, "evidence": clip(evidence, 1400), "ts": now_iso()}
    matrix.append(row)
    if finding:
        findings.append({"id": f"D-{len(findings)+1:03d}", "severity": severity, "title": title or attack, "actor": identity, "preconditions": pre, "reproduction": attack, "impact": impact, "state": state, "evidence": clip(evidence, 2500), "surface": surface})


def persisted(resp) -> bool:
    b = resp.get("body")
    if isinstance(b, list) and b:
        return True
    if isinstance(b, dict) and b.get("id"):
        return True
    return False


def sign_in(email, password):
    r = http("POST", AUTH + "token?grant_type=password", token=ANON, body={"email": email, "password": password}, prefer=None)
    body = r.get("body") or {}
    if not isinstance(body, dict) or not body.get("access_token"):
        raise RuntimeError(clip(r))
    return {"jwt": body["access_token"], "id": body["user"]["id"], "email": email}


def observe_order(oid):
    r = rest(None, "GET", f"orders?id=eq.{oid}&select=*", svc=True, prefer=None)
    rows = r.get("body") if isinstance(r.get("body"), list) else []
    return rows[0] if rows else {}


def observe_product(pid):
    r = rest(None, "GET", f"products?id=eq.{pid}&select=id,title,price,quantity,seller_id,is_sold,list_on_marketplace", svc=True, prefer=None)
    rows = r.get("body") if isinstance(r.get("body"), list) else []
    return rows[0] if rows else {}


def observe_wallet(uid):
    r = rest(None, "GET", f"wallets?id=eq.{uid}&select=*", svc=True, prefer=None)
    rows = r.get("body") if isinstance(r.get("body"), list) else []
    return rows[0] if rows else {}


def create_product(seller_id, qty, price, title):
    r = rest(None, "POST", "products", svc=True, body={
        "seller_id": seller_id,
        "title": title,
        "price": price,
        "quantity": qty,
        "list_on_marketplace": True,
        "is_sold": False,
        "state": "Bom",
        "description": "rt-indep-d fixture",
        "category": "Outros",
    })
    b = r.get("body")
    if isinstance(b, list) and b:
        pid = b[0]["id"]
    elif isinstance(b, dict) and b.get("id"):
        pid = b["id"]
    else:
        raise RuntimeError("product insert " + clip(r))
    cleanup_ids["products"].append(pid)
    return pid


def oid_from(r):
    if not r.get("ok"):
        return None
    b = r.get("body")
    row = b[0] if isinstance(b, list) else b
    if row and row.get("id"):
        cleanup_ids["orders"].append(row["id"])
        return row["id"]
    return None


def dump():
    (ROOT / "probe_cont_raw.json").write_text(json.dumps({
        "project": "fxdknzrqjenzqcvnwqqq",
        "ts": now_iso(),
        "inventory": inventory,
        "matrix": matrix,
        "findings": findings,
        "invariants": invariants,
        "races": races,
        "stripe_tests": stripe_tests,
        "gaps": gaps,
        "cleanup_ids": cleanup_ids,
    }, ensure_ascii=False, indent=2, default=str), encoding="utf-8")


def main():
    global ANON, SVC
    env = load_env(ENV_PATH)
    ANON = env["SUPABASE_ANON_KEY"]
    SVC = env["SUPABASE_SERVICE_ROLE_KEY"]
    buyer = sign_in(env["LIVE_OPS_TEST_BUYER_EMAIL"], env["LIVE_OPS_TEST_BUYER_PASSWORD"])
    seller = sign_in(env["LIVE_OPS_TEST_SELLER_EMAIL"], env["LIVE_OPS_TEST_SELLER_PASSWORD"])
    try:
        buyer2 = sign_in("demo_bot_01@staging.fleaber.bot", "FleaberBotSim_Staging_2026!")
    except Exception:
        buyer2 = buyer
        gaps.append("buyer2 fallback")
    print(f"ids buyer={buyer['id']} seller={seller['id']} buyer2={buyer2['id']}", flush=True)

    # OpenAPI via service
    spec = http("GET", REST[:-1] + "/", token=SVC, extra={"Accept": "application/openapi+json"}, prefer=None)
    body = spec.get("body") if isinstance(spec.get("body"), dict) else {}
    rpcs, tables = [], []
    for p in (body.get("paths") or {}):
        if p.startswith("/rpc/"):
            rpcs.append(p.split("/")[-1])
        elif p.startswith("/") and "{" not in p and not p.startswith("/rpc"):
            tables.append(p.strip("/"))
    inventory.update({"openapi_http": spec["status"], "rpcs": sorted(set(rpcs)), "tables": sorted(set(tables)), "rpc_n": len(set(rpcs)), "table_n": len(set(tables))})
    rec("INVENTORY", "openapi service", "observe", f"http={spec['status']} tables={inventory['table_n']} rpcs={inventory['rpc_n']}", "map", "INFO", {"rpc_sample": rpcs[:60]})
    dump()
    print(f"openapi tables={inventory['table_n']} rpcs={inventory['rpc_n']}", flush=True)

    pid = create_product(seller["id"], 5, 5.00, f"RT-D {int(time.time())} cheap")
    pid1 = create_product(seller["id"], 1, 6.00, f"RT-D {int(time.time())} qty1")
    print(f"products {pid} {pid1}", flush=True)

    # --- credit wallet once (correct signature) ---
    w0 = observe_wallet(buyer["id"])
    credit = rpc(buyer["jwt"], "batata_credit_wallet_once", {
        "p_wallet_id": buyer["id"],
        "p_order_id": "00000000-0000-0000-0000-000000000123",
        "p_amount": 50,
        "p_type": "reembolso",
        "p_description": "rt-d mint",
    })
    w1 = observe_wallet(buyer["id"])
    minted = float(w1.get("balance") or 0) > float(w0.get("balance") or 0) + 0.01
    rec("WALLET", "buyer batata_credit_wallet_once correct args", "buyer",
        f"http={credit['status']} minted={minted} {w0.get('balance')}->{w1.get('balance')}",
        "JWT mint", "P0" if minted else "INFO", {"rpc": clip(credit.get("body")), "w0": w0, "w1": w1},
        finding=minted, title="Buyer minted wallet via batata_credit_wallet_once")
    invariants["E_jwt_mint_credit_once"] = minted

    debit = rpc(buyer["jwt"], "batata_debit_wallet_once", {
        "p_wallet_id": seller["id"],
        "p_order_id": "00000000-0000-0000-0000-000000000124",
        "p_amount": 1,
        "p_description": "rt-d steal",
    })
    rec("WALLET", "buyer batata_debit_wallet_once on seller", "buyer", f"http={debit['status']}", "steal", "P0" if debit["ok"] and debit.get("body") is True else "INFO", clip(debit.get("body")), finding=debit["ok"] and debit.get("body") is True)

    # --- anon order insert with real product ---
    anon_ins = rest(None, "POST", "orders", body={
        "product_id": pid, "buyer_id": buyer["id"], "seller_id": seller["id"],
        "price_total": 5, "status": "reserva_pendente", "quantity": 1,
        "payment_method": "Pagamento na App",
    }, prefer="return=representation")
    rec("RLS", "anon INSERT well-formed order", "anon", f"http={anon_ins['status']} persisted={persisted(anon_ins)}", "unauth order",
        "P1" if persisted(anon_ins) else "INFO", clip(anon_ins.get("body")), finding=persisted(anon_ins), title="Anon created a real order")

    # anon favorites with user_id
    fav = rest(None, "POST", "favorites", body={"user_id": buyer["id"], "product_id": pid})
    rec("RLS", "anon INSERT favorites with user_id", "anon", f"http={fav['status']} persisted={persisted(fav)}", "social write",
        "P2" if persisted(fav) else "INFO", clip(fav.get("body")), finding=persisted(fav))

    # follow with ids
    fol = rest(None, "POST", "follows", body={"follower_id": buyer["id"], "following_id": seller["id"]})
    rec("RLS", "anon INSERT follows with party ids", "anon", f"http={fol['status']} persisted={persisted(fol)}", "social write",
        "P2" if persisted(fol) else "INFO", clip(fol.get("body")), finding=persisted(fol))

    # --- buyer order insert hostile ---
    paid = rest(buyer["jwt"], "POST", "orders", body={
        "product_id": pid, "buyer_id": buyer["id"], "seller_id": seller["id"],
        "price_total": 0.01, "status": "pago", "quantity": 1,
        "amount_paid_cents": 999999, "stripe_payment_intent_id": "pi_rt_d",
        "contract_unit_cents": 1, "contract_qty": 1, "payment_method": "Pagamento na App",
    })
    paid_id = oid_from(paid)
    final = observe_order(paid_id) if paid_id else {}
    fake_paid = str(final.get("status") or "").lower() == "pago"
    rec("ORDERS", "buyer INSERT pago+amount_paid+pi", "buyer",
        f"http={paid['status']} status={final.get('status')} paid_cents={final.get('amount_paid_cents')} pi={final.get('stripe_payment_intent_id')}",
        "forged capture",
        "P0" if fake_paid and (final.get("amount_paid_cents") or final.get("stripe_payment_intent_id")) else ("P1" if fake_paid else "INFO"),
        final or clip(paid.get("body")),
        finding=fake_paid, title="Buyer inserted order already pago")

    if paid_id:
        rel = rpc(seller["jwt"], "batata_release_seller_wallet_for_order", {"p_order_id": paid_id})
        rec("WALLET", "release on JWT-forged pago", "seller", f"http={rel['status']} body={clip(rel.get('body'),120)}", "mint",
            "P0" if rel.get("body") is True else "INFO", clip(rel.get("body")), finding=rel.get("body") is True)

    xparty = rest(buyer["jwt"], "POST", "orders", body={
        "product_id": pid, "buyer_id": buyer2["id"], "seller_id": seller["id"],
        "price_total": 5, "status": "reserva_pendente", "quantity": 1, "payment_method": "Pagamento na App",
    })
    rec("AUTHORITY", "buyer INSERT as buyer2", "buyer", f"http={xparty['status']} persisted={persisted(xparty)}", "party swap",
        "P1" if persisted(xparty) else "INFO", clip(xparty.get("body")), finding=persisted(xparty))
    oid_from(xparty)

    for q, lab in [(0, "0"), (-1, "-1"), (10**6, "1e6")]:
        r = rest(buyer["jwt"], "POST", "orders", body={
            "product_id": pid1, "buyer_id": buyer["id"], "seller_id": seller["id"],
            "price_total": 6, "status": "reserva_pendente", "quantity": q, "payment_method": "Pagamento na App",
        })
        oid = oid_from(r)
        row = observe_order(oid) if oid else {}
        rec("QUANTITY", f"INSERT qty={lab} stock=1", "buyer", f"http={r['status']} qty={row.get('quantity')}", "capacity",
            "P1" if oid and int(row.get("quantity") or 0) > 1 else "INFO", row or clip(r.get("body")),
            finding=bool(oid and int(row.get("quantity") or 0) > 1))

    hold = rest(buyer["jwt"], "POST", "orders", body={
        "product_id": pid, "buyer_id": buyer["id"], "seller_id": seller["id"],
        "price_total": 5, "status": "reserva_pendente", "quantity": 1,
        "payment_method": "Pagamento na App", "shipping_method": "hand",
    })
    oid = oid_from(hold)
    rec("ORDERS", "buyer legit hold", "buyer", f"id={oid} http={hold['status']}", "fixture", "INFO", clip(hold.get("body")))
    dump()

    if oid:
        before = observe_order(oid)
        patches = [
            ("price_total", {"price_total": 0.01}),
            ("quantity", {"quantity": 99}),
            ("contract_unit_cents", {"contract_unit_cents": 1}),
            ("contract_qty", {"contract_qty": 99}),
            ("status_pago", {"status": "pago"}),
            ("status_concluido", {"status": "concluido"}),
            ("amount_paid_cents", {"amount_paid_cents": 1}),
            ("stripe_pi", {"stripe_payment_intent_id": "pi_patched"}),
            ("seller_swap", {"seller_id": buyer["id"]}),
            ("buyer_swap", {"buyer_id": buyer2["id"]}),
            ("product_swap", {"product_id": pid1}),
        ]
        for lab, data in patches:
            r = rest(buyer["jwt"], "PATCH", f"orders?id=eq.{oid}", body=data)
            after = observe_order(oid)
            changed = any(str(after.get(k)) != str(before.get(k)) for k in data)
            rows_ret = r.get("body") if isinstance(r.get("body"), list) else []
            rec("ORDERS", f"buyer PATCH {lab}", "buyer",
                f"http={r['status']} nret={len(rows_ret) if isinstance(rows_ret, list) else 'x'} changed={changed} val={ {k: after.get(k) for k in data} }",
                "authority",
                "P0" if changed and lab in ("status_pago", "amount_paid_cents", "stripe_pi", "seller_swap", "buyer_swap") else ("P1" if changed else "INFO"),
                {"before": {k: before.get(k) for k in data}, "after": {k: after.get(k) for k in data}},
                finding=changed, title=f"Buyer persisted PATCH {lab}")
            before = after

        # seller patch — require actual change
        b2 = observe_order(oid)
        r = rest(seller["jwt"], "PATCH", f"orders?id=eq.{oid}", body={"status": "pago", "price_total": 0.01})
        a2 = observe_order(oid)
        ch = str(a2.get("status")) != str(b2.get("status")) or str(a2.get("price_total")) != str(b2.get("price_total"))
        rec("ORDERS", "seller PATCH hold to pago/cheap", "seller", f"http={r['status']} changed={ch} status={a2.get('status')}", "fake payment",
            "P1" if ch and str(a2.get("status")).lower() == "pago" else "INFO", a2, finding=ch and str(a2.get("status")).lower() == "pago")

        r = rest(buyer2["jwt"], "PATCH", f"orders?id=eq.{oid}", body={"status": "pago"})
        a3 = observe_order(oid)
        rec("ORDERS", "buyer2 PATCH foreign order", "buyer2", f"http={r['status']} n={len(r.get('body') or []) if isinstance(r.get('body'), list) else 0} status={a3.get('status')}", "cross-user",
            "P1" if persisted(r) else "INFO", clip(r.get("body")), finding=persisted(r))

        # checkout attacks
        for lab, body in [
            ("underpay amount=50", {"order_id": oid, "buyer_id": buyer["id"], "amount": 50, "shipping_method": "hand", "product_id": pid}),
            ("prize", {"order_id": oid, "buyer_id": buyer["id"], "prize_shipping": True, "shipping_method": "carrier"}),
            ("qty99", {"order_id": oid, "buyer_id": buyer["id"], "quantity": 99, "shipping_method": "hand"}),
            ("seller swap", {"order_id": oid, "buyer_id": buyer["id"], "seller_id": buyer["id"], "shipping_method": "hand"}),
            ("buyer mismatch", {"order_id": oid, "buyer_id": seller["id"], "shipping_method": "hand"}),
            ("hand", {"order_id": oid, "buyer_id": buyer["id"], "shipping_method": "hand"}),
            ("carrier", {"order_id": oid, "buyer_id": buyer["id"], "shipping_method": "carrier"}),
            ("free shipping", {"order_id": oid, "buyer_id": buyer["id"], "shipping_method": "free"}),
            ("live inject", {"order_id": oid, "buyer_id": buyer["id"], "shipping_method": "hand", "live_id": "11111111-1111-1111-1111-111111111111"}),
        ]:
            r = fn(buyer["jwt"], "create-payment-intent", body)
            amt = r.get("body", {}).get("server_amount_cents") if isinstance(r.get("body"), dict) else None
            sid = r.get("body", {}).get("checkoutSessionId") if isinstance(r.get("body"), dict) else None
            rec("CHECKOUT", lab, "buyer", f"http={r['status']} amt={amt} sid={sid}", "price authority",
                "P0" if r["ok"] and lab.startswith("underpay") and amt is not None and amt <= 50 else "INFO",
                clip(r.get("body")), finding=bool(r["ok"] and lab.startswith("underpay") and amt is not None and amt <= 50))
            stripe_tests.append({"lab": lab, "http": r["status"], "amt": amt, "sid": sid, "ok": r["ok"]})
        # seller/anon checkout
        r = fn(seller["jwt"], "create-payment-intent", {"order_id": oid, "buyer_id": buyer["id"], "shipping_method": "hand"})
        rec("CHECKOUT", "seller pays buyer order", "seller", f"http={r['status']}", "party", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])
        r = fn(None, "create-payment-intent", {"order_id": oid, "buyer_id": buyer["id"], "shipping_method": "hand"})
        rec("CHECKOUT", "anon checkout", "anon", f"http={r['status']}", "unauth", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])
        r = fn(buyer["jwt"], "create-payment-intent", {"order_id": oid, "payment_intent_id": "pi_x"}, qs="fase2_e2e_settle=1")
        rec("CHECKOUT", "fase2 settle buyer jwt", "buyer", f"http={r['status']}", "privileged", "P0" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])
        r = fn(buyer["jwt"], "sec-fase2-e2e-oversell", {"buyer_id": buyer["id"], "seller_id": seller["id"]})
        rec("EDGE", "e2e-oversell buyer jwt", "buyer", f"http={r['status']}", "privileged pay", "P0" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])

        # catalog drop then checkout
        rest(None, "PATCH", f"products?id=eq.{pid}", body={"price": 0.50}, svc=True)
        r = fn(buyer["jwt"], "create-payment-intent", {"order_id": oid, "buyer_id": buyer["id"], "shipping_method": "hand"})
        amt = r.get("body", {}).get("server_amount_cents") if isinstance(r.get("body"), dict) else None
        cu = observe_order(oid).get("contract_unit_cents")
        rec("CONTRACT", "price drop after hold then checkout", "buyer", f"amt={amt} contract={cu}", "retro price",
            "P1" if r["ok"] and amt and cu and amt < int(cu) * 0.5 else "INFO", {"amt": amt, "contract": cu, "body": clip(r.get("body"))})
        rest(None, "PATCH", f"products?id=eq.{pid}", body={"price": 5.00}, svc=True)
        invariants["K_contract_vs_catalog"] = {"amt": amt, "contract_unit_cents": cu}

    dump()
    print("wallet writes...", flush=True)
    for ident, tok, uid in [("buyer", buyer["jwt"], buyer["id"]), ("seller", seller["jwt"], seller["id"])]:
        before = observe_wallet(uid)
        r = rest(tok, "PATCH", f"wallets?id=eq.{uid}", body={"balance": 9999.99})
        after = observe_wallet(uid)
        ch = float(after.get("balance") or 0) >= 9999
        rec("WALLET", f"{ident} PATCH balance", ident, f"http={r['status']} {before.get('balance')}->{after.get('balance')}", "direct mint",
            "P0" if ch else "INFO", after, finding=ch)
        r = rest(tok, "POST", "wallet_transactions", body={"wallet_id": uid, "amount": 12.34, "type": "venda", "description": "rt-d"})
        rec("WALLET", f"{ident} INSERT wallet_transactions", ident, f"http={r['status']} persisted={persisted(r)}", "ledger",
            "P1" if persisted(r) else "INFO", clip(r.get("body")), finding=persisted(r))

    r = rpc(buyer["jwt"], "batata_ensure_wallet", {"p_user_id": seller["id"]})
    rec("WALLET", "buyer ensure_wallet seller", "buyer", f"http={r['status']}", "cross", "INFO", clip(r.get("body")))
    if oid:
        r = rpc(buyer["jwt"], "batata_refund_buyer_wallet_for_order", {"p_order_id": oid})
        rec("WALLET", "buyer refund rpc on hold", "buyer", f"http={r['status']} body={clip(r.get('body'),80)}", "unearned",
            "P1" if r.get("body") is True else "INFO", clip(r.get("body")), finding=r.get("body") is True)
        r = rpc(buyer["jwt"], "batata_release_seller_wallet_for_order", {"p_order_id": oid})
        rec("WALLET", "buyer release seller wallet on hold", "buyer", f"http={r['status']}", "cross-role",
            "P1" if r.get("body") is True else "INFO", clip(r.get("body")), finding=r.get("body") is True)

    r = fn(buyer["jwt"], "create-connect-account", {"user_id": seller["id"], "amount": 100, "idempotency_key": "rt_d_xuser_payout_aaaa"})
    rec("PAYOUT", "buyer payout user_id=seller", "buyer", f"http={r['status']}", "identity swap",
        "P0" if r["ok"] and isinstance(r.get("body"), dict) and r["body"].get("success") else "INFO", clip(r.get("body")),
        finding=r["ok"] and isinstance(r.get("body"), dict) and r["body"].get("success"))
    r = fn(seller["jwt"], "create-connect-account", {"user_id": seller["id"], "amount": 99999999, "idempotency_key": "rt_d_huge_payout_bbbb"})
    rec("PAYOUT", "seller payout 999999.99", "seller", f"http={r['status']}", "over-balance", "INFO", clip(r.get("body")))

    # MB WAY mint
    mb = rest(buyer["jwt"], "POST", "orders", body={
        "product_id": pid, "buyer_id": buyer["id"], "seller_id": seller["id"],
        "price_total": 8, "status": "aguarda_confirmacao", "quantity": 1, "payment_method": "MB WAY",
    })
    mb_id = oid_from(mb)
    if mb_id:
        ws0 = observe_wallet(seller["id"])
        rest(seller["jwt"], "PATCH", f"orders?id=eq.{mb_id}", body={"status": "pago"})
        after = observe_order(mb_id)
        rel = rpc(seller["jwt"], "batata_release_seller_wallet_for_order", {"p_order_id": mb_id})
        ws1 = observe_wallet(seller["id"])
        minted = float(ws1.get("balance") or 0) > float(ws0.get("balance") or 0) + 0.01
        rec("WALLET", "MB WAY seller pago then release", "seller",
            f"status={after.get('status')} release={clip(rel.get('body'),80)} bal {ws0.get('balance')}->{ws1.get('balance')}",
            "off-platform mint", "P0" if minted else "INFO",
            {"order": after, "rpc": clip(rel.get("body")), "w0": ws0, "w1": ws1}, finding=minted,
            title="Off-platform pago minted seller wallet")
        invariants["F_offplatform_mint"] = minted

    dump()
    print("stock races...", flush=True)
    payload = {"product_id": pid1, "buyer_id": buyer["id"], "seller_id": seller["id"], "price_total": 6, "status": "reserva_pendente", "quantity": 1, "payment_method": "Pagamento na App"}
    results = []
    with ThreadPoolExecutor(8) as ex:
        futs = [ex.submit(rest, buyer["jwt"], "POST", "orders", **{"body": payload}) for _ in range(8)]
        for f in as_completed(futs):
            results.append(f.result())
    n_ok = 0
    for r in results:
        i = oid_from(r)
        if i:
            n_ok += 1
    prod = observe_product(pid1)
    races.append({"name": "8 holds stock=1", "accepted": n_ok, "product": prod})
    rec("STOCK", "8 concurrent holds stock=1", "buyer", f"accepted={n_ok} qty={prod.get('quantity')}", "oversell holds", "P2" if n_ok > 1 else "INFO", {"n": n_ok, "product": prod})

    r = rest(buyer["jwt"], "PATCH", f"products?id=eq.{pid1}", body={"quantity": 999, "price": 0.01})
    after = observe_product(pid1)
    rec("CATALOG", "buyer PATCH seller product", "buyer", f"http={r['status']} qty={after.get('quantity')} price={after.get('price')} n={len(r.get('body') or []) if isinstance(r.get('body'), list) else 0}",
        "catalog hijack", "P1" if persisted(r) and (int(after.get("quantity") or 0) == 999 or float(after.get("price") or 9) < 1) else "INFO", after,
        finding=persisted(r) and (int(after.get("quantity") or 0) == 999 or float(after.get("price") or 9) < 1))

    # reviews
    r1 = rest(buyer["jwt"], "POST", "reviews", body={"target_id": seller["id"], "buyer_id": buyer["id"], "stars": 1, "comment": "rt-d", "target_type": "seller", "order_id": oid})
    r2 = rest(buyer["jwt"], "POST", "reviews", body={"target_id": seller["id"], "buyer_id": buyer2["id"], "stars": 5, "comment": "forged", "target_type": "seller"})
    rec("REVIEWS", "insert own without completed trade", "buyer", f"http={r1['status']} persisted={persisted(r1)}", "rep", "P1" if persisted(r1) else "INFO", clip(r1.get("body")), finding=persisted(r1))
    rec("REVIEWS", "insert as buyer2 identity", "buyer", f"http={r2['status']} persisted={persisted(r2)}", "identity", "P1" if persisted(r2) else "INFO", clip(r2.get("body")), finding=persisted(r2))
    rvs = []
    with ThreadPoolExecutor(6) as ex:
        for i in range(6):
            rvs.append(ex.submit(rest, buyer["jwt"], "POST", "reviews", **{"body": {"target_id": seller["id"], "buyer_id": buyer["id"], "stars": 5, "comment": f"race{i}", "target_type": "seller"}}))
        rvs = [f.result() for f in rvs]
    ok_n = sum(1 for x in rvs if persisted(x))
    rec("REVIEWS", "6 concurrent reviews", "buyer", f"ok={ok_n}", "dup", "P1" if ok_n > 1 else "INFO", [x["status"] for x in rvs], finding=ok_n > 1)

    # privacy
    chats = rest(buyer["jwt"], "GET", "chats?select=id,user_a,user_b&limit=30", prefer=None)
    rows = chats.get("body") if isinstance(chats.get("body"), list) else []
    foreign = [c for c in rows if buyer["id"] not in (c.get("user_a"), c.get("user_b"))]
    rec("CHAT", "SELECT chats", "buyer", f"n={len(rows)} foreign={len(foreign)}", "leak", "P1" if foreign else "INFO", clip(rows[:3]), finding=bool(foreign))
    msgs = rest(buyer["jwt"], "GET", "chat_messages?select=id,chat_id,sender_id,text&limit=5", prefer=None)
    mrows = msgs.get("body") if isinstance(msgs.get("body"), list) else []
    rec("CHAT", "SELECT chat_messages limit 5", "buyer", f"http={msgs['status']} n={len(mrows)}", "message leak", "P1" if mrows and any(x.get("sender_id") not in (buyer["id"],) for x in mrows) else "INFO", clip(mrows[:2]))

    disp = rest(buyer["jwt"], "GET", "order_disputes?select=id,buyer_id,seller_id,status,order_id&limit=10", prefer=None)
    drows = disp.get("body") if isinstance(disp.get("body"), list) else []
    fd = [d for d in drows if buyer["id"] not in (d.get("buyer_id"), d.get("seller_id"))]
    rec("DISPUTES", "SELECT disputes", "buyer", f"n={len(drows)} foreign={len(fd)}", "leak", "P1" if fd else "INFO", clip(drows[:2]), finding=bool(fd))

    lives = rest(buyer["jwt"], "GET", "lives?select=id,seller_id,mux_stream_key,stream_key,status&limit=8", prefer=None)
    lrows = lives.get("body") if isinstance(lives.get("body"), list) else []
    leak = any(str(x.get("mux_stream_key") or x.get("stream_key") or "").strip() for x in lrows)
    rec("LIVE", "SELECT stream keys", "buyer", f"n={len(lrows)} leak={leak}", "keys", "P1" if leak else "INFO", clip(lrows[:2]), finding=leak)
    lid = lrows[0]["id"] if lrows else None

    # storage
    url = BASE + f"/storage/v1/object/chat_media/chat_uploads/{seller['id']}/rt_d_{int(time.time())}.txt"
    req = urllib.request.Request(url, data=b"rt-indep-d", method="POST", headers={"Authorization": f"Bearer {buyer['jwt']}", "apikey": ANON, "Content-Type": "text/plain", "x-upsert": "true"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            st, raw = resp.status, resp.read()[:200]
    except urllib.error.HTTPError as e:
        st, raw = e.code, e.read()[:200]
    except Exception as e:
        st, raw = 0, str(e).encode()
    rec("STORAGE", "POST into seller chat_uploads prefix", "buyer", f"http={st}", "cross storage", "P1" if st in (200, 201) else "INFO", clip(raw.decode("utf-8", "replace") if isinstance(raw, (bytes, bytearray)) else raw), finding=st in (200, 201))

    dump()
    print("edges + rpcs...", flush=True)
    r = fn(buyer["jwt"], "refund-order", {"order_id": oid or "00000000-0000-0000-0000-000000000001"})
    rec("REFUNDS", "buyer refund-order", "buyer", f"http={r['status']}", "authz", "P1" if r["ok"] and isinstance(r.get("body"), dict) and r["body"].get("ok") else "INFO", clip(r.get("body")), finding=r["ok"] and isinstance(r.get("body"), dict) and r["body"].get("ok") is True)
    r = http("POST", FN + "stripe-webhook", token=ANON, body={"type": "checkout.session.completed"}, prefer=None)
    rec("WEBHOOK", "no signature", "anon", f"http={r['status']}", "forged settle", "P0" if r["ok"] and isinstance(r.get("body"), dict) and r["body"].get("ok") else "INFO", clip(r.get("body")), finding=r["ok"] and isinstance(r.get("body"), dict) and r["body"].get("ok") is True)
    r = fn(buyer["jwt"], "create-mux-live", {"title": "hostile rt d live xx"})
    rec("MUX", "buyer create-mux-live", "buyer", f"http={r['status']}", "cost", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])
    if lid:
        r = fn(buyer["jwt"], "complete-mux-live", {"live_id": lid})
        rec("MUX", "buyer complete foreign live", "buyer", f"http={r['status']}", "hijack", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])
        r = fn(buyer["jwt"], "livekit-mux-publish", {"step": "token", "live_id": lid})
        rec("LIVEKIT", "buyer token foreign", "buyer", f"http={r['status']}", "publish", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])
    r = fn(buyer["jwt"], "create-live-tip-checkout", {"seller_id": seller["id"], "amount_eur": 1, "tip_id": "00000000-0000-0000-0000-000000000042"})
    rec("TIPS", "client tip_id", "buyer", f"http={r['status']}", "confusion", "P1" if r["ok"] else "INFO", clip(r.get("body")))
    r = fn(buyer["jwt"], "create-live-tip-checkout", {"seller_id": seller["id"], "amount_eur": 1})
    rec("TIPS", "legit 1eur tip session", "buyer", f"http={r['status']} amt={(r.get('body') or {}).get('server_amount_cents') if isinstance(r.get('body'), dict) else None}", "tip", "INFO", clip(r.get("body")))
    r = fn(buyer["jwt"], "delete-test-account", {"confirm": "APAGAR TUDO"})
    rec("AUTH", "delete-test-account", "buyer", f"http={r['status']}", "nuke", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])
    r = fn(None, "ingest-ocr-reservation", {"live_id": lid or "x", "ocr_line_hash": "abcdefghij", "detected_at": now_iso(), "requested_qty": 99})
    rec("PS/OCR", "ingest no token", "anon", f"http={r['status']}", "fake res", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])
    r = fn(None, "ps-pairing-claim", {"code": "000000", "device_id": "rt-d"})
    rec("PS/OCR", "pairing 000000", "anon", f"http={r['status']}", "claim", "INFO", clip(r.get("body")))
    r = fn(buyer["jwt"], "livekit-egress-cleanup", {})
    rec("LIVEKIT", "cleanup as buyer", "buyer", f"http={r['status']}", "stop", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])
    r = fn(None, "send-sms-bulkgate", {"phone": "+351912345678"})
    rec("SMS", "anon sms hook", "anon", f"http={r['status']}", "pump", "P1" if r["ok"] and r["status"] not in (401, 400) else "INFO", clip(r.get("body")))
    r = rpc(buyer["jwt"], "batata_seller_direct_payment_details", {"p_seller_id": seller["id"]})
    leaked = False
    if r["ok"] and r.get("body"):
        s = json.dumps(r["body"])
        leaked = ("iban" in s.lower() or "mb" in s.lower()) and any(c.isdigit() for c in s)
    rec("PRIVACY", "seller_direct_payment_details", "buyer", f"http={r['status']} leaked={leaked}", "banking", "P1" if leaked else "INFO", clip(r.get("body")), finding=leaked)
    r = rpc(buyer["jwt"], "batata_process_partial_refund_dispute", {"p_order_id": oid} if oid else {})
    rec("REFUNDS", "buyer partial refund dispute rpc", "buyer", f"http={r['status']}", "refund", "P1" if r["ok"] and r.get("body") not in (None, False) else "INFO", clip(r.get("body")))
    r = rpc(buyer["jwt"], "batata_admin_resolve_dispute", {"p_dispute_id": "00000000-0000-0000-0000-000000000001"})
    rec("DISPUTES", "buyer admin_resolve_dispute", "buyer", f"http={r['status']}", "admin", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"] and not (isinstance(r.get("body"), dict) and "negado" in json.dumps(r.get("body")).lower()))
    r = rpc(buyer["jwt"], "batata_draw_live_raffle_winners", {})
    rec("RAFFLES", "buyer draw winners", "buyer", f"http={r['status']}", "raffle", "P1" if r["ok"] else "INFO", clip(r.get("body")))
    r = rpc(buyer["jwt"], "batata_find_user_id_by_email", {"p_email": env["LIVE_OPS_TEST_SELLER_EMAIL"]})
    rec("PRIVACY", "find_user_id_by_email", "buyer", f"http={r['status']}", "enum", "P2" if r["ok"] else "INFO", clip(r.get("body")))
    r = rpc(buyer["jwt"], "batata_director_activate_kill_switch", {})
    rec("LIVE", "buyer director kill switch", "buyer", f"http={r['status']}", "DoS lives", "P1" if r["ok"] else "INFO", clip(r.get("body")), finding=r["ok"])
    r = rest(buyer["jwt"], "POST", "live_raffle_winners", body={"user_id": buyer["id"]})
    rec("RAFFLES", "INSERT winners", "buyer", f"http={r['status']} persisted={persisted(r)}", "self-win", "P1" if persisted(r) else "INFO", clip(r.get("body")), finding=persisted(r))
    prize = rest(buyer["jwt"], "POST", "orders", body={
        "product_id": pid, "buyer_id": buyer["id"], "seller_id": seller["id"],
        "price_total": 0, "status": "premio_rifa", "quantity": 1, "payment_method": "premio_rifa",
    })
    prid = oid_from(prize)
    rec("RAFFLES", "INSERT premio_rifa", "buyer", f"http={prize['status']} id={prid}", "fake prize", "P1" if prid else "INFO", clip(prize.get("body")), finding=bool(prid))
    if prid:
        c = fn(buyer["jwt"], "create-payment-intent", {"order_id": prid, "buyer_id": buyer["id"], "prize_shipping": True, "shipping_method": "carrier"})
        rec("RAFFLES", "checkout prize on forged premio_rifa", "buyer", f"http={c['status']}", "ports-only fraud", "P1" if c["ok"] else "INFO", clip(c.get("body")), finding=c["ok"])

    dump()
    print("composition + races...", flush=True)
    p2 = create_product(seller["id"], 1, 7.0, f"RT-D bagB {int(time.time())}")
    o1 = oid_from(rest(buyer["jwt"], "POST", "orders", body={"product_id": pid, "buyer_id": buyer["id"], "seller_id": seller["id"], "price_total": 5, "status": "reserva_pendente", "quantity": 1, "payment_method": "Pagamento na App", "shipping_method": "hand"}))
    o2 = oid_from(rest(buyer["jwt"], "POST", "orders", body={"product_id": p2, "buyer_id": buyer["id"], "seller_id": seller["id"], "price_total": 7, "status": "reserva_pendente", "quantity": 1, "payment_method": "Pagamento na App", "shipping_method": "hand"}))
    if o1 and o2:
        r = fn(buyer["jwt"], "create-payment-intent", {
            "buyer_id": buyer["id"], "order_id": o1, "bag_checkout": True, "shipping_method": "hand",
            "bag_lines": [{"order_id": o1, "line_total_cents": 1}, {"order_id": o2, "line_total_cents": 1}],
        })
        amt = r.get("body", {}).get("server_amount_cents") if isinstance(r.get("body"), dict) else None
        rec("COMPOSITION", "bag two SKUs line_total=1c", "buyer", f"http={r['status']} amt={amt}", "underpay",
            "P0" if r["ok"] and amt is not None and amt < 500 else "INFO", clip(r.get("body")),
            finding=bool(r["ok"] and amt is not None and amt < 500))
        stripe_tests.append({"lab": "bag_two_sku", "amt": amt, "http": r["status"]})

    if oid:
        def ck(_):
            return fn(buyer["jwt"], "create-payment-intent", {"order_id": oid, "buyer_id": buyer["id"], "shipping_method": "hand"})
        outs = []
        with ThreadPoolExecutor(6) as ex:
            outs = [f.result() for f in as_completed([ex.submit(ck, i) for i in range(6)])]
        sessions = [x.get("body", {}).get("checkoutSessionId") for x in outs if isinstance(x.get("body"), dict) and x["body"].get("checkoutSessionId")]
        races.append({"name": "6 checkout sessions", "n": len(sessions), "ids": sessions})
        rec("CHECKOUT", "6 concurrent sessions same order", "buyer", f"created={len(sessions)}", "double session window", "P2" if len(sessions) > 1 else "INFO", sessions)
        stripe_tests.append({"lab": "concurrent_sessions", "n": len(sessions)})

        refs = []
        with ThreadPoolExecutor(4) as ex:
            refs = [f.result() for f in as_completed([ex.submit(fn, seller["jwt"], "refund-order", {"order_id": oid}) for _ in range(4)])]
        rec("REFUNDS", "4 concurrent refund on hold", "seller", f"st={[x['status'] for x in refs]}", "dup", "INFO", [clip(x.get("body"), 100) for x in refs])

    key = "rt_d_same_" + "".join(random.choices(string.ascii_lowercase, k=10))
    same, diff = [], []
    with ThreadPoolExecutor(4) as ex:
        same = [f.result() for f in as_completed([ex.submit(fn, seller["jwt"], "create-connect-account", {"user_id": seller["id"], "amount": 100, "idempotency_key": key}) for _ in range(4)])]
        diff = [f.result() for f in as_completed([ex.submit(fn, seller["jwt"], "create-connect-account", {"user_id": seller["id"], "amount": 100, "idempotency_key": f"{key}_{i}"}) for i in range(4)])]
    rec("PAYOUT", "4 same idempotency key", "seller", f"st={[x['status'] for x in same]}", "dup transfer", "INFO", [clip(x.get("body"), 140) for x in same])
    rec("PAYOUT", "4 different keys", "seller", f"st={[x['status'] for x in diff]}", "multi transfer", "INFO", [clip(x.get("body"), 140) for x in diff])
    races.append({"same_key": [clip(x.get("body"), 140) for x in same], "diff_key": [clip(x.get("body"), 140) for x in diff]})

    # RPC interesting from inventory
    interesting = [n for n in (inventory.get("rpcs") or []) if any(k in n.lower() for k in ("wallet", "payout", "credit", "refund", "admin", "nuke", "release", "settle", "winner", "iban"))]
    inventory["rpc_interesting"] = interesting
    for n in interesting[:50]:
        r = rpc(buyer["jwt"], n, {})
        rec("RPC", f"buyer empty {n}", "buyer", f"http={r['status']}", "enum", "INFO", clip(r.get("body"), 180))

    # offer self-accept
    r = rest(buyer["jwt"], "POST", "product_offers", body={"product_id": pid, "buyer_id": buyer["id"], "seller_id": seller["id"], "amount": 0.5, "status": "accepted"})
    rec("OFFERS", "buyer INSERT accepted 0.50", "buyer", f"http={r['status']} persisted={persisted(r)}", "self-accept", "P2" if persisted(r) else "INFO", clip(r.get("body")))

    if oid:
        r = rest(buyer["jwt"], "POST", "order_disputes", body={"order_id": oid, "buyer_id": buyer["id"], "seller_id": seller["id"], "status": "aberta", "reason": "rt-d"})
        rec("DISPUTES", "INSERT dispute on hold", "buyer", f"http={r['status']} persisted={persisted(r)}", "dispute unpaid", "P2" if persisted(r) else "INFO", clip(r.get("body")))

    # profiles iban as buyer
    r = rest(buyer["jwt"], "GET", f"profiles?id=eq.{seller['id']}&select=id,iban,mb_way,phone,user_type", prefer=None)
    rec("PRIVACY", "buyer SELECT seller iban/mb_way", "buyer", f"http={r['status']}", "banking cols", "P1" if r["ok"] and isinstance(r.get("body"), list) and r["body"] and (r["body"][0].get("iban") or r["body"][0].get("mb_way")) else "INFO", clip(r.get("body")),
        finding=bool(r["ok"] and isinstance(r.get("body"), list) and r["body"] and (r["body"][0].get("iban") or r["body"][0].get("mb_way"))))

    dump()
    print("cleanup...", flush=True)
    for p in cleanup_ids["products"]:
        rest(None, "PATCH", f"products?id=eq.{p}", body={"list_on_marketplace": False}, svc=True)
    for o in cleanup_ids["orders"]:
        rest(None, "PATCH", f"orders?id=eq.{o}", body={"status": "cancelado"}, svc=True)
    dump()
    print("FINDINGS", json.dumps([{"id": f["id"], "sev": f["severity"], "title": f["title"]} for f in findings], indent=2), flush=True)
    print(f"DONE matrix={len(matrix)} findings={len(findings)}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        traceback.print_exc()
        dump()
        sys.exit(1)
