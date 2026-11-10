#!/usr/bin/env python3
"""Pass 3: composition leftovers, cleanup, USD, events leak, review delete."""
from __future__ import annotations
import json, ssl
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
ENV = {}
for line in (ROOT / "tool" / "live_ops_staging.env").read_text(encoding="utf-8").splitlines():
    if line.strip() and not line.strip().startswith("#") and "=" in line:
        k, v = line.split("=", 1)
        ENV[k.strip()] = v.strip()
BASE = "https://fxdknzrqjenzqcvnwqqq.supabase.co"
ANON, SVC = ENV["SUPABASE_ANON_KEY"], ENV["SUPABASE_SERVICE_ROLE_KEY"]
BUYER_ID, SELLER_ID = ENV["LIVE_OPS_TEST_BUYER_ID"], ENV["LIVE_OPS_TEST_SELLER_ID"]
CTX = ssl.create_default_context()
OUT = []

def http(method, url, token, body=None, extra=None):
    headers = {"Accept": "application/json", "apikey": ANON, "Authorization": f"Bearer {token}"}
    if token == SVC:
        headers["apikey"] = SVC
    if extra:
        headers.update(extra)
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    req = Request(url, data=data, headers=headers, method=method)
    try:
        with urlopen(req, timeout=40, context=CTX) as r:
            raw = r.read()
            return r.status, json.loads(raw.decode() or "null")
    except HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw.decode() or "null")
        except Exception:
            return e.code, raw.decode("utf-8", "replace")[:800]
    except URLError as e:
        return 0, str(e)

def rest(method, path, token, body=None, qs=""):
    return http(method, f"{BASE}/rest/v1/{path}{qs}", token, body, {"Prefer": "return=representation"})

def snip(o, n=500):
    return json.dumps(o, default=str, ensure_ascii=False)[:n]

def login(email, pw):
    st, p = http("POST", f"{BASE}/auth/v1/token?grant_type=password", ANON, {"email": email, "password": pw})
    return p["access_token"]

buyer = login(ENV["LIVE_OPS_TEST_BUYER_EMAIL"], ENV["LIVE_OPS_TEST_BUYER_PASSWORD"])
seller = login(ENV["LIVE_OPS_TEST_SELLER_EMAIL"], ENV["LIVE_OPS_TEST_SELLER_PASSWORD"])

# profile final
st, p = rest("GET", "profiles", buyer, qs=f"?id=eq.{BUYER_ID}&select=id,user_type,phone_verified_at,iban")
OUT.append({"profile_final": p, "st": st})
if isinstance(p, list) and p:
    row = p[0]
    if row.get("phone_verified_at") or row.get("iban") or str(row.get("user_type")).lower() != "comprador":
        rest("PATCH", "profiles", buyer, {"user_type": "comprador", "phone_verified_at": None, "iban": None}, qs=f"?id=eq.{BUYER_ID}")
        st, p = rest("GET", "profiles", buyer, qs=f"?id=eq.{BUYER_ID}&select=id,user_type,phone_verified_at,iban")
        OUT.append({"profile_reverted_again": p})

# delete satcega review
st, p = rest("DELETE", "reviews", buyer, qs="?id=eq.25fed33d-5818-44c1-9cb0-5be44bc2b264")
OUT.append({"delete_review": {"st": st, "body": snip(p)}})
st, p = rest("GET", "reviews", buyer, qs="?id=eq.25fed33d-5818-44c1-9cb0-5be44bc2b264&select=id,stars,comment")
OUT.append({"review_after_delete": p})

# USD checkout currency on last session from probe - read order 279f4719
st, p = rest("GET", "orders", buyer, qs="?id=eq.279f4719-e247-4fc1-8706-8f73ab2bbafc&select=id,contract_unit_cents,price_total,status")
OUT.append({"neg_price_order": p})

# stripe events: other buyers?
st, p = rest("GET", "stripe_checkout_events", buyer, qs="?select=id,order_id,buyer_id,event,session_id&limit=30")
foreign = []
if isinstance(p, list):
    foreign = [r for r in p if r.get("buyer_id") and r.get("buyer_id") != BUYER_ID]
OUT.append({"stripe_events_n": len(p) if isinstance(p, list) else p, "foreign_buyer_events": snip(foreign[:5]), "foreign_n": len(foreign)})

# hub_lives_public
st, p = rest("GET", "hub_lives_public", buyer, qs="?select=*&limit=2")
OUT.append({"hub_lives_public": {"st": st, "body": snip(p)}})
st, p = rest("GET", "hub_lives_public", ANON, qs="?select=*&limit=2")
OUT.append({"hub_lives_public_anon": {"st": st, "body": snip(p)}})

