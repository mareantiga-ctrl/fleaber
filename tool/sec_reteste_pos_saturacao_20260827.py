#!/usr/bin/env python3
"""Independent retest after saturation hardening. Staging only. No fixes. No SQL apply."""
from __future__ import annotations

import json
import os
import re
import ssl
import time
import uuid
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = ROOT / "tool" / "live_ops_staging.env"
CTX = ssl.create_default_context()
STAGING_REF = "fxdknzrqjenzqcvnwqqq"
BASE = f"https://{STAGING_REF}.supabase.co"
ANON = SVC = BUYER_EMAIL = BUYER_PASS = SELLER_EMAIL = SELLER_PASS = ""
BUYER_ID = SELLER_ID = ""
TAG = f"RETSAT-{int(time.time())}"
CATALOG_EUR = 40.00
CATALOG_CENTS = 4000
PROBES: list[dict[str, Any]] = []
CREATED: dict[str, list[str]] = {
    "products": [],
    "orders": [],
    "offers": [],
    "lives": [],
    "live_items": [],
    "reservations": [],
    "disputes": [],
    "reviews": [],
    "chats": [],
}


def load_env() -> None:
    global ANON, SVC, BUYER_EMAIL, BUYER_PASS, SELLER_EMAIL, SELLER_PASS, BUYER_ID, SELLER_ID
    kv: dict[str, str] = {}
    for line in ENV_PATH.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        kv[k.strip()] = v.strip()
    ANON = kv["SUPABASE_ANON_KEY"]
    SVC = kv["SUPABASE_SERVICE_ROLE_KEY"]
    BUYER_EMAIL = kv["LIVE_OPS_TEST_BUYER_EMAIL"]
    BUYER_PASS = kv["LIVE_OPS_TEST_BUYER_PASSWORD"]
    SELLER_EMAIL = kv["LIVE_OPS_TEST_SELLER_EMAIL"]
    SELLER_PASS = kv["LIVE_OPS_TEST_SELLER_PASSWORD"]
    BUYER_ID = kv["LIVE_OPS_TEST_BUYER_ID"]
    SELLER_ID = kv["LIVE_OPS_TEST_SELLER_ID"]
    url = kv.get("SUPABASE_URL", "")
    if STAGING_REF not in url and STAGING_REF not in BASE:
        raise SystemExit("refused: not staging")


def snip(obj: Any, n: int = 700) -> Any:
    s = json.dumps(obj, default=str, ensure_ascii=False)
    return s[:n]


def http(
    method: str,
    url: str,
    *,
    token: str | None = None,
    apikey: str | None = None,
    body: Any = None,
    extra: dict[str, str] | None = None,
    timeout: int = 60,
) -> tuple[int, Any]:
    key = apikey or ANON
    headers = {"Accept": "application/json", "apikey": key}
    headers["Authorization"] = f"Bearer {token or key}"
    if extra:
        headers.update(extra)
    data = None
    if body is not None:
        raw = body if isinstance(body, (bytes, bytearray)) else json.dumps(body).encode()
        data = raw
        headers.setdefault("Content-Type", "application/json")
        headers["Content-Length"] = str(len(raw))
    req = Request(url, data=data, headers=headers, method=method)
    try:
        with urlopen(req, timeout=timeout, context=CTX) as resp:
            raw = resp.read()
            try:
                parsed = json.loads(raw.decode("utf-8") or "null")
            except Exception:
                parsed = raw.decode("utf-8", errors="replace")[:4000]
            return resp.status, parsed
    except HTTPError as e:
        raw = e.read()
        try:
            parsed = json.loads(raw.decode("utf-8") or "null")
        except Exception:
            parsed = raw.decode("utf-8", errors="replace")[:4000]
        return e.code, parsed
    except URLError as e:
        return 0, {"error": str(e.reason)}


def rest(
    method: str,
    path: str,
    token: str | None,
    *,
    body: Any = None,
    qs: str = "",
    svc: bool = False,
    extra: dict[str, str] | None = None,
) -> tuple[int, Any]:
    key = SVC if svc else ANON
    headers = {"Prefer": "return=representation"}
    if extra:
        headers.update(extra)
    return http(
        method,
        f"{BASE}/rest/v1/{path.lstrip('/')}{qs}",
        token=token or key,
        apikey=key,
        body=body,
        extra=headers,
    )


def rpc(name: str, token: str | None, args: dict[str, Any] | None = None, *, svc: bool = False) -> tuple[int, Any]:
    key = SVC if svc else ANON
    return http(
        "POST",
        f"{BASE}/rest/v1/rpc/{name}",
        token=token or key,
        apikey=key,
        body=args or {},
    )


def edge(name: str, token: str | None, body: Any = None, *, method: str = "POST", qs: str = "", extra: dict[str, str] | None = None) -> tuple[int, Any]:
    return http(method, f"{BASE}/functions/v1/{name}{qs}", token=token or ANON, apikey=ANON, body=body, extra=extra)


def login(email: str, password: str) -> str:
    st, parsed = http(
        "POST",
        f"{BASE}/auth/v1/token?grant_type=password",
        apikey=ANON,
        token=ANON,
        body={"email": email, "password": password},
    )
    if st != 200 or not isinstance(parsed, dict) or "access_token" not in parsed:
        raise SystemExit(f"login failed {email}: {st} {parsed}")
    return str(parsed["access_token"])


def probe(name: str, **data: Any) -> None:
    rec = {"name": name, **data}
    PROBES.append(rec)
    print(f"  [{name}] st={data.get('status')} {data.get('note', '')}", flush=True)


def first_row(parsed: Any) -> dict[str, Any]:
    if isinstance(parsed, list) and parsed and isinstance(parsed[0], dict):
        return parsed[0]
    if isinstance(parsed, dict):
        return parsed
    return {}


def track(kind: str, parsed: Any) -> dict[str, Any]:
    row = first_row(parsed)
    if row.get("id"):
        CREATED.setdefault(kind, []).append(str(row["id"]))
    return row


def make_product(seller: str, price: float, qty: int, title: str) -> str | None:
    st, parsed = rest(
        "POST",
        "products",
        seller,
        body={
            "seller_id": SELLER_ID,
            "title": title,
            "price": price,
            "quantity": qty,
            "list_on_marketplace": False,
            "available_for_live": False,
            "state": "Bom",
            "category": "Outros",
            "description": TAG,
        },
    )
    probe("create_product", status=st, body=snip(parsed, 300), title=title)
    row = track("products", parsed)
    return str(row["id"]) if row.get("id") else None


def insert_order(token: str, body: dict[str, Any]) -> tuple[int, dict[str, Any]]:
    payload = {
        "buyer_id": BUYER_ID,
        "seller_id": SELLER_ID,
        "shipping_method": "Envio Transportadora (€3.50)",
        "payment_method": "Pagamento na App",
        "status": "reserva_pendente",
        "quantity": 1,
        **body,
    }
    st, parsed = rest("POST", "orders", token, body=payload)
    row = track("orders", parsed) if st in (200, 201) else first_row(parsed)
    if st not in (200, 201):
        row = {"_error": parsed} if not row else {**row, "_error": parsed}
    return st, row


def checkout(token: str | None, body: dict[str, Any]) -> tuple[int, Any]:
    return edge("create-payment-intent", token, body)


def amounts(parsed: Any) -> dict[str, Any]:
    if not isinstance(parsed, dict):
        return {"raw": snip(parsed, 400)}
    return {
        "status_body": parsed.get("status") or parsed.get("ok"),
        "error": parsed.get("error") or parsed.get("message"),
        "server_amount_cents": parsed.get("server_amount_cents"),
        "amount_total": parsed.get("amount_total"),
        "session_id": parsed.get("session_id") or parsed.get("id"),
        "url": parsed.get("url") or parsed.get("checkout_url"),
        "snip": snip(parsed, 500),
    }


def get_order(token: str, oid: str, cols: str = "*") -> dict[str, Any]:
    st, parsed = rest("GET", "orders", token, qs=f"?id=eq.{oid}&select={cols}")
    return first_row(parsed) if st == 200 else {"_st": st, "_error": parsed}


def err_text(parsed: Any) -> str:
    if isinstance(parsed, dict):
        return str(parsed.get("message") or parsed.get("hint") or parsed.get("error") or parsed)[:400]
    return str(parsed)[:400]


