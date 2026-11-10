#!/usr/bin/env python3
"""Pass 3 follow-ups: Stripe TEST captures, live_id inject, sequential payouts, RPCs."""
from __future__ import annotations

import json
import time
import urllib.error
import urllib.request
from pathlib import Path

ENV_PATH = Path(__file__).resolve().parents[1] / "live_ops_staging.env"
BASE = "https://fxdknzrqjenzqcvnwqqq.supabase.co"
REST = BASE + "/rest/v1/"
AUTH = BASE + "/auth/v1/"
FN = BASE + "/functions/v1/"
OUT = Path(__file__).resolve().parent / "probe_pass3.json"


def load_env():
    e = {}
    for line in ENV_PATH.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        e[k.strip()] = v.strip()
    return e


def http(method, url, token=None, apikey=None, body=None, prefer="return=representation"):
    headers = {"Accept": "application/json", "Content-Type": "application/json"}
    key = apikey or ANON
    headers["apikey"] = key
    headers["Authorization"] = f"Bearer {token or key}"
    if prefer:
        headers["Prefer"] = prefer
    data = json.dumps(body).encode() if body is not None and method != "GET" else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            try:
                parsed = json.loads(raw) if raw else None
            except json.JSONDecodeError:
                parsed = raw
            return {"ok": True, "status": resp.status, "body": parsed, "raw": raw[:3000]}
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            parsed = raw
        return {"ok": False, "status": e.code, "body": parsed, "raw": raw[:3000]}


def rest(token, method, path, **kw):
    svc = kw.pop("svc", False)
    return http(method, REST + path, token=SVC if svc else token, apikey=SVC if svc else ANON, **kw)


def rpc(token, name, params=None, svc=False):
    return rest(token, "POST", f"rpc/{name}", body=params or {}, svc=svc)


def fn(token, name, body=None, qs=""):
    return http("POST" if body is not None else "GET", FN + name + (("?" + qs) if qs else ""), token=token or ANON, apikey=ANON, body=body, prefer=None)


def sign_in(email, pw):
    r = http("POST", AUTH + "token?grant_type=password", token=ANON, body={"email": email, "password": pw}, prefer=None)
    return {"jwt": r["body"]["access_token"], "id": r["body"]["user"]["id"]}


def row(r):
    b = r.get("body")
    if isinstance(b, list) and b:
        return b[0]
    if isinstance(b, dict):
        return b
    return {}


def observe(table, oid):
    r = rest(None, "GET", f"{table}?id=eq.{oid}&select=*", svc=True, prefer=None)
    return row(r)


def create_product(seller_id, qty, price, title):
    r = rest(None, "POST", "products", svc=True, body={
        "seller_id": seller_id, "title": title, "price": price, "quantity": qty,
        "list_on_marketplace": True, "is_sold": False, "state": "Bom", "category": "Outros",
        "description": "rt-d p3",
    })
    return row(r)["id"]