# wallet txs for mbway order
st, p = rest("GET", "wallet_transactions", seller, qs="?order_id=eq.cc12ae00-1a73-4722-a74a-f8687a36cb39&select=*")
OUT.append({"mbway_wallet_tx": {"st": st, "body": snip(p)}})
st, p = rest("GET", "orders", seller, qs="?id=eq.cc12ae00-1a73-4722-a74a-f8687a36cb39&select=id,status,amount_paid_cents,wallet_release_processed_at,payment_method")
OUT.append({"mbway_order_now": p})

# dispute percent after seller patch
st, p = rest("GET", "order_disputes", seller, qs="?id=eq.e027d167-1df1-478b-a3fe-24c96dfb58c4&select=id,status,seller_refund_percent,seller_offer_set_by")
OUT.append({"dispute_after_patch": p})

# reservation 99
st, p = rest("GET", "live_reservation_requests", seller, qs="?id=eq.bb9d65e0-7750-4d6f-b5fb-952cd1f138f0&select=id,requested_qty,status")
OUT.append({"hostile_reservation_now": p})
if isinstance(p, list) and p:
    rest("PATCH", "live_reservation_requests", seller, {"status": "cancelled", "requested_qty": 1}, qs="?id=eq.bb9d65e0-7750-4d6f-b5fb-952cd1f138f0")

# unpaid enviado order 846fecba
st, p = rest("GET", "orders", seller, qs="?id=eq.846fecba-34b2-487f-9607-c5a768f1ee12&select=id,status,payment_method,amount_paid_cents,stripe_payment_intent_id")
OUT.append({"unpaid_enviado": p})

# storage nested files
st, p = http("POST", f"{BASE}/storage/v1/object/list/chat_media", ANON, {"prefix": "product_photos/", "limit": 15})
OUT.append({"anon_product_photos_files": {"st": st, "n": len(p) if isinstance(p, list) else None, "sample": snip(p)}})
st, p = http("POST", f"{BASE}/storage/v1/object/list/chat_media", ANON, {"prefix": "chat_uploads/", "limit": 15})
OUT.append({"anon_chat_uploads_files": {"st": st, "n": len(p) if isinstance(p, list) else None, "sample": snip(p)}})

# cancel SATCEGA orders (title via product description)
st, prods = rest("GET", "products", seller, qs="?description=like.*SATCEGA*&select=id,title,quantity")
OUT.append({"satcega_products": snip(prods)})
if isinstance(prods, list):
    ids = [r["id"] for r in prods]
    for pid in ids:
        rest("PATCH", "products", seller, {"list_on_marketplace": False, "quantity": 0}, qs=f"?id=eq.{pid}")
    # cancel open orders on those products
    if ids:
        st, ords = rest("GET", "orders", seller, qs=f"?product_id=in.({','.join(ids)})&select=id,status&status=in.(reserva_pendente,reservado,enviado,pago)")
        OUT.append({"satcega_open_orders": snip(ords)})
        if isinstance(ords, list):
            for o in ords:
                if str(o.get("status")).lower() in {"reserva_pendente", "reservado"}:
                    rest("PATCH", "orders", seller, {"status": "cancelado"}, qs=f"?id=eq.{o['id']}")

# mux live status
st, p = rest("GET", "lives", SVC, qs="?id=eq.0f0f239d-e2c6-44bd-8a13-c1ccf2fa3495&select=id,status,is_active,title")
OUT.append({"mux_live_final": {"st": st, "body": snip(p)}})

# seller bundle discounts JWT
st, p = rest("GET", "seller_bundle_discounts", buyer, qs="?select=*&limit=5")
OUT.append({"buyer_bundle_discounts": {"st": st, "body": snip(p)}})
st, p = rest("PATCH", "seller_bundle_discounts", buyer, {"enabled": True, "tier_2_pct": 50}, qs=f"?seller_id=eq.{SELLER_ID}")
OUT.append({"buyer_patch_bundle": {"st": st, "body": snip(p)}})

dest = ROOT / "tool" / "reports" / "SATURACAO_CEGA_2026-08-27_PASS3.json"
dest.write_text(json.dumps(OUT, ensure_ascii=False, indent=2, default=str), encoding="utf-8")
print("wrote", dest)
for x in OUT:
    print(json.dumps(x, ensure_ascii=False, default=str)[:400])
    print("---")