# ---------------------------------------------------------------------------
# 2 P0 contract_unit_cents
# ---------------------------------------------------------------------------
def test_p0_contract(buyer: str, seller: str, pid: str) -> dict[str, Any]:
    out: dict[str, Any] = {"variants": []}
    variants: list[tuple[str, Any]] = [
        ("1", 1),
        ("50", 50),
        ("100", 100),
        ("null", None),
        ("neg", -50),
        ("huge", 9_999_999),
        ("omit", "__omit__"),
        ("str50", "50"),
    ]
    for name, val in variants:
        body: dict[str, Any] = {
            "product_id": pid,
            "price_total": 0.50,
        }
        if val != "__omit__":
            body["contract_unit_cents"] = val
        st, row = insert_order(buyer, body)
        rec = {
            "variant": name,
            "insert_st": st,
            "persisted_contract": row.get("contract_unit_cents"),
            "persisted_qty": row.get("contract_qty"),
            "quantity": row.get("quantity"),
            "status": row.get("status"),
            "oid": row.get("id"),
            "err": err_text(row.get("_error")) if st not in (200, 201) else None,
        }
        if row.get("id"):
            stc, pc = checkout(buyer, {
                "order_id": row["id"],
                "buyer_id": BUYER_ID,
                "shipping_method": "hand",
                "amount": 1,
            })
            rec["checkout_st"] = stc
            rec["checkout"] = amounts(pc)
        out["variants"].append(rec)
        probe(f"p0_contract_{name}", status=st, note=snip(rec, 350))
    cheap = next((v for v in out["variants"] if v.get("persisted_contract") in (1, 50, 100)), None)
    catalogish = next(
        (v for v in out["variants"] if v.get("insert_st") in (200, 201) and v.get("persisted_contract") == CATALOG_CENTS),
        None,
    )
    jwt_controls = bool(cheap) and any(
        (v.get("checkout") or {}).get("amount_total") is not None
        and int((v.get("checkout") or {}).get("amount_total") or 999999) < 1000
        for v in out["variants"]
        if v.get("persisted_contract") in (1, 50, 100)
    )
    out["jwt_controls_stripe"] = jwt_controls
    out["catalog_seal_seen"] = catalogish is not None
    # catalog hike after seal
    oid = (catalogish or next((v for v in out["variants"] if v.get("oid")), {})).get("oid")
    if oid:
        rest("PATCH", "products", seller, qs=f"?id=eq.{pid}", body={"price": 99.00})
        stc, pc = checkout(buyer, {"order_id": oid, "buyer_id": BUYER_ID, "shipping_method": "hand"})
        out["after_catalog_hike"] = amounts(pc)
        rest("PATCH", "products", seller, qs=f"?id=eq.{pid}", body={"price": CATALOG_EUR})
        probe("p0_catalog_hike", status=stc, body=snip(pc, 400))
    return out


# ---------------------------------------------------------------------------
# 3 P0 propostas
# ---------------------------------------------------------------------------
def test_p0_proposta(buyer: str, seller: str, pid: str) -> dict[str, Any]:
    out: dict[str, Any] = {"string_spoof": [], "entity": {}}
    strings = [
        "Proposta aceite",
        "proposta",
        "xproposta",
        "  Proposta aceite  ",
        "PROPOSTA ACEITE",
        "proposta\u00a0aceite",
    ]
    for s in strings:
        st, row = insert_order(buyer, {
            "product_id": pid,
            "payment_method": s,
            "price_total": 0.50,
        })
        rec = {
            "pm": s,
            "st": st,
            "contract": row.get("contract_unit_cents"),
            "oid": row.get("id"),
            "err": err_text(row.get("_error")) if st not in (200, 201) else None,
        }
        if row.get("id"):
            stc, pc = checkout(buyer, {"order_id": row["id"], "buyer_id": BUYER_ID, "shipping_method": "hand", "amount": 50})
            rec["checkout"] = amounts(pc)
        out["string_spoof"].append(rec)
        probe("p0_proposta_str", status=st, note=snip(rec, 280))

    # buyer create accepted offer
    st, parsed = rest("POST", "product_offers", buyer, body={
        "product_id": pid,
        "buyer_id": BUYER_ID,
        "seller_id": SELLER_ID,
        "amount": 0.50,
        "status": "accepted",
        "offered_by": "buyer",
        "responded_at": "2026-01-01T00:00:00Z",
    })
    offer_acc = track("offers", parsed)
    out["buyer_insert_accepted"] = {"st": st, "status": offer_acc.get("status"), "amount": offer_acc.get("amount"), "id": offer_acc.get("id"), "err": snip(parsed, 250)}
    probe("buyer_insert_offer_accepted", status=st, body=snip(parsed, 300))

    # pending offer then buyer self-accept
    st, parsed = rest("POST", "product_offers", buyer, body={
        "product_id": pid,
        "buyer_id": BUYER_ID,
        "seller_id": SELLER_ID,
        "amount": 1.00,
        "status": "pending",
        "offered_by": "buyer",
    })
    offer_p = track("offers", parsed)
    out["buyer_insert_pending"] = {"st": st, "status": offer_p.get("status"), "id": offer_p.get("id")}
    if offer_p.get("id"):
        st2, p2 = rest("PATCH", "product_offers", buyer, qs=f"?id=eq.{offer_p['id']}", body={"status": "accepted", "responded_at": "2026-08-27T00:00:00Z"})
        row2 = first_row(p2)
        out["buyer_self_accept"] = {"st": st2, "status": row2.get("status"), "body": snip(p2, 300)}
        probe("buyer_self_accept_offer", status=st2, body=snip(p2, 300))

        # order with pending offer id
        st3, row3 = insert_order(buyer, {"product_id": pid, "product_offer_id": offer_p["id"], "price_total": 1.00})
        out["order_pending_offer"] = {"st": st3, "contract": row3.get("contract_unit_cents"), "offer_id": row3.get("product_offer_id"), "oid": row3.get("id")}
        if row3.get("id"):
            stc, pc = checkout(buyer, {"order_id": row3["id"], "buyer_id": BUYER_ID, "shipping_method": "hand"})
            out["order_pending_offer"]["checkout"] = amounts(pc)

        # legitimate seller accept
        st4, p4 = rest("PATCH", "product_offers", seller, qs=f"?id=eq.{offer_p['id']}", body={"status": "accepted"})
        row4 = first_row(p4)
        out["seller_accept"] = {"st": st4, "status": row4.get("status"), "amount": row4.get("amount"), "responded_at": row4.get("responded_at"), "body": snip(p4, 300)}
        probe("seller_accept_offer", status=st4, body=snip(p4, 300))
        if str(row4.get("status") or "").lower() == "accepted":
            st5, row5 = insert_order(buyer, {"product_id": pid, "product_offer_id": offer_p["id"], "price_total": 99})
            out["order_after_legit_accept"] = {
                "st": st5,
                "contract": row5.get("contract_unit_cents"),
                "offer_id": row5.get("product_offer_id"),
                "oid": row5.get("id"),
            }
            if row5.get("id"):
                stc, pc = checkout(buyer, {"order_id": row5["id"], "buyer_id": BUYER_ID, "shipping_method": "hand"})
                out["order_after_legit_accept"]["checkout"] = amounts(pc)
                probe("legit_offer_checkout", status=stc, body=snip(pc, 400))

    # rejected offer
    st, parsed = rest("POST", "product_offers", buyer, body={
        "product_id": pid, "buyer_id": BUYER_ID, "seller_id": SELLER_ID, "amount": 0.50, "status": "pending", "offered_by": "buyer",
    })
    off_r = track("offers", parsed)
    if off_r.get("id"):
        rest("PATCH", "product_offers", seller, qs=f"?id=eq.{off_r['id']}", body={"status": "rejected"})
        st6, row6 = insert_order(buyer, {"product_id": pid, "product_offer_id": off_r["id"], "price_total": 0.50})
        out["order_rejected_offer"] = {"st": st6, "contract": row6.get("contract_unit_cents"), "offer_id": row6.get("product_offer_id")}
        if row6.get("id"):
            stc, pc = checkout(buyer, {"order_id": row6["id"], "buyer_id": BUYER_ID, "shipping_method": "hand"})
            out["order_rejected_offer"]["checkout"] = amounts(pc)

    # expired offer via svc fixture
    st, parsed = rest("POST", "product_offers", buyer, body={
        "product_id": pid, "buyer_id": BUYER_ID, "seller_id": SELLER_ID, "amount": 2.00, "status": "pending", "offered_by": "buyer",
    })
    off_e = track("offers", parsed)
    if off_e.get("id"):
        rest("PATCH", "product_offers", None, qs=f"?id=eq.{off_e['id']}", svc=True, body={
            "status": "accepted", "responded_at": "2020-01-01T00:00:00Z", "expires_at": "2020-01-02T00:00:00Z",
        })
        st7, row7 = insert_order(buyer, {"product_id": pid, "product_offer_id": off_e["id"], "price_total": 2.00})
        out["order_expired_offer"] = {"st": st7, "contract": row7.get("contract_unit_cents"), "offer_id": row7.get("product_offer_id")}
        if row7.get("id"):
            stc, pc = checkout(buyer, {"order_id": row7["id"], "buyer_id": BUYER_ID, "shipping_method": "hand"})
            out["order_expired_offer"]["checkout"] = amounts(pc)

    # other-product offer
    pid2 = make_product(seller, 25.00, 3, f"{TAG} other prod 25")
    if pid2 and offer_p.get("id") and str(out.get("seller_accept", {}).get("status") or "").lower() == "accepted":
        st8, row8 = insert_order(buyer, {"product_id": pid2, "product_offer_id": offer_p["id"], "price_total": 1.00})
        out["offer_other_product"] = {"st": st8, "contract": row8.get("contract_unit_cents"), "offer_id": row8.get("product_offer_id"), "product": pid2}
        if row8.get("id"):
            stc, pc = checkout(buyer, {"order_id": row8["id"], "buyer_id": BUYER_ID, "shipping_method": "hand"})
            out["offer_other_product"]["checkout"] = amounts(pc)

    # fake uuid offer
    st9, row9 = insert_order(buyer, {"product_id": pid, "product_offer_id": str(uuid.uuid4()), "price_total": 0.50})
    out["offer_nonexistent"] = {"st": st9, "contract": row9.get("contract_unit_cents"), "offer_id": row9.get("product_offer_id"), "err": err_text(row9.get("_error"))}

    # seller offer to buyer then buyer accept (legit counterparty)
    st, parsed = rest("POST", "product_offers", seller, body={
        "product_id": pid, "buyer_id": BUYER_ID, "seller_id": SELLER_ID, "amount": 12.00, "status": "pending", "offered_by": "seller",
    })
    off_s = track("offers", parsed)
    out["seller_insert_offer"] = {"st": st, "status": off_s.get("status"), "id": off_s.get("id")}
    if off_s.get("id"):
        st10, p10 = rest("PATCH", "product_offers", buyer, qs=f"?id=eq.{off_s['id']}", body={"status": "accepted"})
        row10 = first_row(p10)
        out["buyer_accept_seller_offer"] = {"st": st10, "status": row10.get("status"), "amount": row10.get("amount")}
        if str(row10.get("status") or "").lower() == "accepted":
            st11, row11 = insert_order(buyer, {"product_id": pid, "product_offer_id": off_s["id"]})
            out["order_seller_offer"] = {"st": st11, "contract": row11.get("contract_unit_cents"), "oid": row11.get("id")}
            if row11.get("id"):
                stc, pc = checkout(buyer, {"order_id": row11["id"], "buyer_id": BUYER_ID, "shipping_method": "hand"})
                out["order_seller_offer"]["checkout"] = amounts(pc)

    fake_strings_win = any(
        (r.get("contract") in (50, 1) or ((r.get("checkout") or {}).get("amount_total") is not None and int((r.get("checkout") or {}).get("amount_total") or 99999) < 1000))
        and (r.get("contract") not in (None, CATALOG_CENTS, 1200, 2500))
        for r in out["string_spoof"]
        if r.get("st") in (200, 201)
    )
    # 12€ seller offer = 1200 cents is legit
    out["fake_proposta_changes_contract"] = bool(fake_strings_win)
    return out