def main():
    global ANON, SVC
    env = load_env()
    ANON, SVC = env["SUPABASE_ANON_KEY"], env["SUPABASE_SERVICE_ROLE_KEY"]
    buyer = sign_in(env["LIVE_OPS_TEST_BUYER_EMAIL"], env["LIVE_OPS_TEST_BUYER_PASSWORD"])
    seller = sign_in(env["LIVE_OPS_TEST_SELLER_EMAIL"], env["LIVE_OPS_TEST_SELLER_PASSWORD"])
    out = {"ts": time.time(), "tests": []}

    def rec(name, **k):
        out["tests"].append({"name": name, **k})
        print(name, {x: k[x] for x in k if x != "evidence"}, flush=True)

    # hostile 0.01 order contract + checkout
    p = create_product(seller["id"], 3, 8.00, f"RT-D p3 price {int(time.time())}")
    ins = rest(buyer["jwt"], "POST", "orders", body={
        "product_id": p, "buyer_id": buyer["id"], "seller_id": seller["id"],
        "price_total": 0.01, "status": "pago", "quantity": 1,
        "amount_paid_cents": 1, "stripe_payment_intent_id": "pi_fake",
        "payment_method": "Pagamento na App", "shipping_method": "hand",
    })
    oid_h = row(ins).get("id")
    oh = observe("orders", oid_h) if oid_h else {}
    ck = fn(buyer["jwt"], "create-payment-intent", {"order_id": oid_h, "buyer_id": buyer["id"], "shipping_method": "hand", "amount": 50})
    rec("hostile_001_insert_checkout",
        insert_http=ins["status"], persisted_status=oh.get("status"), price_total=oh.get("price_total"),
        contract_unit=oh.get("contract_unit_cents"), contract_qty=oh.get("contract_qty"),
        amount_paid=oh.get("amount_paid_cents"), pi=oh.get("stripe_payment_intent_id"),
        checkout_http=ck["status"], checkout_amt=(ck.get("body") or {}).get("server_amount_cents") if isinstance(ck.get("body"), dict) else None,
        checkout_err=ck.get("body") if not ck["ok"] else None)

    # stock=1 two orders two sessions
    p1 = create_product(seller["id"], 1, 5.00, f"RT-D p3 qty1 {int(time.time())}")
    oids = []
    sessions = []
    for i in range(2):
        o = rest(buyer["jwt"], "POST", "orders", body={
            "product_id": p1, "buyer_id": buyer["id"], "seller_id": seller["id"],
            "price_total": 5, "status": "reserva_pendente", "quantity": 1,
            "payment_method": "Pagamento na App", "shipping_method": "hand",
        })
        oid = row(o).get("id")
        oids.append(oid)
        ck = fn(buyer["jwt"], "create-payment-intent", {"order_id": oid, "buyer_id": buyer["id"], "shipping_method": "hand"})
        b = ck.get("body") if isinstance(ck.get("body"), dict) else {}
        sessions.append({"order_id": oid, "http": ck["status"], "sid": b.get("checkoutSessionId"), "url": b.get("checkoutUrl"), "amt": b.get("server_amount_cents")})
    rec("stock1_two_sessions", product=p1, product_after=observe("products", p1), oids=oids, sessions=sessions)

    # live_id inject using a real live
    lives = rest(None, "GET", "lives?select=id,seller_id,status&limit=5", svc=True, prefer=None)
    live_rows = lives.get("body") if isinstance(lives.get("body"), list) else []
    foreign_live = next((x for x in live_rows if x.get("seller_id") != seller["id"]), live_rows[0] if live_rows else None)
    p3 = create_product(seller["id"], 2, 5.00, f"RT-D p3 liveinj {int(time.time())}")
    o3 = rest(buyer["jwt"], "POST", "orders", body={
        "product_id": p3, "buyer_id": buyer["id"], "seller_id": seller["id"],
        "price_total": 5, "status": "reserva_pendente", "quantity": 1,
        "payment_method": "Pagamento na App", "shipping_method": "hand",
    })
    oid3 = row(o3).get("id")
    ck3 = fn(buyer["jwt"], "create-payment-intent", {
        "order_id": oid3, "buyer_id": buyer["id"], "shipping_method": "hand",
        "live_id": (foreign_live or {}).get("id"), "is_live": True,
    })
    b3 = ck3.get("body") if isinstance(ck3.get("body"), dict) else {}
    rec("live_id_inject_session", live=foreign_live, order_id=oid3, order_before=observe("orders", oid3),
        checkout_http=ck3["status"], sid=b3.get("checkoutSessionId"), url=b3.get("checkoutUrl"), amt=b3.get("server_amount_cents"))

    # GET settle unpaid session (should not mark paid)
    if sessions and sessions[0].get("sid"):
        g = http("GET", FN + f"create-payment-intent?checkout_return=success&session_id={sessions[0]['sid']}", token=ANON, prefer=None)
        rec("get_settle_unpaid", http=g["status"], raw=g.get("raw", "")[:400], order=observe("orders", sessions[0]["order_id"]))

    # sequential payouts distinct keys
    k1 = f"rt_d_seq_a_{int(time.time())}"
    k2 = f"rt_d_seq_b_{int(time.time())}"
    w0 = observe("wallets", seller["id"])
    pA = fn(seller["jwt"], "create-connect-account", {"user_id": seller["id"], "amount": 100, "idempotency_key": k1})
    time.sleep(2)
    w1 = observe("wallets", seller["id"])
    pB = fn(seller["jwt"], "create-connect-account", {"user_id": seller["id"], "amount": 100, "idempotency_key": k2})
    w2 = observe("wallets", seller["id"])
    rec("sequential_payouts_two_keys",
        w0=w0.get("balance"), w1=w1.get("balance"), w2=w2.get("balance"),
        a=pA.get("body"), b=pB.get("body"),
        two_transfers=isinstance(pA.get("body"), dict) and isinstance(pB.get("body"), dict)
        and pA["body"].get("transferId") and pB["body"].get("transferId")
        and pA["body"].get("transferId") != pB["body"].get("transferId"))

    # admin resolve as buyer with hinted signature
    r = rpc(buyer["jwt"], "batata_admin_resolve_dispute", {
        "p_dispute_id": "00000000-0000-0000-0000-000000000001",
        "p_note": "x",
        "p_resolution": "reembolso",
    })
    rec("admin_resolve_3args", http=r["status"], body=r.get("body"))

    # raffle activate as buyer
    r = rpc(buyer["jwt"], "batata_activate_live_raffle", {"p_live_id": (foreign_live or {}).get("id")})
    rec("activate_raffle_buyer", http=r["status"], body=r.get("body"))

    # reservation qty
    r = rpc(buyer["jwt"], "batata_process_live_reservation_request", {
        "p_live_id": (foreign_live or {}).get("id"),
        "p_live_item_id": "00000000-0000-0000-0000-000000000001",
        "p_requested_qty": 99,
    })
    rec("reservation_qty99", http=r["status"], body=r.get("body"))

    # join raffle
    r = rpc(buyer["jwt"], "batata_join_live_raffle", {"p_raffle_id": "00000000-0000-0000-0000-000000000001"})
    rec("join_raffle", http=r["status"], body=r.get("body"))

    # openapi retry
    spec = http("GET", REST, token=SVC, apikey=SVC, prefer=None)
    rec("openapi_default_accept", http=spec["status"], keys=list(spec.get("body").keys())[:20] if isinstance(spec.get("body"), dict) else type(spec.get("body")).__name__)

    # MB WAY stock consume
    pmb = create_product(seller["id"], 2, 5.00, f"RT-D p3 mbway {int(time.time())}")
    omb = rest(buyer["jwt"], "POST", "orders", body={
        "product_id": pmb, "buyer_id": buyer["id"], "seller_id": seller["id"],
        "price_total": 5, "status": "aguarda_confirmacao", "quantity": 1, "payment_method": "MB WAY",
    })
    omb_id = row(omb).get("id")
    before = observe("products", pmb)
    rest(seller["jwt"], "PATCH", f"orders?id=eq.{omb_id}", body={"status": "pago"})
    after_o = observe("orders", omb_id)
    after_p = observe("products", pmb)
    rec("mbway_pago_stock", order_status=after_o.get("status"), stock_units=after_o.get("stock_units_applied"),
        qty_before=before.get("quantity"), qty_after=after_p.get("quantity"), is_sold=after_p.get("is_sold"),
        amount_paid=after_o.get("amount_paid_cents"))

    # observe previous mb way order if still exists
    rec("observe_old_mbway", order=observe("orders", "22415e09-ec30-4c02-8697-0159d6db9454"),
        product=observe("products", "b175da73-9c3f-4367-87cd-0e83879604be"))

    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=2, default=str), encoding="utf-8")
    print("WROTE", OUT)


if __name__ == "__main__":
    main()
