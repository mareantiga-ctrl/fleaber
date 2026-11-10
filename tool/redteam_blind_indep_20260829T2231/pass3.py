#!/usr/bin/env python3
"""Pass 3 focused: shipping underpay, status-hold bypass, Stripe TEST oversell, leftovers."""
from __future__ import annotations

import json
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

ENV_PATH = Path(__file__).resolve().parents[2] / "tool" / "live_ops_staging.env"
OUT = Path(__file__).resolve().parent / "out"
STAGING = "fxdknzrqjenzqcvnwqqq"


def load_env(path: Path) -> dict[str, str]:
    env = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip().strip('"').strip("'")
    return env


E = load_env(ENV_PATH)
URL = E["SUPABASE_URL"].replace("/rest/v1/", "").replace("/rest/v1", "").rstrip("/")
ANON, SVC = E["SUPABASE_ANON_KEY"], E["SUPABASE_SERVICE_ROLE_KEY"]
SECRET = E.get("FLEABER_STAGING_CRASH_INJECT_SECRET", "")
assert STAGING in URL
LOG = []


def note(k, **kw):
    LOG.append({"k": k, **kw})
    msg = json.dumps({"k": k, **kw}, default=str)
    print(msg[:900])


def req(method, path, token=None, service=False, body=None, query=None, extra=None, timeout=60):
    tok = SVC if service else (token or ANON)
    h = {
        "apikey": SVC if service else ANON,
        "Authorization": f"Bearer {tok}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    if extra:
        h.update(extra)
    q = "?" + urllib.parse.urlencode(query, doseq=True) if query else ""
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(URL + path + q, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(r, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", "replace")
            code = resp.status
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        code = e.code
    try:
        parsed = json.loads(raw) if raw else None
    except json.JSONDecodeError:
        parsed = raw
    return code, parsed


def login(email, password):
    c, b = req("POST", "/auth/v1/token?grant_type=password", body={"email": email, "password": password})
    assert c == 200, (c, b)
    return b["access_token"], b["user"]["id"]


bj, buyer = login(E["LIVE_OPS_TEST_BUYER_EMAIL"], E["LIVE_OPS_TEST_BUYER_PASSWORD"])
sj, seller = login(E["LIVE_OPS_TEST_SELLER_EMAIL"], E["LIVE_OPS_TEST_SELLER_PASSWORD"])


def snap(table, **q):
    return req("GET", f"/rest/v1/{table}", service=True, query=q)[1]


# --- fresh product for shipping underpay ---
ref = str(int(time.time()))
c, prod = req(
    "POST",
    "/rest/v1/products",
    token=sj,
    body={
        "seller_id": seller,
        "title": f"RT-SHIP {ref}",
        "price": 20.00,
        "quantity": 3,
        "list_on_marketplace": True,
        "is_sold": False,
        "ref_code": f"RTS-{ref}",
    },
    extra={"Prefer": "return=representation"},
)
pid = prod[0]["id"] if c == 201 else None
note("ship_product", http=c, pid=pid)


def mk_order(ship, status="reserva_pendente"):
    c, b = req(
        "POST",
        "/rest/v1/orders",
        token=bj,
        body={
            "buyer_id": buyer,
            "seller_id": seller,
            "product_id": pid,
            "quantity": 1,
            "status": status,
            "payment_method": "seguro fleaber",
            "shipping_method": ship,
            "price_total": 20,
        },
        extra={"Prefer": "return=representation"},
    )
    return c, b


def checkout(oid, ship_body, extra_body=None):
    body = {"buyer_id": buyer, "order_id": oid, "shipping_method": ship_body, "amount": 1}
    if extra_body:
        body.update(extra_body)
    return req("POST", "/functions/v1/create-payment-intent", token=bj, body=body)


# Reproduce shipping underpay twice
for i in range(2):
    c, b = mk_order("carrier")
    note(f"order_carrier_{i}", http=c, row=b)
    oid = b[0]["id"]
    before = snap(
        "orders",
        id=f"eq.{oid}",
        select="id,shipping_method,price_total,contract_unit_cents,status",
    )
    c1, s1 = checkout(oid, "hand")
    note(
        f"checkout_sealed_carrier_body_hand_{i}",
        http=c1,
        amount=s1.get("server_amount_cents") if isinstance(s1, dict) else None,
        total=s1.get("amount_total") if isinstance(s1, dict) else None,
        err=s1 if not isinstance(s1, dict) or "checkoutUrl" not in s1 else None,
        keys=list(s1) if isinstance(s1, dict) else None,
    )
    # PATCH shipping empty
    c2, p2 = req(
        "PATCH",
        "/rest/v1/orders",
        token=bj,
        body={"shipping_method": ""},
        query={"id": f"eq.{oid}"},
        extra={"Prefer": "return=representation"},
    )
    note(f"patch_ship_empty_{i}", http=c2, row=p2)
    c3, s3 = checkout(oid, "hand")
    note(
        f"checkout_after_empty_ship_{i}",
        http=c3,
        amount=s3.get("server_amount_cents") if isinstance(s3, dict) else None,
        total=s3.get("amount_total") if isinstance(s3, dict) else None,
        body=s3 if isinstance(s3, dict) else str(s3)[:300],
    )
    after = snap(
        "orders",
        id=f"eq.{oid}",
        select="id,shipping_method,price_total,status",
    )
    note(f"order_after_underpay_{i}", before=before, after=after)

# garbage shipping
c, b = mk_order("carrier")
oid = b[0]["id"]
req("PATCH", "/rest/v1/orders", token=bj, body={"shipping_method": "garbage"}, query={"id": f"eq.{oid}"})
c4, s4 = checkout(oid, "hand")
note(
    "checkout_garbage_then_hand",
    http=c4,
    amount=s4.get("server_amount_cents") if isinstance(s4, dict) else None,
    total=s4.get("amount_total") if isinstance(s4, dict) else None,
    row=snap("orders", id=f"eq.{oid}", select="id,shipping_method,price_total"),
)

# --- status escalation: reserva_pendente -> aguarda_pagamento on stock=1 ---
c, p1 = req(
    "POST",
    "/rest/v1/products",
    token=sj,
    body={
        "seller_id": seller,
        "title": f"RT-HOLD {ref}",
        "price": 9.00,
        "quantity": 1,
        "list_on_marketplace": True,
        "is_sold": False,
        "ref_code": f"RTH-{ref}",
    },
    extra={"Prefer": "return=representation"},
)
pid1 = p1[0]["id"]
note("hold_product", pid=pid1, row=p1)

oids = []
for i in range(5):
    c, b = req(
        "POST",
        "/rest/v1/orders",
        token=bj,
        body={
            "buyer_id": buyer,
            "seller_id": seller,
            "product_id": pid1,
            "quantity": 1,
            "status": "reserva_pendente",
            "payment_method": "seguro fleaber",
            "shipping_method": "hand",
            "price_total": 9,
        },
        extra={"Prefer": "return=representation"},
    )
    if c in (200, 201):
        oids.append(b[0]["id"])
note("pend_orders", n=len(oids), ids=oids)

# try escalate all to aguarda_pagamento
esc = []
for oid in oids:
    c, b = req(
        "PATCH",
        "/rest/v1/orders",
        token=bj,
        body={"status": "aguarda_pagamento"},
        query={"id": f"eq.{oid}"},
        extra={"Prefer": "return=representation"},
    )
    esc.append((c, b))
note("escalate_aguarda", results=[(c, (b[0] if isinstance(b, list) and b else b)) for c, b in esc])

# seller escalate
esc_s = []
for oid in oids:
    c, b = req(
        "PATCH",
        "/rest/v1/orders",
        token=sj,
        body={"status": "reservado"},
        query={"id": f"eq.{oid}"},
        extra={"Prefer": "return=representation"},
    )
    esc_s.append((c, b[0] if isinstance(b, list) and b else b))
note("seller_escalate_reservado", results=[(c, r) for c, r in esc_s])

final_orders = snap(
    "orders",
    product_id=f"eq.{pid1}",
    select="id,status,quantity",
)
note("hold_product_orders_final", rows=final_orders, product=snap("products", id=f"eq.{pid1}", select="id,quantity,is_sold,price"))

# checkout two reserva_pendente on stock=1 (no escalate)
c, p2 = req(
    "POST",
    "/rest/v1/products",
    token=sj,
    body={
        "seller_id": seller,
        "title": f"RT-SESS {ref}",
        "price": 7.00,
        "quantity": 1,
        "list_on_marketplace": True,
        "is_sold": False,
        "ref_code": f"RTSS-{ref}",
    },
    extra={"Prefer": "return=representation"},
)
pid2 = p2[0]["id"]
oA = req(
    "POST",
    "/rest/v1/orders",
    token=bj,
    body={
        "buyer_id": buyer,
        "seller_id": seller,
        "product_id": pid2,
        "quantity": 1,
        "status": "reserva_pendente",
        "payment_method": "seguro fleaber",
        "shipping_method": "hand",
        "price_total": 7,
    },
    extra={"Prefer": "return=representation"},
)[1][0]["id"]
oB = req(
    "POST",
    "/rest/v1/orders",
    token=bj,
    body={
        "buyer_id": buyer,
        "seller_id": seller,
        "product_id": pid2,
        "quantity": 1,
        "status": "reserva_pendente",
        "payment_method": "seguro fleaber",
        "shipping_method": "hand",
        "price_total": 7,
    },
    extra={"Prefer": "return=representation"},
)[1][0]["id"]


def ck2(oid):
    return req(
        "POST",
        "/functions/v1/create-payment-intent",
        token=bj,
        body={"buyer_id": buyer, "order_id": oid, "shipping_method": "hand"},
    )


with ThreadPoolExecutor(max_workers=2) as ex:
    fa, fb = ex.submit(ck2, oA), ex.submit(ck2, oB)
    a, b = fa.result(), fb.result()
note(
    "dual_session_stock1",
    a_http=a[0],
    b_http=b[0],
    a_amt=(a[1] or {}).get("server_amount_cents") if isinstance(a[1], dict) else None,
    b_amt=(b[1] or {}).get("server_amount_cents") if isinstance(b[1], dict) else None,
    a_sid=(a[1] or {}).get("checkoutSessionId") if isinstance(a[1], dict) else None,
    b_sid=(b[1] or {}).get("checkoutSessionId") if isinstance(b[1], dict) else None,
    a_err=a[1] if isinstance(a[1], dict) and not a[1].get("checkoutUrl") else None,
    b_err=b[1] if isinstance(b[1], dict) and not b[1].get("checkoutUrl") else None,
)

# PATCH contract after seal
c, b = mk_order("hand")
oidc = b[0]["id"]
c, p = req(
    "PATCH",
    "/rest/v1/orders",
    token=bj,
    body={"contract_unit_cents": 1, "contract_qty": 1, "price_total": 0.01, "quantity": 1},
    query={"id": f"eq.{oidc}"},
    extra={"Prefer": "return=representation"},
)
note("patch_contract", http=c, row=p, final=snap("orders", id=f"eq.{oidc}", select="id,contract_unit_cents,contract_qty,price_total,quantity"))
c5, s5 = checkout(oidc, "hand")
note(
    "checkout_after_contract_patch",
    http=c5,
    amount=s5.get("server_amount_cents") if isinstance(s5, dict) else None,
    total=s5.get("amount_total") if isinstance(s5, dict) else None,
)

# --- Stripe TEST oversell_two via e2e secret (fixture pay; observe final DB) ---
if SECRET:
    c, ev = req(
        "POST",
        "/functions/v1/sec-fase2-e2e-oversell",
        extra={"x-fleaber-e2e-secret": SECRET},
        body={
            "probe": "oversell_two",
            "buyer_id": buyer,
            "seller_id": seller,
            "initial_qty": 1,
        },
        timeout=120,
    )
    note("e2e_oversell_two", http=c, body=ev)

    c, ev2 = req(
        "POST",
        "/functions/v1/sec-fase2-e2e-oversell",
        extra={"x-fleaber-e2e-secret": SECRET},
        body={"probe": "setup_paid_order", "buyer_id": buyer, "seller_id": seller, "initial_qty": 1},
        timeout=90,
    )
    note("e2e_setup_paid_order", http=c, body=ev2)
    # JWT refund as buyer vs seller on that order
    oid_paid = None
    if isinstance(ev2, dict):
        oid_paid = ev2.get("order_id") or (ev2.get("order") or {}).get("id") or ev2.get("evidence", {}).get("order_id") if isinstance(ev2.get("evidence"), dict) else None
        # brute keys
        def find_oid(obj, depth=0):
            if depth > 4:
                return None
            if isinstance(obj, dict):
                for k, v in obj.items():
                    if k in ("order_id",) and isinstance(v, str) and len(v) > 20:
                        return v
                    if k == "order" and isinstance(v, dict) and v.get("id"):
                        return v["id"]
                    r = find_oid(v, depth + 1)
                    if r:
                        return r
            if isinstance(obj, list):
                for x in obj:
                    r = find_oid(x, depth + 1)
                    if r:
                        return r
            return None
        oid_paid = oid_paid or find_oid(ev2)
    note("paid_order_id", oid=oid_paid)
    if oid_paid:
        w0b = snap("wallets", id=f"eq.{buyer}", select="id,balance")
        w0s = snap("wallets", id=f"eq.{seller}", select="id,balance")
        o0 = snap("orders", id=f"eq.{oid_paid}", select="id,status,amount_paid_cents,stripe_refund_id,stock_units_applied,price_total")
        c, r1 = req("POST", "/functions/v1/refund-order", token=bj, body={"order_id": oid_paid})
        note("refund_as_buyer", http=c, body=r1)
        c, r2 = req("POST", "/functions/v1/refund-order", token=sj, body={"order_id": oid_paid})
        note("refund_as_seller", http=c, body=r2)
        c, r3 = req("POST", "/functions/v1/refund-order", token=sj, body={"order_id": oid_paid})
        note("refund_as_seller_retry", http=c, body=r3)
        o1 = snap("orders", id=f"eq.{oid_paid}", select="id,status,amount_paid_cents,stripe_refund_id,stock_units_applied")
        w1b = snap("wallets", id=f"eq.{buyer}", select="id,balance")
        w1s = snap("wallets", id=f"eq.{seller}", select="id,balance")
        note("after_refund", order_before=o0, order_after=o1, wallets=((w0b, w1b), (w0s, w1s)))
        # release after refund
        c, rel = req("POST", "/rest/v1/rpc/batata_release_seller_wallet_for_order", token=sj, body={"p_order_id": oid_paid})
        note("release_after_refund", http=c, body=rel, wallet=snap("wallets", id=f"eq.{seller}", select="id,balance"))

# disputes remaining
c, ds = req(
    "GET",
    "/rest/v1/order_disputes",
    token=sj,
    query={"select": "id,order_id,buyer_id,seller_id,status", "limit": "20"},
)
foreign = []
if isinstance(ds, list):
    for d in ds:
        if d.get("seller_id") not in (None, seller) and d.get("buyer_id") != seller:
            foreign.append(d)
note("disputes_seller", n=len(ds) if isinstance(ds, list) else ds, foreign_n=len(foreign), foreign=foreign[:3])

c, db = req(
    "GET",
    "/rest/v1/order_disputes",
    token=bj,
    query={"select": "id,order_id,buyer_id,seller_id,status", "limit": "20"},
)
foreign_b = []
if isinstance(db, list):
    for d in db:
        if d.get("buyer_id") not in (None, buyer) and d.get("seller_id") != buyer:
            foreign_b.append(d)
note("disputes_buyer", n=len(db) if isinstance(db, list) else db, foreign_n=len(foreign_b))

# chats
c, ch = req("GET", "/rest/v1/chats", token=bj, query={"select": "id,user_a,user_b", "limit": "20"})
cross = []
if isinstance(ch, list):
    for row in ch:
        if buyer not in (row.get("user_a"), row.get("user_b")):
            cross.append(row)
note("chats_buyer", n=len(ch) if isinstance(ch, list) else ch, cross=len(cross))

# storage
c, buckets = req("GET", "/storage/v1/bucket", service=True)
note("storage_buckets", http=c, body=buckets)

# raffle tick with real id
c, raf = req("GET", "/rest/v1/live_raffles", service=True, query={"select": "id,live_id,status", "limit": "3"})
note("raffles", rows=raf)
if isinstance(raf, list) and raf:
    c, t = req("POST", "/rest/v1/rpc/batata_tick_live_raffle", token=bj, body={"p_raffle_id": raf[0]["id"]})
    note("tick_raffle_as_buyer", http=c, body=t)
    c, w = req(
        "POST",
        "/rest/v1/live_raffle_winners",
        token=bj,
        body={"raffle_id": raf[0]["id"], "user_id": buyer},
        extra={"Prefer": "return=representation"},
    )
    note("insert_winner_as_buyer", http=c, body=t if False else w)

# messages
for mt in ("messages", "chat_messages", "live_messages"):
    c, b = req("GET", f"/rest/v1/{mt}", token=bj, query={"select": "*", "limit": "3"})
    note(f"get_{mt}", http=c, n=len(b) if isinstance(b, list) else None, sample=str(b)[:200])

# profiles flags final
c, pr = req("GET", "/rest/v1/profiles", service=True, query={"id": f"eq.{buyer}", "select": "id,user_type,is_admin,verified"})
note("buyer_profile_final", row=pr)

outp = OUT / f"pass3_{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.json"
outp.write_text(json.dumps(LOG, indent=2, default=str), encoding="utf-8")
print("WROTE", outp)