# ---------------------------------------------------------------------------
# 4 qty
# ---------------------------------------------------------------------------
def test_p0_qty(buyer: str, seller: str, pid: str) -> dict[str, Any]:
    out: dict[str, Any] = {"cases": []}
    cases = [
        ("q5_c1", {"quantity": 5, "contract_qty": 1}),
        ("q1_c5", {"quantity": 1, "contract_qty": 5}),
        ("q1_c8", {"quantity": 1, "contract_qty": 8, "contract_unit_cents": 50}),
        ("omit_c", {"quantity": 3}),
        ("omit_q", {"contract_qty": 4}),
        ("q0", {"quantity": 0}),
        ("qneg", {"quantity": -1}),
        ("q100", {"quantity": 100}),
        ("q9999", {"quantity": 9999}),
        ("q8_stock8", {"quantity": 8}),
        ("q9_overstock", {"quantity": 9}),
    ]
    for name, extra in cases:
        st, row = insert_order(buyer, {"product_id": pid, "price_total": CATALOG_EUR, **extra})
        rec = {
            "name": name,
            "st": st,
            "quantity": row.get("quantity"),
            "contract_qty": row.get("contract_qty"),
            "contract_unit": row.get("contract_unit_cents"),
            "oid": row.get("id"),
            "err": err_text(row.get("_error")) if st not in (200, 201) else None,
        }
        if row.get("id"):
            stc, pc = checkout(buyer, {"order_id": row["id"], "buyer_id": BUYER_ID, "shipping_method": "hand"})
            rec["checkout"] = amounts(pc)
        out["cases"].append(rec)
        probe(f"qty_{name}", status=st, note=snip(rec, 280))

    # UPDATE after insert
    st, row = insert_order(buyer, {"product_id": pid, "quantity": 1})
    if row.get("id"):
        st2, p2 = rest("PATCH", "orders", buyer, qs=f"?id=eq.{row['id']}", body={"quantity": 5, "contract_qty": 5, "contract_unit_cents": 50})
        after = first_row(p2) or get_order(buyer, row["id"], "id,quantity,contract_qty,contract_unit_cents")
        out["buyer_update_qty"] = {"st": st2, "before": {"q": row.get("quantity"), "cq": row.get("contract_qty")}, "after": {"q": after.get("quantity"), "cq": after.get("contract_qty"), "c": after.get("contract_unit_cents")}}
        st3, p3 = rest("PATCH", "orders", seller, qs=f"?id=eq.{row['id']}", body={"quantity": 7, "contract_qty": 7})
        afters = first_row(p3) or get_order(seller, row["id"], "id,quantity,contract_qty")
        out["seller_update_qty"] = {"st": st3, "after": {"q": afters.get("quantity"), "cq": afters.get("contract_qty")}}
        probe("qty_update", status=st2, body=snip(out["buyer_update_qty"]))

    # bag two lines
    st_a, a = insert_order(buyer, {"product_id": pid, "quantity": 1, "contract_unit_cents": 100, "contract_qty": 1})
    pid_b = make_product(seller, 25.00, 4, f"{TAG} bag 25")
    st_b, b = insert_order(buyer, {"product_id": pid_b, "quantity": 1, "contract_unit_cents": 100}) if pid_b else (0, {})
    out["bag"] = {"a": {"st" : st_a, "c": a.get("contract_unit_cents"), "id": a.get("id")}, "b": {"st": st_b, "c": b.get("contract_unit_cents"), "id": b.get("id")}}
    if a.get("id") and b.get("id"):
        stc, pc = checkout(buyer, {
            "bag_checkout": True,
            "bag_lines": [{"order_id": a["id"]}, {"order_id": b["id"]}],
            "shipping_method": "carrier",
            "amount": 50,
            "buyer_id": BUYER_ID,
        })
        out["bag"]["checkout"] = amounts(pc)
        probe("bag_checkout", status=stc, body=snip(pc, 400))
    diverge = False
    for c in out["cases"]:
        if c.get("st") in (200, 201) and c.get("quantity") is not None and c.get("contract_qty") is not None:
            if int(c["quantity"]) != int(c["contract_qty"]):
                diverge = True
        chk = (c.get("checkout") or {}).get("amount_total")
        if c.get("name") == "q1_c8" and c.get("contract_qty") == 8 and chk and int(chk) < 2000:
            diverge = True
    out["qty_charged_diverges"] = diverge
    return out


# ---------------------------------------------------------------------------
# 5 flags
# ---------------------------------------------------------------------------
FLAG_PAYLOAD = {
    "stock_units_applied": 9,
    "wallet_release_processed_at": "2020-01-01T00:00:00Z",
    "wallet_refund_processed_at": "2020-01-01T00:00:00Z",
    "auto_feedback_processed_at": "2020-01-01T00:00:00Z",
    "completed_at": "2020-01-01T00:00:00Z",
    "returned_at": "2020-01-01T00:00:00Z",
    "amount_paid_cents": 12,
    "stripe_checkout_session_id": "cs_test_fake",
    "stripe_payment_intent_id": "pi_fake",
    "stripe_refund_id": "re_fake",
    "stripe_refunded_at": "2020-01-01T00:00:00Z",
    "contract_unit_cents": 50,
    "contract_qty": 9,
    "status": "pago",
}


def test_flags(buyer: str, seller: str, pid: str, order_cols: list[str]) -> dict[str, Any]:
    extra_flag_names = [
        c for c in order_cols
        if any(x in c for x in ("processed_at", "_applied", "_settled", "_verified", "_confirmed", "amount_paid", "stripe_"))
    ]
    payload = {**FLAG_PAYLOAD, "product_id": pid, "price_total": 1, "quantity": 1}
    for c in extra_flag_names:
        if c not in payload and c not in {"id", "created_at", "updated_at", "buyer_id", "seller_id", "product_id"}:
            if c.endswith("_at"):
                payload[c] = "2020-01-01T00:00:00Z"
            elif c.endswith("_cents") or c.endswith("_qty") or c.endswith("_applied"):
                payload[c] = 1
    st, row = insert_order(buyer, payload)
    interesting = {k: row.get(k) for k in FLAG_PAYLOAD if k in row or True}
    interesting = {k: row.get(k) for k in list(FLAG_PAYLOAD.keys()) + extra_flag_names}
    out = {"insert_st": st, "after_insert": interesting, "oid": row.get("id"), "err": err_text(row.get("_error")) if st not in (200, 201) else None, "extra_cols_tried": extra_flag_names}
    probe("flags_insert", status=st, body=snip(interesting, 500))
    oid = row.get("id")
    if oid:
        st2, p2 = rest("PATCH", "orders", buyer, qs=f"?id=eq.{oid}", body=FLAG_PAYLOAD)
        after = first_row(p2) or get_order(buyer, oid)
        out["buyer_update"] = {k: after.get(k) for k in FLAG_PAYLOAD}
        st3, p3 = rest("PATCH", "orders", seller, qs=f"?id=eq.{oid}", body=FLAG_PAYLOAD)
        afters = first_row(p3) or get_order(seller, oid)
        out["seller_update"] = {k: afters.get(k) for k in FLAG_PAYLOAD}
        probe("flags_update", status=st2, body=snip(out["buyer_update"], 400))
    premarked = False
    src = out.get("after_insert") or {}
    if src.get("amount_paid_cents") not in (None, 0):
        premarked = True
    if src.get("wallet_release_processed_at"):
        premarked = True
    if src.get("stock_units_applied") not in (None, 0):
        premarked = True
    if src.get("stripe_payment_intent_id"):
        premarked = True
    if (out.get("buyer_update") or {}).get("amount_paid_cents") not in (None, 0) and FLAG_PAYLOAD["amount_paid_cents"] == (out.get("buyer_update") or {}).get("amount_paid_cents"):
        premarked = True
    out["jwt_premarks_privileged"] = premarked
    return out


