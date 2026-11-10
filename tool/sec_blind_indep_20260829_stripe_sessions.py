#!/usr/bin/env python3
"""Mint fresh Checkout Sessions and write FULL URLs. Staging Stripe TEST only."""
from __future__ import annotations

import json
import time
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
ENV = ROOT / "tool" / "live_ops_staging.env"
OUT = ROOT / "tool" / "reports"


def load_env():
    out = {}
    for line in ENV.read_text(encoding="utf-8").splitlines():
        t = line.strip()
        if not t or t.startswith("#") or "=" not in t:
            continue
        k, v = t.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def req(method, url, headers, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = Request(url, data=data, headers=headers, method=method)
    try:
        with urlopen(r, timeout=45) as resp:
            return resp.status, json.loads(resp.read().decode())
    except HTTPError as e:
        return e.code, json.loads(e.read().decode())


def main():
    env = load_env()
    raw = env["SUPABASE_URL"].strip().rstrip("/")
    if raw.endswith("/rest/v1"):
        raw = raw[: -len("/rest/v1")].rstrip("/")
    anon = env["SUPABASE_ANON_KEY"]
    svc = env["SUPABASE_SERVICE_ROLE_KEY"]
    buyer = env["LIVE_OPS_TEST_BUYER_ID"]
    seller = env["LIVE_OPS_TEST_SELLER_ID"]
    tag = f"rtbpay-{int(time.time())}"

    def H(tok, key=None):
        k = key or anon
        return {
            "apikey": k,
            "Authorization": f"Bearer {tok}",
            "Content-Type": "application/json",
            "Prefer": "return=representation",
        }

    st, tokb = req(
        "POST",
        f"{raw}/auth/v1/token?grant_type=password",
        {"apikey": anon, "Content-Type": "application/json"},
        {"email": env["LIVE_OPS_TEST_BUYER_EMAIL"], "password": env["LIVE_OPS_TEST_BUYER_PASSWORD"]},
    )
    bj = tokb["access_token"]

    def post_prod(qty=1, price=5.5):
        st, b = req(
            "POST",
            f"{raw}/rest/v1/products",
            H(svc, svc),
            {
                "seller_id": seller,
                "title": f"{tag} p{qty}",
                "price": price,
                "quantity": qty,
                "list_on_marketplace": True,
                "is_sold": False,
                "ref_code": f"{tag}-{qty}-{int(time.time()*1000)%100000}",
            },
        )
        return b[0]["id"] if isinstance(b, list) else b["id"]

    def post_ord(pid):
        st, b = req(
            "POST",
            f"{raw}/rest/v1/orders",
            H(bj),
            {
                "buyer_id": buyer,
                "seller_id": seller,
                "product_id": pid,
                "quantity": 1,
                "price_total": 8,
                "status": "reserva_pendente",
                "payment_method": "Seguro Fleaber",
                "shipping_method": "hand",
            },
        )
        return b[0]

    def checkout(oid):
        st, b = req(
            "POST",
            f"{raw}/functions/v1/create-payment-intent",
            {
                "apikey": anon,
                "Authorization": f"Bearer {bj}",
                "Content-Type": "application/json",
            },
            {"buyer_id": buyer, "order_id": oid, "shipping_method": "hand", "amount": 1},
        )
        return st, b

    pid1 = post_prod(1, 8.0)
    o1 = post_ord(pid1)
    o2 = post_ord(pid1)
    s1 = checkout(o1["id"])
    s2 = checkout(o2["id"])
    payload = {
        "product": pid1,
        "orders": [o1["id"], o2["id"]],
        "http": [s1[0], s2[0]],
        "amount": [
            (s1[1] or {}).get("amount_total") if isinstance(s1[1], dict) else None,
            (s2[1] or {}).get("amount_total") if isinstance(s2[1], dict) else None,
        ],
        "session": [
            (s1[1] or {}).get("checkoutSessionId") if isinstance(s1[1], dict) else None,
            (s2[1] or {}).get("checkoutSessionId") if isinstance(s2[1], dict) else None,
        ],
        "url": [
            (s1[1] or {}).get("checkoutUrl") if isinstance(s1[1], dict) else None,
            (s2[1] or {}).get("checkoutUrl") if isinstance(s2[1], dict) else None,
        ],
        "contract": [o1.get("contract_unit_cents"), o2.get("contract_unit_cents")],
    }
    (OUT / "RT_BLIND_INDEP_20260829_STRIPE_SESSIONS.json").write_text(
        json.dumps(payload, indent=2), encoding="utf-8"
    )
    for i, u in enumerate(payload["url"]):
        if u:
            (OUT / f"_pay_{i}.txt").write_text(u, encoding="utf-8")
            print("URL", i, "len", len(u))
    print(json.dumps({k: payload[k] for k in payload if k != "url"}, indent=2))


if __name__ == "__main__":
    main()
