#!/usr/bin/env python3
"""Pass 2/3 verification — anti-false-positive + restore side effects."""
from __future__ import annotations

import json
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENV_PATH = ROOT / "tool" / "live_ops_staging.env"
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
ANON = E["SUPABASE_ANON_KEY"]
SVC = E["SUPABASE_SERVICE_ROLE_KEY"]
assert STAGING in URL


def req(method, path, token=None, service=False, body=None, query=None, extra=None, timeout=45):
    tok = SVC if service else (token or ANON)
    h = {
        "apikey": SVC if service else ANON,
        "Authorization": f"Bearer {tok}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    if extra:
        h.update(extra)
    q = ""
    if query:
        q = "?" + urllib.parse.urlencode(query, doseq=True)
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
    return code, parsed, raw


def login(email, password):
    c, b, _ = req(
        "POST",
        "/auth/v1/token?grant_type=password",
        body={"email": email, "password": password},
    )
    assert c == 200, (c, b)
    return b["access_token"], b["user"]["id"]


buyer_jwt, buyer = login(E["LIVE_OPS_TEST_BUYER_EMAIL"], E["LIVE_OPS_TEST_BUYER_PASSWORD"])
seller_jwt, seller = login(E["LIVE_OPS_TEST_SELLER_EMAIL"], E["LIVE_OPS_TEST_SELLER_PASSWORD"])

LOG = []


def note(k, **kw):
    LOG.append({"k": k, **kw})
    print(k, json.dumps(kw, default=str)[:500])


# Restore V0 product if we smashed price
c, b, _ = req(
    "GET",
    "/rest/v1/products",
    service=True,
    query={"id": "eq.f85ded7d-c00a-4e70-8931-77a81d309bd7", "select": "id,title,price,quantity,is_sold"},
)
note("v0_product_now", http=c, row=b)
if isinstance(b, list) and b and float(b[0].get("price") or 0) == 0.01:
    # cannot know original; set a non-zero lab price and flag
    c2, b2, _ = req(
        "PATCH",
        "/rest/v1/products",
        service=True,
        body={"price": 10.00},
        query={"id": "eq.f85ded7d-c00a-4e70-8931-77a81d309bd7"},
        extra={"Prefer": "return=representation"},
    )
    note("v0_price_restored_to_10", http=c2, row=b2)

# End stray live from create-mux-live
c, b, _ = req(
    "GET",
    "/rest/v1/lives",
    service=True,
    query={
        "id": "eq.7ec5d342-5257-4de0-a79c-4000d8237a2b",
        "select": "id,status,is_active,seller_id,vendedor_id,title",
    },
)
note("stray_live", http=c, row=b)
if isinstance(b, list) and b:
    c2, b2, _ = req(
        "POST",
        "/functions/v1/complete-mux-live",
        token=seller_jwt,
        body={"live_id": "7ec5d342-5257-4de0-a79c-4000d8237a2b"},
    )
    note("complete_mux_live", http=c2, body=str(b2)[:400])
    c3, b3, _ = req(
        "PATCH",
        "/rest/v1/lives",
        service=True,
        body={"status": "ended", "is_active": False},
        query={"id": "eq.7ec5d342-5257-4de0-a79c-4000d8237a2b"},
        extra={"Prefer": "return=representation"},
    )
    note("stray_live_force_ended", http=c3, row=b3)

PRODUCT = "d60b4ec1-bcfe-4525-b419-b0113264a268"
c, orders, _ = req(
    "GET",
    "/rest/v1/orders",
    service=True,
    query={
        "product_id": f"eq.{PRODUCT}",
        "select": "id,status,quantity,contract_unit_cents,contract_qty,price_total,amount_paid_cents,buyer_id,seller_id,stock_units_applied,payment_method,shipping_method,stripe_checkout_session_id",
        "order": "created_at.desc",
        "limit": "40",
    },
)
note("orders_on_probe_product", n=len(orders) if isinstance(orders, list) else None)
holdish = []
if isinstance(orders, list):
    for o in orders:
        st = str(o.get("status") or "").lower()
        if st not in ("cancelado", "cancelled", "rejected", "expired"):
            holdish.append(o)
    note(
        "active_holds",
        n=len(holdish),
        statuses={o["status"]: 1 for o in holdish},
        sample=holdish[:3],
    )

# status counts
from collections import Counter

if isinstance(orders, list):
    note("status_counts", counts=dict(Counter(o.get("status") for o in orders)))

c, prod, _ = req(
    "GET",
    "/rest/v1/products",
    service=True,
    query={"id": f"eq.{PRODUCT}", "select": "*"},
)
note("probe_product", row=prod)

# Dual checkout on two distinct active holds
sessions = []
if len(holdish) >= 2:
    o1, o2 = holdish[0], holdish[1]

    def ck(oid):
        return req(
            "POST",
            "/functions/v1/create-payment-intent",
            token=buyer_jwt,
            body={
                "buyer_id": buyer,
                "order_id": oid,
                "shipping_method": "hand",
                "amount": 1,
            },
        )

    with ThreadPoolExecutor(max_workers=2) as ex:
        futs = [ex.submit(ck, o1["id"]), ex.submit(ck, o2["id"])]
        for f in futs:
            sessions.append(f.result())
    note(
        "dual_checkout_two_holds",
        http=[s[0] for s in sessions],
        bodies=[str(s[1])[:500] for s in sessions],
        orders=[o1["id"], o2["id"]],
    )

# Inspect checkoutUrl-creating responses from previous run: create new session and capture full JSON
if holdish:
    oid = holdish[0]["id"]
    # reset shipping sealed
    req(
        "PATCH",
        "/rest/v1/orders",
        token=buyer_jwt,
        body={"shipping_method": "carrier"},
        query={"id": f"eq.{oid}"},
    )
    c, b, raw = req(
        "POST",
        "/functions/v1/create-payment-intent",
        token=buyer_jwt,
        body={
            "buyer_id": buyer,
            "order_id": oid,
            "shipping_method": "hand",
            "amount": 1,
            "quantity": 99,
        },
    )
    note("checkout_full", http=c, keys=list(b) if isinstance(b, dict) else None, body=b)
    after = req(
        "GET",
        "/rest/v1/orders",
        service=True,
        query={
            "id": f"eq.{oid}",
            "select": "id,price_total,shipping_method,contract_unit_cents,quantity,stripe_checkout_session_id,status",
        },
    )
    note("order_after_checkout", row=after[1])

    # hostile shipping PATCH empty then hand
    req(
        "PATCH",
        "/rest/v1/orders",
        token=buyer_jwt,
        body={"shipping_method": ""},
        query={"id": f"eq.{oid}"},
    )
    c2, b2, _ = req(
        "POST",
        "/functions/v1/create-payment-intent",
        token=buyer_jwt,
        body={"buyer_id": buyer, "order_id": oid, "shipping_method": "hand", "amount": 50},
    )
    note("checkout_empty_ship_then_hand", http=c2, body=b2)
    after2 = req(
        "GET",
        "/rest/v1/orders",
        service=True,
        query={"id": f"eq.{oid}", "select": "id,price_total,shipping_method,stripe_checkout_session_id"},
    )
    note("order_after_hand_fallback", row=after2[1])

# Seller paid FSM: find MB WAY pago from this run
c, mb, _ = req(
    "GET",
    "/rest/v1/orders",
    service=True,
    query={
        "buyer_id": f"eq.{buyer}",
        "seller_id": f"eq.{seller}",
        "payment_method": "eq.mb way",
        "select": "id,status,amount_paid_cents,stock_units_applied,price_total,product_id,wallet_release_processed_at",
        "order": "created_at.desc",
        "limit": "5",
    },
)
note("mbway_orders", rows=mb)
w_s = req("GET", "/rest/v1/wallets", service=True, query={"id": f"eq.{seller}", "select": "id,balance"})
note("seller_wallet", row=w_s[1])

# Banking: other sellers
c, sellers, _ = req(
    "GET",
    "/rest/v1/profiles",
    service=True,
    query={"select": "id,full_name", "id": f"neq.{seller}", "limit": "5"},
)
other_id = None
if isinstance(sellers, list):
    for p in sellers:
        if p["id"] not in (buyer, seller):
            other_id = p["id"]
            break
note("other_profile", id=other_id)
if other_id:
    c, b, _ = req(
        "POST",
        "/rest/v1/rpc/batata_seller_direct_payment_details",
        token=buyer_jwt,
        body={"p_seller_id": other_id},
    )
    note("banking_other_seller", http=c, body=b)
    c, b, _ = req(
        "POST",
        "/rest/v1/rpc/batata_seller_direct_payment_details",
        token=buyer_jwt,
        body={"p_seller_id": seller},
    )
    note("banking_lab_seller", http=c, body=b)

# Email oracle: buyer looks up seller email
c, b, _ = req(
    "POST",
    "/rest/v1/rpc/batata_find_user_id_by_email",
    token=buyer_jwt,
    body={"p_email": E["LIVE_OPS_TEST_SELLER_EMAIL"]},
)
note("email_oracle_buyer_lookup_seller", http=c, body=b)

# Reviews with stars
c, b, _ = req(
    "POST",
    "/rest/v1/reviews",
    token=buyer_jwt,
    body={
        "buyer_id": buyer,
        "target_id": seller,
        "stars": 5,
        "comment": "forged-no-order",
        "author_role": "comprador",
    },
    extra={"Prefer": "return=representation"},
)
note("review_no_order_stars", http=c, body=b)

# Live reservations on item from pass1
LI = "cff7b002-3b87-4ab7-acfb-3ea4b6aad74d"
c, res, _ = req(
    "GET",
    "/rest/v1/live_reservation_requests",
    service=True,
    query={
        "live_item_id": f"eq.{LI}",
        "select": "id,status,buyer_id,requested_qty,source,created_at",
        "order": "created_at.desc",
        "limit": "20",
    },
)
note("reservations_item", n=len(res) if isinstance(res, list) else None, rows=res)
c, li, _ = req(
    "GET",
    "/rest/v1/live_items",
    service=True,
    query={"id": f"eq.{LI}", "select": "id,status,quantity,product_id,checkout_product_id"},
)
note("live_item", row=li)

# Can buyer accept a pending reservation?
c, pend, _ = req(
    "POST",
    "/rest/v1/live_reservation_requests",
    token=buyer_jwt,
    body={
        "live_id": "4ea8fcd4-544c-43d1-8477-56ccc059a730",
        "live_item_id": LI,
        "buyer_id": buyer,
        "seller_id": seller,
        "requested_qty": 1,
        "status": "pending",
        "source": "fleaber_live",
    },
    extra={"Prefer": "return=representation"},
)
note("res_insert_pending", http=c, body=pend)
if c in (200, 201) and isinstance(pend, list) and pend:
    rid = pend[0]["id"]
    c2, b2, _ = req(
        "PATCH",
        "/rest/v1/live_reservation_requests",
        token=buyer_jwt,
        body={"status": "accepted"},
        query={"id": f"eq.{rid}"},
        extra={"Prefer": "return=representation"},
    )
    note("buyer_self_accept_pending", http=c2, body=b2)

# Disputes: can seller read disputes for orders they don't own?
c, ds, _ = req(
    "GET",
    "/rest/v1/order_disputes",
    token=seller_jwt,
    query={"select": "id,order_id,buyer_id,seller_id,status", "limit": "20"},
)
foreign_d = []
if isinstance(ds, list):
    for d in ds:
        if d.get("seller_id") and d.get("seller_id") != seller:
            foreign_d.append(d)
        if d.get("buyer_id") == seller:
            foreign_d.append(d)
note("disputes_as_seller", n=len(ds) if isinstance(ds, list) else None, foreign=foreign_d[:5], sample=(ds or [])[:3])

c, db, _ = req(
    "GET",
    "/rest/v1/order_disputes",
    token=buyer_jwt,
    query={"select": "id,order_id,buyer_id,seller_id,status", "limit": "20"},
)
foreign_b = []
if isinstance(db, list):
    for d in db:
        if d.get("buyer_id") and d.get("buyer_id") != buyer and d.get("seller_id") != buyer:
            foreign_b.append(d)
note("disputes_as_buyer", n=len(db) if isinstance(db, list) else None, foreign=foreign_b[:5])

# Payout bodies
c, b, _ = req(
    "POST",
    "/functions/v1/create-connect-account",
    token=seller_jwt,
    body={"amount": 1, "idempotency_key": "verify-" + str(int(time.time()))},
)
note("payout_seller_1cent", http=c, body=b)
c, b, _ = req(
    "POST",
    "/functions/v1/create-connect-account",
    token=buyer_jwt,
    body={"amount": 100, "idempotency_key": "verify-b-" + str(int(time.time()))},
)
note("payout_buyer_1eur", http=c, body=b)

# Storage buckets via service
c, b, _ = req("GET", "/storage/v1/bucket", service=True)
note("storage_buckets_service", http=c, body=b)

# OpenAPI retry
c, spec, _ = req("GET", "/rest/v1/", extra={"Accept": "application/openapi+json", "apikey": ANON})
note("openapi_retry", http=c, type=type(spec).__name__, keys=list(spec)[:20] if isinstance(spec, dict) else str(spec)[:200])

# List RPCs from PostgREST by fetching swagger yaml?
c, spec2, raw2 = req("GET", "/rest/v1/", extra={"Accept": "application/json"})
note("rest_root", http=c, body=str(spec2)[:200])

# Seller order as buyer: the 201 paid insert
c, so, _ = req(
    "GET",
    "/rest/v1/orders",
    service=True,
    query={
        "buyer_id": f"eq.{seller}",
        "seller_id": f"eq.{seller}",
        "select": "id,status,amount_paid_cents,stripe_payment_intent_id,quantity,contract_unit_cents,price_total,product_id",
        "order": "created_at.desc",
        "limit": "5",
    },
)
note("seller_self_orders", rows=so)

# RPC grant spray from openapi-less: try credit with alternate signatures
alts = [
    ("batata_credit_wallet_once", {"p_wallet_user_id": buyer, "p_amount_eur": 1, "p_idempotency_key": "x", "p_entry_type": "venda"}),
    ("batata_credit_wallet_once", {"p_user_id": buyer, "p_order_id": None, "p_amount_eur": 1, "p_kind": "venda", "p_note": "x"}),
    ("batata_send_live_tip_from_wallet", {"p_live_id": None, "p_seller_id": seller, "p_amount": 1, "p_message": "x"}),
    ("batata_create_live_tip_pending", {"p_live_id": None, "p_seller_id": seller, "p_amount": 1, "p_message": "x"}),
]
w0 = req("GET", "/rest/v1/wallets", service=True, query={"id": f"eq.{buyer}", "select": "id,balance"})[1]
for name, payload in alts:
    c, b, _ = req("POST", f"/rest/v1/rpc/{name}", token=buyer_jwt, body=payload)
    note(f"rpc_alt_{name}", http=c, body=str(b)[:300], payload=payload)
w1 = req("GET", "/rest/v1/wallets", service=True, query={"id": f"eq.{buyer}", "select": "id,balance"})[1]
note("wallet_buyer_delta_alts", before=w0, after=w1)

# Partial refund RPC if we have a paid order
c, paid, _ = req(
    "GET",
    "/rest/v1/orders",
    service=True,
    query={
        "seller_id": f"eq.{seller}",
        "select": "id,status,amount_paid_cents,stripe_payment_intent_id,buyer_id",
        "amount_paid_cents": "gt.0",
        "limit": "3",
    },
)
note("paid_orders_sample", rows=paid)
if isinstance(paid, list) and paid:
    oid = paid[0]["id"]
    w_b = req("GET", "/rest/v1/wallets", service=True, query={"id": f"eq.{buyer}", "select": "id,balance"})[1]
    w_s = req("GET", "/rest/v1/wallets", service=True, query={"id": f"eq.{seller}", "select": "id,balance"})[1]
    c, b, _ = req(
        "POST",
        "/rest/v1/rpc/batata_process_partial_refund_dispute",
        token=buyer_jwt,
        body={"p_order_id": oid, "p_amount": 0.01},
    )
    note("partial_refund_as_buyer", http=c, body=b, order=paid[0])
    c, b, _ = req(
        "POST",
        "/functions/v1/refund-order",
        token=buyer_jwt,
        body={"order_id": oid},
    )
    note("refund_edge_buyer_on_paid", http=c, body=str(b)[:400])
    w_b2 = req("GET", "/rest/v1/wallets", service=True, query={"id": f"eq.{buyer}", "select": "id,balance"})[1]
    w_s2 = req("GET", "/rest/v1/wallets", service=True, query={"id": f"eq.{seller}", "select": "id,balance"})[1]
    note("wallets_after_refund_attempts", buyer=(w_b, w_b2), seller=(w_s, w_s2))

# Offers oneshot evidence from first run — query offers
c, offs, _ = req(
    "GET",
    "/rest/v1/product_offers",
    service=True,
    query={"product_id": f"eq.{PRODUCT}", "select": "*", "limit": "10"},
)
note("offers_on_product", rows=offs)

# e2e oversell result from previous json is enough; try pay_one only if secret
secret = E.get("FLEABER_STAGING_CRASH_INJECT_SECRET", "")
if secret:
    # stock=1 product fresh
    ref = str(int(time.time()))
    c, pnew, _ = req(
        "POST",
        "/rest/v1/products",
        token=seller_jwt,
        body={
            "seller_id": seller,
            "title": f"RT-PAY {ref}",
            "price": 5.00,
            "quantity": 1,
            "list_on_marketplace": True,
            "is_sold": False,
            "ref_code": f"RTP-{ref}",
        },
        extra={"Prefer": "return=representation"},
    )
    note("pay_product", http=c, row=pnew)
    pid = None
    if isinstance(pnew, list) and pnew:
        pid = pnew[0]["id"]
    if pid:
        c, b, _ = req(
            "POST",
            "/functions/v1/sec-fase2-e2e-oversell",
            extra={"x-fleaber-e2e-secret": secret},
            body={
                "probe": "oversell_two",
                "buyer_id": buyer,
                "seller_id": seller,
                "product_id": pid,
                "initial_qty": 1,
            },
        )
        note("e2e_oversell_two", http=c, body=b)

outp = OUT / f"verify_{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.json"
outp.write_text(json.dumps(LOG, indent=2, default=str), encoding="utf-8")
print("WROTE", outp)