# ---------------------------------------------------------------------------
# 6 lab RPCs
# ---------------------------------------------------------------------------
def openapi_rpcs() -> list[str]:
    st, parsed = http(
        "GET",
        f"{BASE}/rest/v1/",
        token=ANON,
        apikey=ANON,
        extra={"Accept": "application/openapi+json"},
    )
    names: list[str] = []
    if isinstance(parsed, dict):
        paths = parsed.get("paths") or {}
        for p in paths:
            m = re.search(r"/rpc/([A-Za-z0-9_]+)", str(p))
            if m:
                names.append(m.group(1))
    probe("openapi_rpcs", status=st, note=f"count={len(names)}")
    return sorted(set(names))


def test_lab_rpcs(buyer: str, seller: str, rpc_names: list[str]) -> dict[str, Any]:
    needles = ("lab", "staging", "test", "nuke", "seed", "clear", "reset", "repair", "debug", "e2e", "feedback", "demo")
    labish = [n for n in rpc_names if any(x in n.lower() for x in needles)]
    explicit = [
        "batata_lab_clear_all_fm_pending",
        "batata_lab_clear_fm_pending",
        "batata_generate_auto_feedback",
        "batata_staging_h_v1_ux_demo_seed",
        "batata_staging_set_fleahub_test_state",
        "staging_nuke_user_data",
        "staging_restore_stock_before_nuke",
        "batata_expire_product_offers",
    ]
    targets = sorted(set(labish + explicit))
    out: dict[str, Any] = {"targets": targets, "results": []}
    executable = []
    for name in targets:
        arg_sets: list[dict[str, Any]] = [
            {},
            {"p_now": "2099-01-01T00:00:00Z"},
            {"p_user_id": BUYER_ID},
            {"p_seller_id": SELLER_ID},
        ]
        for role, tok in [("anon", None), ("buyer", buyer), ("seller", seller)]:
            for args in arg_sets:
                st, parsed = rpc(name, tok, args)
                rec = {"name": name, "role": role, "st": st, "args": args, "body": snip(parsed, 180)}
                out["results"].append(rec)
                if st == 200:
                    executable.append(rec)
                    probe(f"lab_{role}_{name}", status=st, body=snip(parsed, 200))
                if st not in (404, 400, 415):
                    break
            else:
                continue
            break
    out["jwt_or_anon_executable"] = executable
    probe("lab_rpc_summary", status=len(executable), note=f"exec={len(executable)} targets={len(targets)}")
    return out


# ---------------------------------------------------------------------------
# 7 payment method / state machine
# ---------------------------------------------------------------------------
def test_payment_machine(buyer: str, seller: str, pid: str) -> dict[str, Any]:
    out: dict[str, Any] = {"methods": [], "platform_unpaid": {}, "offplat": {}}
    methods = [
        "",
        " ",
        None,
        "pix",
        "mbwy",
        "MB WAY",
        "mb way",
        "Pagamento direto ao vendedor (MB WAY/Transf)",
        "Pagamento na App",
        "Seguro Fleaber",
        "plataforma",
        "transferencia",
    ]
    oids: dict[str, str] = {}
    for pm in methods:
        body: dict[str, Any] = {"product_id": pid, "quantity": 1}
        if pm is None:
            body["payment_method"] = None
        else:
            body["payment_method"] = pm
        st, row = insert_order(buyer, body)
        rec = {"pm": pm, "st": st, "stored_pm": row.get("payment_method"), "status": row.get("status"), "oid": row.get("id"), "err": err_text(row.get("_error")) if st not in (200, 201) else None}
        if row.get("id"):
            oids[str(pm)] = row["id"]
        out["methods"].append(rec)
        probe("pm_insert", status=st, note=snip(rec, 200))

    def try_statuses(oid: str, token: str, role: str) -> list[dict[str, Any]]:
        res = []
        for stt in ["pago", "enviado", "entregue", "concluido", "review", "devolvida", "cancelado", "pedido_devolucao"]:
            before = get_order(token, oid, "id,status,amount_paid_cents,payment_method")
            st, parsed = rest("PATCH", "orders", token, qs=f"?id=eq.{oid}", body={"status": stt})
            after = first_row(parsed) or get_order(token, oid, "id,status,amount_paid_cents")
            res.append({"role": role, "want": stt, "st": st, "before": before.get("status"), "after": after.get("status")})
        return res

    plat_oid = oids.get("Pagamento na App") or oids.get("Seguro Fleaber") or oids.get("")
    if plat_oid:
        out["platform_unpaid"]["buyer"] = try_statuses(plat_oid, buyer, "buyer")
        # fresh for seller
        st, row = insert_order(buyer, {"product_id": pid, "payment_method": "Pagamento na App"})
        if row.get("id"):
            out["platform_unpaid"]["seller"] = try_statuses(row["id"], seller, "seller")
            probe("platform_unpaid_seller", status=st, body=snip(out["platform_unpaid"]["seller"], 400))

    # off-platform legit
    st, row = insert_order(buyer, {"product_id": pid, "payment_method": "Pagamento direto ao vendedor (MB WAY/Transf)", "quantity": 1})
    out["offplat"]["insert"] = {"st": st, "oid": row.get("id"), "pm": row.get("payment_method"), "status": row.get("status")}
    if row.get("id"):
        st2, p2 = rest("PATCH", "orders", seller, qs=f"?id=eq.{row['id']}", body={"status": "pago"})
        after = first_row(p2) or get_order(seller, row["id"], "id,status,amount_paid_cents,wallet_release_processed_at,stock_units_applied,quantity,contract_qty")
        out["offplat"]["seller_pago"] = {"st": st2, "after": after}
        # wallet mint?
        stw, pw = rest("GET", "wallet_transactions", seller, qs=f"?order_id=eq.{row['id']}&select=id,amount,type,order_id")
        if stw != 200:
            stw, pw = rest("GET", "wallet_transactions", None, qs=f"?order_id=eq.{row['id']}&select=id,amount,type,order_id", svc=True)
        out["offplat"]["wallet_tx"] = {"st": stw, "rows": snip(pw, 300)}
        # stock after pago
        stp, pp = rest("GET", "products", seller, qs=f"?id=eq.{pid}&select=id,quantity")
        out["offplat"]["stock_after_pago"] = first_row(pp)
        st3, p3 = rest("PATCH", "orders", seller, qs=f"?id=eq.{row['id']}", body={"status": "enviado"})
        after3 = first_row(p3) or get_order(seller, row["id"], "id,status")
        out["offplat"]["seller_enviado"] = {"st": st3, "status": after3.get("status")}
        probe("offplat_pago", status=st2, body=snip(after, 400))

    plat_fake_pago = False
    for role_runs in (out["platform_unpaid"].get("buyer") or []) + (out["platform_unpaid"].get("seller") or []):
        if role_runs.get("want") in ("pago", "enviado", "entregue", "concluido") and str(role_runs.get("after") or "").lower() == role_runs["want"]:
            plat_fake_pago = True
    out["platform_can_fake_paid"] = plat_fake_pago
    off = out["offplat"].get("seller_pago", {}).get("after") or {}
    minted = False
    w = out["offplat"].get("wallet_tx", {}).get("rows")
    if isinstance(w, list) and w:
        minted = True
    if isinstance(out["offplat"].get("wallet_tx", {}).get("rows"), str) and '"id"' in str(w) and "[]" not in str(w)[:4]:
        minted = "[]" not in str(out["offplat"]["wallet_tx"]["rows"])[:10] and "id" in str(out["offplat"]["wallet_tx"]["rows"])
    out["offplatform_mints_fleaber"] = bool(off.get("amount_paid_cents")) or minted
    return out


# ---------------------------------------------------------------------------
# 8 live / reservations
# ---------------------------------------------------------------------------
def test_live(buyer: str, seller: str, pid: str) -> dict[str, Any]:
    out: dict[str, Any] = {"rule": {}, "attacks": {}}
    st, live = rest("POST", "lives", seller, body={
        "seller_id": SELLER_ID,
        "vendedor_id": SELLER_ID,
        "title": f"{TAG} live fixture",
        "status": "ended",
        "is_active": False,
    })
    live_row = track("lives", live)
    out["live_insert"] = {"st": st, "id": live_row.get("id"), "err": snip(live, 250) if st not in (200, 201) else None}
    lid = live_row.get("id")
    if not lid:
        probe("live_insert_fail", status=st, body=snip(live, 400))
        return out
    st, item = rest("POST", "live_items", seller, body={
        "live_id": lid,
        "ref_code": f"R{int(time.time()) % 10000}",
        "title": f"{TAG} item",
        "price": CATALOG_EUR,
        "product_id": pid,
        "is_active": True,
    })
    item_row = track("live_items", item)
    out["item_insert"] = {"st": st, "id": item_row.get("id"), "err": snip(item, 250) if st not in (200, 201) else None}
    iid = item_row.get("id")
    if not iid:
        return out

    def res_insert(token: str, body: dict[str, Any]) -> tuple[int, dict[str, Any]]:
        payload = {
            "live_id": lid,
            "live_item_id": iid,
            "seller_id": SELLER_ID,
            "buyer_id": BUYER_ID,
            "requested_qty": 1,
            "source": "fleaber_live",
            **body,
        }
        st, parsed = rest("POST", "live_reservation_requests", token, body=payload)
        row = track("reservations", parsed) if st in (200, 201) else first_row(parsed)
        if st not in (200, 201):
            row = {**row, "_error": parsed}
        return st, row

    st, r1 = res_insert(buyer, {"requested_qty": 99, "status": "accepted"})
    out["attacks"]["buyer_insert_accepted_qty99"] = {"st": st, "status": r1.get("status"), "qty": r1.get("requested_qty"), "qpos": r1.get("queue_position"), "id": r1.get("id"), "err": err_text(r1.get("_error"))}
    probe("res_buyer_accepted99", status=st, body=snip(out["attacks"]["buyer_insert_accepted_qty99"]))

    # pending then self-accept
    st, r2 = res_insert(buyer, {"requested_qty": 1, "status": "pending"})
    out["attacks"]["buyer_insert_pending"] = {"st": st, "status": r2.get("status"), "qty": r2.get("requested_qty"), "qpos": r2.get("queue_position"), "id": r2.get("id")}
    if r2.get("id"):
        st2, p2 = rest("PATCH", "live_reservation_requests", buyer, qs=f"?id=eq.{r2['id']}", body={"status": "accepted"})
        after = first_row(p2)
        # re-get
        stg, pg = rest("GET", "live_reservation_requests", buyer, qs=f"?id=eq.{r2['id']}&select=*")
        after = first_row(pg) or after
        out["attacks"]["buyer_pending_to_accepted"] = {"st": st2, "status": after.get("status"), "body": snip(p2, 250)}
        st3, p3 = rest("PATCH", "live_reservation_requests", buyer, qs=f"?id=eq.{r2['id']}", body={"queue_position": 1, "requested_qty": 50})
        stg, pg = rest("GET", "live_reservation_requests", buyer, qs=f"?id=eq.{r2['id']}&select=*")
        after3 = first_row(pg)
        out["attacks"]["buyer_patch_qpos_qty"] = {"st": st3, "qty": after3.get("requested_qty"), "qpos": after3.get("queue_position")}

    for qty in (0, -1, 100, 9999):
        st, r = res_insert(buyer, {"requested_qty": qty, "status": "pending"})
        out["attacks"][f"qty_{qty}"] = {"st": st, "qty": r.get("requested_qty"), "status": r.get("status"), "err": err_text(r.get("_error"))}

    # jump queue
    st, r3 = res_insert(buyer, {"requested_qty": 1, "status": "pending", "queue_position": 1})
    out["attacks"]["buyer_insert_qpos1"] = {"st": st, "qpos": r3.get("queue_position"), "status": r3.get("status"), "id": r3.get("id")}

    # seller accept legit pending
    pending_id = (out["attacks"].get("buyer_insert_pending") or {}).get("id")
    if pending_id:
        st4, p4 = rpc("batata_process_live_reservation_request", seller, {"p_request_id": pending_id, "p_action": "accept"})
        out["attacks"]["seller_rpc_accept"] = {"st": st4, "body": snip(p4, 400)}
        probe("seller_accept_res", status=st4, body=snip(p4, 300))
        stg, pg = rest("GET", "live_reservation_requests", seller, qs=f"?id=eq.{pending_id}&select=*")
        acc = first_row(pg)
        out["attacks"]["after_seller_accept"] = {"status": acc.get("status"), "qty": acc.get("requested_qty")}
        # buyer order from live item exceeding reservation
        st5, o5 = insert_order(buyer, {"product_id": pid, "live_item_id": iid, "live_id": lid, "quantity": 8})
        out["attacks"]["order_qty_gt_res"] = {"st": st5, "q": o5.get("quantity"), "cq": o5.get("contract_qty"), "err": err_text(o5.get("_error")), "oid": o5.get("id")}
        st6, o6 = insert_order(buyer, {"product_id": pid, "live_item_id": iid, "live_id": lid, "quantity": 1})
        out["attacks"]["order_qty_ok"] = {"st": st6, "q": o6.get("quantity"), "cq": o6.get("contract_qty"), "contract": o6.get("contract_unit_cents"), "oid": o6.get("id")}
        if o6.get("id"):
            stc, pc = checkout(buyer, {"order_id": o6["id"], "buyer_id": BUYER_ID, "shipping_method": "hand"})
            out["attacks"]["order_qty_ok"]["checkout"] = amounts(pc)

        st7, p7 = rpc("batata_live_bag_update_qty", buyer, {"p_request_id": pending_id, "p_qty": 50})
        out["attacks"]["bag_update_qty"] = {"st": st7, "body": snip(p7, 300)}

    # two last-unit reservations (waitlist) — product qty 1 fixture
    pid_last = make_product(seller, 15.00, 1, f"{TAG} last unit")
    if pid_last:
        st, item2 = rest("POST", "live_items", seller, body={
            "live_id": lid, "ref_code": f"L{int(time.time()) % 10000}", "title": "last", "price": 15, "product_id": pid_last, "is_active": True,
        })
        i2 = track("live_items", item2).get("id")
        if i2:
            st_a, ra = rest("POST", "live_reservation_requests", buyer, body={
                "live_id": lid, "live_item_id": i2, "seller_id": SELLER_ID, "buyer_id": BUYER_ID, "requested_qty": 1, "source": "fleaber_live", "status": "pending",
            })
            track("reservations", ra)
            st_b, rb = rest("POST", "live_reservation_requests", buyer, body={
                "live_id": lid, "live_item_id": i2, "seller_id": SELLER_ID, "buyer_id": BUYER_ID, "requested_qty": 1, "source": "fleaber_live", "status": "pending",
            })
            track("reservations", rb)
            out["attacks"]["two_pending_last_unit"] = {
                "a": {"st" : st_a, "id": first_row(ra).get("id"), "status": first_row(ra).get("status")},
                "b": {"st": st_b, "id": first_row(rb).get("id"), "status": first_row(rb).get("status"), "err": snip(rb, 200)},
            }
            # seller accept first then try convert both to paid orders
            ida = first_row(ra).get("id")
            if ida:
                rpc("batata_process_live_reservation_request", seller, {"p_request_id": ida, "p_action": "accept"})
                st_o, o = insert_order(buyer, {"product_id": pid_last, "live_item_id": i2, "live_id": lid, "quantity": 1})
                out["attacks"]["order_from_accepted_last"] = {"st" : st_o, "oid": o.get("id"), "contract": o.get("contract_unit_cents")}

    buyer_auto = False
    a99 = out["attacks"].get("buyer_insert_accepted_qty99") or {}
    if str(a99.get("status") or "").lower() == "accepted":
        buyer_auto = True
    p2a = out["attacks"].get("buyer_pending_to_accepted") or {}
    if str(p2a.get("status") or "").lower() == "accepted":
        buyer_auto = True
    out["buyer_can_self_accept"] = buyer_auto
    qjump = out["attacks"].get("buyer_insert_qpos1") or {}
    out["buyer_forced_queue_pos"] = qjump.get("qpos") == 1 and qjump.get("st") in (200, 201)
    out["waitlist_two_pending_allowed"] = bool((out["attacks"].get("two_pending_last_unit") or {}).get("a", {}).get("id"))
    return out


# ---------------------------------------------------------------------------
# 9 phone
# ---------------------------------------------------------------------------
def test_phone(buyer: str, seller: str) -> dict[str, Any]:
    out: dict[str, Any] = {}
    st0, p0 = rest("GET", "profiles", buyer, qs=f"?id=eq.{BUYER_ID}&select=id,phone_verified_at,user_type")
    before = first_row(p0)
    out["before"] = before
    for who, tok, uid in [("buyer", buyer, BUYER_ID), ("seller", seller, SELLER_ID)]:
        tries = []
        for val in ["2020-01-01T00:00:00Z", "2030-12-31T00:00:00Z", None]:
            st, parsed = rest("PATCH", "profiles", tok, qs=f"?id=eq.{uid}", body={"phone_verified_at": val})
            stg, pg = rest("GET", "profiles", tok, qs=f"?id=eq.{uid}&select=id,phone_verified_at")
            after = first_row(pg)
            tries.append({"want": val, "st": st, "after": after.get("phone_verified_at"), "patch": snip(parsed, 180)})
        out[who] = tries
        probe(f"phone_{who}", status=tries[0]["st"], body=snip(tries, 400))
    # equivalent kyc cols
    st, parsed = rest("GET", "profiles", buyer, qs=f"?id=eq.{BUYER_ID}&select=*")
    cols = list(first_row(parsed).keys()) if st == 200 else []
    kyc = [c for c in cols if any(x in c.lower() for x in ("verif", "kyc", "iban_verified", "phone", "document"))]
    out["kyc_cols"] = kyc
    forged = False
    for t in out.get("buyer") or []:
        if t.get("want") and t.get("after") and str(t["want"])[:10] in str(t["after"]):
            forged = True
    out["forgable"] = forged
    # restore
    rest("PATCH", "profiles", None, qs=f"?id=eq.{BUYER_ID}", svc=True, body={"phone_verified_at": before.get("phone_verified_at")})
    return out


# ---------------------------------------------------------------------------
# 10 disputes
# ---------------------------------------------------------------------------
def test_disputes(buyer: str, seller: str, pid: str) -> dict[str, Any]:
    out: dict[str, Any] = {}
    st, row = insert_order(buyer, {"product_id": pid, "payment_method": "Pagamento direto ao vendedor (MB WAY/Transf)"})
    oid = row.get("id")
    if not oid:
        return {"err": "no order"}
    st, parsed = rest("POST", "order_disputes", None, svc=True, body={
        "order_id": oid,
        "buyer_id": BUYER_ID,
        "status": "resolvida",
        "seller_refund_percent": 100,
        "seller_offer_type": "full_refund",
    })
    d = track("disputes", parsed)
    out["svc_insert_resolved"] = {"st": st, "id": d.get("id"), "percent": d.get("seller_refund_percent"), "err": snip(parsed, 250) if not d.get("id") else None}
    did = d.get("id")
    if not did:
        # try minimal
        st, parsed = rest("POST", "order_disputes", buyer, body={"order_id": oid})
        d = track("disputes", parsed)
        out["buyer_insert"] = {"st": st, "id": d.get("id"), "status": d.get("status"), "body": snip(parsed, 300)}
        did = d.get("id")
        if did:
            rest("PATCH", "order_disputes", None, qs=f"?id=eq.{did}", svc=True, body={"status": "resolvida", "seller_refund_percent": 100})
    if did:
        before = rest("GET", "order_disputes", seller, qs=f"?id=eq.{did}&select=*")[1]
        brow = first_row(before)
        st2, p2 = rest("PATCH", "order_disputes", seller, qs=f"?id=eq.{did}", body={"seller_refund_percent": 10, "seller_offer_type": "partial", "status": "aberta"})
        after = first_row(p2)
        if not after.get("id"):
            after = first_row(rest("GET", "order_disputes", seller, qs=f"?id=eq.{did}&select=*")[1])
        out["seller_patch_terminal"] = {
            "st": st2,
            "before": {k: brow.get(k) for k in ("status", "seller_refund_percent", "seller_offer_type", "buyer_decision", "admin_resolution")},
            "after": {k: after.get(k) for k in ("status", "seller_refund_percent", "seller_offer_type", "buyer_decision", "admin_resolution")},
            "body": snip(p2, 300),
        }
        st3, p3 = rest("PATCH", "order_disputes", buyer, qs=f"?id=eq.{did}", body={"seller_refund_percent": 1, "buyer_decision": "accept"})
        afterb = first_row(p3) or first_row(rest("GET", "order_disputes", buyer, qs=f"?id=eq.{did}&select=*")[1])
        out["buyer_patch_terminal"] = {"st": st3, "percent": afterb.get("seller_refund_percent"), "status": afterb.get("status"), "decision": afterb.get("buyer_decision")}
        probe("dispute_terminal", status=st2, body=snip(out["seller_patch_terminal"], 400))

    # open dispute functional
    st, row2 = insert_order(buyer, {"product_id": pid, "payment_method": "Pagamento direto ao vendedor (MB WAY/Transf)"})
    oid2 = row2.get("id")
    if oid2:
        rest("PATCH", "orders", seller, qs=f"?id=eq.{oid2}", body={"status": "pago"})
        rest("PATCH", "orders", seller, qs=f"?id=eq.{oid2}", body={"status": "enviado"})
        rest("PATCH", "orders", buyer, qs=f"?id=eq.{oid2}", body={"status": "concluido"})
        st, parsed = rest("POST", "order_disputes", buyer, body={"order_id": oid2})
        d2 = track("disputes", parsed)
        out["open_insert"] = {"st": st, "id": d2.get("id"), "status": d2.get("status"), "body": snip(parsed, 250)}
        if d2.get("id"):
            st4, p4 = rest("PATCH", "order_disputes", seller, qs=f"?id=eq.{d2['id']}", body={"seller_refund_percent": 50, "seller_offer_type": "partial"})
            after4 = first_row(p4) or first_row(rest("GET", "order_disputes", seller, qs=f"?id=eq.{d2['id']}&select=*")[1])
            out["open_seller_offer"] = {"st": st4, "percent": after4.get("seller_refund_percent"), "type": after4.get("seller_offer_type"), "status": after4.get("status")}
            probe("dispute_open", status=st4, body=snip(after4, 300))
    term = out.get("seller_patch_terminal") or {}
    mutated = False
    if term.get("before") and term.get("after"):
        if term["after"].get("seller_refund_percent") == 10 and term["before"].get("seller_refund_percent") != 10:
            mutated = True
        if str(term["after"].get("status") or "") == "aberta" and str(term["before"].get("status") or "") != "aberta":
            mutated = True
    out["terminal_financially_mutable"] = mutated
    return out


# ---------------------------------------------------------------------------
# 11 reviews
# ---------------------------------------------------------------------------
def test_reviews(buyer: str, seller: str, pid: str) -> dict[str, Any]:
    out: dict[str, Any] = {}
    # PATCH existing own review if any
    st, parsed = rest("GET", "reviews", buyer, qs=f"?buyer_id=eq.{BUYER_ID}&select=id,stars,comment,is_automatic,order_id&limit=3")
    existing = parsed[0] if isinstance(parsed, list) and parsed else None
    out["existing"] = snip(parsed, 300)
    if existing and existing.get("id"):
        st2, p2 = rest("PATCH", "reviews", buyer, qs=f"?id=eq.{existing['id']}", body={"stars": 1, "comment": f"{TAG} hack", "is_automatic": True})
        after = first_row(p2)
        if not after.get("id"):
            after = first_row(rest("GET", "reviews", buyer, qs=f"?id=eq.{existing['id']}&select=id,stars,comment,is_automatic")[1])
        out["patch_existing"] = {
            "st": st2,
            "before": {k: existing.get(k) for k in ("stars", "comment", "is_automatic")},
            "after": {k: after.get(k) for k in ("stars", "comment", "is_automatic")},
        }
        probe("review_patch_existing", status=st2, body=snip(out["patch_existing"], 400))

    # insert without order
    st, parsed = rest("POST", "reviews", buyer, body={"stars": 1, "comment": TAG, "is_automatic": True, "target_id": SELLER_ID})
    out["insert_no_order"] = {"st": st, "body": snip(parsed, 250)}
    # insert random order
    st, parsed = rest("POST", "reviews", buyer, body={"stars": 1, "comment": TAG, "order_id": str(uuid.uuid4()), "is_automatic": True})
    out["insert_fake_order"] = {"st": st, "body": snip(parsed, 250)}

    # platform unpaid concluido attempt then review
    st, row = insert_order(buyer, {"product_id": pid, "payment_method": "Pagamento na App"})
    if row.get("id"):
        rest("PATCH", "orders", buyer, qs=f"?id=eq.{row['id']}", body={"status": "concluido"})
        st2, p2 = rest("POST", "reviews", buyer, body={"stars": 2, "comment": TAG, "order_id": row["id"], "is_automatic": True})
        out["review_unpaid_platform"] = {"st": st2, "body": snip(p2, 250), "order_status": get_order(buyer, row["id"], "id,status").get("status")}

    # off-platform legit review
    st, row = insert_order(buyer, {"product_id": pid, "payment_method": "Pagamento direto ao vendedor (MB WAY/Transf)"})
    if row.get("id"):
        rest("PATCH", "orders", seller, qs=f"?id=eq.{row['id']}", body={"status": "pago"})
        rest("PATCH", "orders", seller, qs=f"?id=eq.{row['id']}", body={"status": "enviado"})
        rest("PATCH", "orders", buyer, qs=f"?id=eq.{row['id']}", body={"status": "concluido"})
        ost = get_order(buyer, row["id"], "id,status,amount_paid_cents")
        st2, p2 = rest("POST", "reviews", buyer, body={"stars": 5, "comment": f"{TAG} legit", "order_id": row["id"], "is_automatic": True})
        rrow = track("reviews", p2)
        out["review_offplat"] = {"st": st2, "id": rrow.get("id"), "stars": rrow.get("stars"), "auto": rrow.get("is_automatic"), "order": ost, "err": snip(p2, 250) if not rrow.get("id") else None}
        if rrow.get("id"):
            st3, p3 = rest("PATCH", "reviews", buyer, qs=f"?id=eq.{rrow['id']}", body={"stars": 1, "is_automatic": True})
            after = first_row(p3) or first_row(rest("GET", "reviews", buyer, qs=f"?id=eq.{rrow['id']}&select=*")[1])
            out["patch_new"] = {"st": st3, "stars": after.get("stars"), "auto": after.get("is_automatic")}
        probe("review_offplat", status=st2, body=snip(out["review_offplat"], 300))

    # auto feedback rpc
    st, parsed = rpc("batata_generate_auto_feedback", buyer, {"p_now": "2099-01-01T00:00:00Z"})
    st2, p2 = rpc("batata_generate_auto_feedback", None, {})
    out["auto_feedback_rpc"] = {"buyer": {"st": st, "body": snip(parsed, 180)}, "anon": {"st": st2, "body": snip(p2, 180)}}

    abusive = False
    pe = out.get("patch_existing") or {}
    if pe.get("after") and pe.get("before"):
        if pe["after"].get("stars") != pe["before"].get("stars") and pe.get("st") in (200, 204):
            abusive = True
        if pe["after"].get("is_automatic") is True and pe["before"].get("is_automatic") is not True:
            abusive = True
    pn = out.get("patch_new") or {}
    if pn.get("stars") == 1 and out.get("review_offplat", {}).get("stars") == 5:
        abusive = True
    if (out.get("auto_feedback_rpc") or {}).get("buyer", {}).get("st") == 200:
        abusive = True
    out["abusable"] = abusive
    return out


# ---------------------------------------------------------------------------
# 12 regression
# ---------------------------------------------------------------------------
def test_regression(buyer: str, seller: str, pid: str) -> dict[str, Any]:
    out: dict[str, Any] = {}
    st, row = insert_order(buyer, {"product_id": pid, "quantity": 1})
    oid = row.get("id")
    if oid:
        stc, pc = checkout(buyer, {
            "order_id": oid,
            "buyer_id": BUYER_ID,
            "amount": 50,
            "shipping_method": "hand",
            "product_id": str(uuid.uuid4()),
            "quantity": 99,
            "line_total": 0.5,
        })
        out["underpay_body_amount"] = {"st": stc, **amounts(pc), "contract": row.get("contract_unit_cents")}
        probe("reg_underpay", status=stc, body=snip(pc, 400))
        # settle harness
        stg, pg = edge("create-payment-intent", buyer, {"order_id": oid, "payment_intent_id": "pi_x"}, qs="?fase2_e2e_settle=1")
        out["fase2_e2e_settle_jwt"] = {"st": stg, "body": snip(pg, 250)}
        # pago then cancel
        # (unpaid)
        st2, p2 = rest("PATCH", "orders", buyer, qs=f"?id=eq.{oid}", body={"status": "cancelado"})
        after = first_row(p2) or get_order(buyer, oid, "id,status")
        out["unpaid_cancel"] = {"st": st2, "status": after.get("status")}

    # alg none
    fake = "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJyb2xlIjoic2VydmljZV9yb2xlIiwic3ViIjoiMDAwMDAwMDAtMDAwMC0wMDAwLTAwMDAtMDAwMDAwMDAwMDAwIn0."
    st, parsed = rest("GET", "orders", fake, qs="?select=id&limit=1")
    out["alg_none"] = {"st": st, "body": snip(parsed, 180)}

    # webhook
    stw, pw = edge("stripe-webhook", None, {"type": "checkout.session.completed"})
    stw2, pw2 = edge("stripe-webhook", None, b"{}", extra={"stripe-signature": "t=1,v1=dead"})
    out["webhook"] = {"nosig": {"st": stw, "body": snip(pw, 180)}, "badsig": {"st": stw2, "body": snip(pw2, 180)}}

    # wallet mint
    dummy = str(uuid.uuid4())
    for name, args in [
        ("batata_credit_wallet_once", {"p_order_id": dummy, "p_amount": 500, "p_type": "venda", "p_description": "x"}),
        ("batata_release_seller_wallet_for_order", {"p_order_id": dummy}),
        ("batata_create_raffle_prize_order", {"p_raffle_id": dummy}),
        ("batata_draw_live_raffle_winners", {"p_raffle_id": dummy}),
    ]:
        st, parsed = rpc(name, buyer, args)
        out[f"rpc_{name}"] = {"st": st, "body": snip(parsed, 180)}

    # stream keys
    st, parsed = rest("GET", "lives", None, qs="?select=id,mux_stream_key,stream_key,status&limit=5")
    keys = []
    if isinstance(parsed, list):
        keys = [r.get("mux_stream_key") or r.get("stream_key") for r in parsed if r.get("mux_stream_key") or r.get("stream_key")]
    out["anon_stream_keys"] = {"st": st, "keys": keys[:3], "n": len(keys)}
    st, parsed = rest("GET", "lives", buyer, qs=f"?seller_id=eq.{SELLER_ID}&select=id,mux_stream_key,stream_key&limit=5")
    bkeys = []
    if isinstance(parsed, list):
        bkeys = [r.get("mux_stream_key") or r.get("stream_key") for r in parsed if r.get("mux_stream_key") or r.get("stream_key")]
    out["buyer_stream_keys"] = {"st": st, "n": len(bkeys)}

    # mux
    st, parsed = edge("create-mux-live", buyer, {"title": f"{TAG} buyer mux"})
    out["mux_buyer"] = {"st": st, "body": snip(parsed, 250)}
    # don't leave seller live running — skip create-mux-live seller if not needed
    st, parsed = edge("complete-mux-live", buyer, {"live_id": str(uuid.uuid4())})
    out["mux_complete_foreign"] = {"st": st, "body": snip(parsed, 180)}

    # OCR / pairing
    st, parsed = edge("ingest-ocr-reservation", None, {"live_id": str(uuid.uuid4()), "ocr_line_hash": "abcdefgh", "detected_at": "2026-08-27T00:00:00Z", "ref_number": 1})
    out["ocr_anon"] = {"st": st, "body": snip(parsed, 220)}
    st, parsed = edge("ps-pairing-claim", None, {"code": "000000", "device_id": "retsat"})
    out["ps_anon"] = {"st": st, "body": snip(parsed, 180)}

    # refund buyer
    if oid:
        st, parsed = edge("refund-order", buyer, {"order_id": oid})
        out["refund_buyer"] = {"st": st, "body": snip(parsed, 200)}
        st, parsed = edge("refund-order", seller, {"order_id": oid})
        out["refund_seller_unpaid"] = {"st": st, "body": snip(parsed, 200)}

    # oversell insert qty > stock
    pid2 = make_product(seller, 10.00, 1, f"{TAG} stock1")
    if pid2:
        st1, a = insert_order(buyer, {"product_id": pid2, "quantity": 1})
        st2, b = insert_order(buyer, {"product_id": pid2, "quantity": 1})
        st3, c = insert_order(buyer, {"product_id": pid2, "quantity": 2})
        out["oversell_unpaid"] = {
            "a": {"st": st1, "id": a.get("id")},
            "b": {"st": st2, "id": b.get("id"), "err": err_text(b.get("_error"))},
            "qty2": {"st": st3, "id": c.get("id"), "err": err_text(c.get("_error"))},
        }

    # product seller mismatch: buyer order with another product? create product then patch seller? 
    # order product of seller with spoofed seller_id = buyer
    st, row = insert_order(buyer, {"product_id": pid, "seller_id": BUYER_ID})
    out["seller_mismatch_insert"] = {"st": st, "seller": row.get("seller_id"), "err": err_text(row.get("_error")), "oid": row.get("id")}

    # chat parties
    st, parsed = rest("POST", "chats", buyer, body={"buyer_id": BUYER_ID, "seller_id": SELLER_ID})
    chat = track("chats", parsed)
    out["chat_insert"] = {"st": st, "id": chat.get("id")}
    if chat.get("id"):
        st2, p2 = rest("PATCH", "chats", buyer, qs=f"?id=eq.{chat['id']}", body={"seller_id": BUYER_ID})
        after = first_row(p2) or first_row(rest("GET", "chats", buyer, qs=f"?id=eq.{chat['id']}&select=*")[1])
        out["chat_party_swap"] = {"st": st2, "seller_id": after.get("seller_id")}
        # messages
        st3, p3 = rest("POST", "chat_messages", buyer, body={"chat_id": chat["id"], "sender_id": SELLER_ID, "content": TAG})
        out["chat_spoof_sender"] = {"st": st3, "body": snip(p3, 200)}

    # tip
    st, parsed = edge("create-live-tip-checkout", buyer, {"live_id": str(uuid.uuid4()), "amount": 500, "seller_id": BUYER_ID})
    out["tip_payb"] = {"st": st, "body": snip(parsed, 220)}

    # payout duplicate
    k = "retsat-idemp-" + uuid.uuid4().hex[:10]
    st1, p1 = edge("create-connect-account", seller, {"amount": 1, "idempotency_key": k, "action": "payout"})
    st2, p2 = edge("create-connect-account", seller, {"amount": 1, "idempotency_key": k, "action": "payout"})
    out["payout_dup"] = {"a": {"st": st1, "body": snip(p1, 220)}, "b": {"st": st2, "body": snip(p2, 220)}}

    # open redirect
    if oid:
        stc, pc = checkout(buyer, {"order_id": oid, "buyer_id": BUYER_ID, "shipping_method": "hand", "success_url": "https://evil.example/x", "cancel_url": "https://evil.example/y"})
        url = amounts(pc).get("url") or ""
        out["open_redirect"] = {"st": stc, "url_snip": str(url)[:180], "body": snip(pc, 250)}

    # prize spoof
    st, row = insert_order(buyer, {"product_id": pid, "live_raffle_id": str(uuid.uuid4()), "status": "premio_rifa", "price_total": 0})
    out["prize_insert"] = {"st": st, "status": row.get("status"), "contract": row.get("contract_unit_cents"), "raffle": row.get("live_raffle_id"), "oid": row.get("id")}
    if row.get("id"):
        stc, pc = checkout(buyer, {"order_id": row["id"], "buyer_id": BUYER_ID, "prize_shipping": True, "shipping_method": "carrier"})
        out["prize_checkout"] = amounts(pc)

    return out


# ---------------------------------------------------------------------------
# 13 stripe e2e (session + optional pay)
# ---------------------------------------------------------------------------
def test_e2e(buyer: str, seller: str) -> dict[str, Any]:
    pid = make_product(seller, CATALOG_EUR, 2, f"{TAG} e2e 40")
    out: dict[str, Any] = {"pid": pid}
    if not pid:
        return out
    st, row = insert_order(buyer, {"product_id": pid, "quantity": 1, "contract_unit_cents": 50, "price_total": 0.5})
    out["legit_order"] = {
        "st": st,
        "oid": row.get("id"),
        "contract": row.get("contract_unit_cents"),
        "qty": row.get("contract_qty"),
        "quantity": row.get("quantity"),
        "status": row.get("status"),
    }
    if row.get("id"):
        stock_before = first_row(rest("GET", "products", seller, qs=f"?id=eq.{pid}&select=id,quantity")[1])
        out["stock_before"] = stock_before.get("quantity")
        stc, pc = checkout(buyer, {"order_id": row["id"], "buyer_id": BUYER_ID, "shipping_method": "hand"})
        out["checkout"] = amounts(pc)
        probe("e2e_checkout", status=stc, body=snip(pc, 500))
        # hostile twin
        pidh = make_product(seller, CATALOG_EUR, 2, f"{TAG} e2e hostile")
        sth, rh = insert_order(buyer, {"product_id": pidh, "quantity": 1, "contract_unit_cents": 50})
        stch, pch = checkout(buyer, {"order_id": rh.get("id"), "buyer_id": BUYER_ID, "shipping_method": "hand", "amount": 50}) if rh.get("id") else (0, {})
        out["hostile"] = {"oid": rh.get("id"), "contract": rh.get("contract_unit_cents"), "checkout": amounts(pch) if stch else {}}
    return out


# ---------------------------------------------------------------------------
# 14 discovery
# ---------------------------------------------------------------------------
def test_discovery(buyer: str, seller: str, pid: str, order_cols: list[str], rpc_names: list[str]) -> dict[str, Any]:
    out: dict[str, Any] = {"new_findings": []}
    # user_type
    st, parsed = rest("PATCH", "profiles", buyer, qs=f"?id=eq.{BUYER_ID}", body={"user_type": "vendedor"})
    after = first_row(rest("GET", "profiles", buyer, qs=f"?id=eq.{BUYER_ID}&select=id,user_type")[1])
    out["user_type"] = {"st": st, "after": after.get("user_type")}
    rest("PATCH", "profiles", None, qs=f"?id=eq.{BUYER_ID}", svc=True, body={"user_type": "comprador"})

    # stripe events
    st, parsed = rest("GET", "stripe_checkout_events", buyer, qs="?select=id,order_id,buyer_id&limit=5")
    foreign = []
    if isinstance(parsed, list):
        foreign = [r for r in parsed if r.get("buyer_id") and r.get("buyer_id") != BUYER_ID]
    out["stripe_events"] = {"st": st, "n": len(parsed) if isinstance(parsed, list) else 0, "foreign": len(foreign)}

    # bundle discounts
    st, parsed = rest("GET", "seller_bundle_discounts", buyer, qs="?select=seller_id,enabled,tier_2_pct,tier_5_pct")
    others = []
    if isinstance(parsed, list):
        others = [r for r in parsed if r.get("seller_id") != SELLER_ID]
    out["bundle_discounts"] = {"st": st, "n": len(parsed) if isinstance(parsed, list) else 0, "others": len(others)}

    # storage list
    st, parsed = http(
        "POST",
        f"{BASE}/storage/v1/object/list/chat_media",
        token=ANON,
        apikey=ANON,
        body={"prefix": "chat_uploads/", "limit": 5},
    )
    out["storage_list_anon"] = {"st": st, "n": len(parsed) if isinstance(parsed, list) else 0, "body": snip(parsed, 200)}

    # UPDATE product_offer_id after insert
    st, row = insert_order(buyer, {"product_id": pid, "quantity": 1})
    if row.get("id"):
        st2, p2 = rest("PATCH", "orders", buyer, qs=f"?id=eq.{row['id']}", body={"product_offer_id": str(uuid.uuid4()), "live_raffle_id": str(uuid.uuid4())})
        after = first_row(p2) or get_order(buyer, row["id"], "id,product_offer_id,live_raffle_id,contract_unit_cents")
        out["update_offer_raffle"] = {"st": st2, "offer": after.get("product_offer_id"), "raffle": after.get("live_raffle_id"), "contract": after.get("contract_unit_cents")}

    # collusion: seller inflate via... already tested. Try INSERT as seller for buyer.
    st, row = insert_order(seller, {"product_id": pid, "buyer_id": BUYER_ID, "seller_id": SELLER_ID, "contract_unit_cents": 20000, "price_total": 200})
    out["seller_insert_for_buyer"] = {"st": st, "contract": row.get("contract_unit_cents"), "oid": row.get("id"), "buyer": row.get("buyer_id")}
    if row.get("id") and row.get("contract_unit_cents"):
        stc, pc = checkout(buyer, {"order_id": row["id"], "buyer_id": BUYER_ID, "shipping_method": "hand"})
        out["seller_insert_for_buyer"]["checkout"] = amounts(pc)

    # concurrent checkout twice
    st, row = insert_order(buyer, {"product_id": pid, "quantity": 1})
    if row.get("id"):
        st1, p1 = checkout(buyer, {"order_id": row["id"], "buyer_id": BUYER_ID, "shipping_method": "hand"})
        st2, p2 = checkout(buyer, {"order_id": row["id"], "buyer_id": BUYER_ID, "shipping_method": "hand"})
        out["double_session"] = {"a": amounts(p1), "b": amounts(p2), "st": [st1, st2]}

    # dangerous rpcs not in lab list
    danger = [n for n in rpc_names if any(x in n.lower() for x in ("wallet", "payout", "refund", "credit", "debit", "settle", "mint", "admin"))]
    hits = []
    for name in danger[:40]:
        st, parsed = rpc(name, buyer, {})
        if st == 200:
            hits.append({"name": name, "st": st, "body": snip(parsed, 120)})
    out["danger_rpc_200"] = hits

    # whitespace payment_method that looks off-platform
    for pm in ["mb way\t", "MBWAY", "pagamento direto ao vendedor", "pix mb way"]:
        st, row = insert_order(buyer, {"product_id": pid, "payment_method": pm})
        if row.get("id"):
            st2, p2 = rest("PATCH", "orders", seller, qs=f"?id=eq.{row['id']}", body={"status": "pago"})
            after = first_row(p2) or get_order(seller, row["id"], "id,status,payment_method")
            rec = {"pm": pm, "stored": row.get("payment_method"), "pago": after.get("status")}
            out.setdefault("pm_edge", []).append(rec)
            if str(after.get("status") or "").lower() == "pago" and "pix" in pm:
                out["new_findings"].append({"id": "NEW-PM-PIX-MBWAY", "detail": rec})

    return out


def cleanup(seller: str) -> None:
    for pid in CREATED.get("products") or []:
        rest("PATCH", "products", seller, qs=f"?id=eq.{pid}", body={"quantity": 0, "list_on_marketplace": False, "title": f"{TAG} DONE"})
    for lid in CREATED.get("lives") or []:
        rest("PATCH", "lives", seller, qs=f"?id=eq.{lid}", body={"status": "ended", "is_active": False})
    for oid in CREATED.get("orders") or []:
        rest("PATCH", "orders", None, qs=f"?id=eq.{oid}", svc=True, body={"status": "cancelado"})
    for rid in CREATED.get("reservations") or []:
        rest("PATCH", "live_reservation_requests", None, qs=f"?id=eq.{rid}", svc=True, body={"status": "rejected"})
    rest("PATCH", "profiles", None, qs=f"?id=eq.{BUYER_ID}", svc=True, body={"user_type": "comprador"})


def main() -> None:
    load_env()
    buyer = login(BUYER_EMAIL, BUYER_PASS)
    seller = login(SELLER_EMAIL, SELLER_PASS)
    evidence: dict[str, Any] = {
        "tag": TAG,
        "staging": STAGING_REF,
        "started": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "production_touched": False,
        "fixes_applied": False,
        "sql_applied": False,
        "fase4": False,
    }
    rpc_names = openapi_rpcs()
    evidence["rpc_names_sample"] = [n for n in rpc_names if any(x in n.lower() for x in ("lab", "staging", "nuke", "feedback", "wallet", "order"))]
    evidence["rpc_count"] = len(rpc_names)

    st, parsed = rest("GET", "orders", None, qs="?select=*&limit=1", svc=True)
    order_cols = list(first_row(parsed).keys()) if st == 200 else []
    evidence["order_cols"] = order_cols
    probe("order_cols", status=st, note=str(len(order_cols)))

    pid = make_product(seller, CATALOG_EUR, 8, f"{TAG} unit 40 qty8")
    if not pid:
        raise SystemExit("cannot create product")
    evidence["product_id"] = pid

    print("=== P0 contract ===", flush=True)
    evidence["p0_contract"] = test_p0_contract(buyer, seller, pid)
    print("=== P0 proposta ===", flush=True)
    evidence["p0_proposta"] = test_p0_proposta(buyer, seller, pid)
    print("=== P0 qty ===", flush=True)
    evidence["p0_qty"] = test_p0_qty(buyer, seller, pid)
    print("=== flags ===", flush=True)
    evidence["flags"] = test_flags(buyer, seller, pid, order_cols)
    print("=== lab rpcs ===", flush=True)
    evidence["lab"] = test_lab_rpcs(buyer, seller, rpc_names)
    print("=== payment machine ===", flush=True)
    evidence["payment"] = test_payment_machine(buyer, seller, pid)
    print("=== live ===", flush=True)
    evidence["live"] = test_live(buyer, seller, pid)
    print("=== phone ===", flush=True)
    evidence["phone"] = test_phone(buyer, seller)
    print("=== disputes ===", flush=True)
    evidence["disputes"] = test_disputes(buyer, seller, pid)
    print("=== reviews ===", flush=True)
    evidence["reviews"] = test_reviews(buyer, seller, pid)
    print("=== regression ===", flush=True)
    evidence["regression"] = test_regression(buyer, seller, pid)
    print("=== e2e ===", flush=True)
    evidence["e2e"] = test_e2e(buyer, seller)
    print("=== discovery ===", flush=True)
    evidence["discovery"] = test_discovery(buyer, seller, pid, order_cols, rpc_names)

    print("=== cleanup ===", flush=True)
    cleanup(seller)
    evidence["created"] = CREATED
    evidence["probes"] = PROBES
    evidence["ended"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    outp = ROOT / "tool" / "reports" / "RETESTE_POS_SATURACAO_2026-08-27_EVIDENCE.json"
    outp.parent.mkdir(parents=True, exist_ok=True)
    outp.write_text(json.dumps(evidence, indent=2, default=str), encoding="utf-8")
    print(f"WROTE {outp}", flush=True)


if __name__ == "__main__":
    main()
