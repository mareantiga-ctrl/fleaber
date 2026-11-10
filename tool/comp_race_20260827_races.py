#!/usr/bin/env python3
# COMP_RACE_20260827 — harness exclusivo (não colidir com outros auditores).
# Staging only. Stripe TEST via edge. Sem correcções. Sem produção.
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
from urllib.parse import urlencode
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = ROOT / "tool" / "live_ops_staging.env"
REPORTS = ROOT / "tool" / "reports"
TAG = f"COMP_RACE_20260827_{int(time.time())}_{uuid.uuid4().hex[:6]}"
STAGING_REF = "fxdknzrqjenzqcvnwqqq"

findings: list[dict[str, Any]] = []
races: list[dict[str, Any]] = []
evidence: dict[str, Any] = {
    "tag": TAG,
    "started_at": datetime.now(timezone.utc).isoformat(),
    "staging": STAGING_REF,
    "production_touched": False,
    "corrections_applied": False,
    "passes": {},
    "cleanup": [],
}
cleanup_products: list[str] = []
cleanup_orders: list[str] = []
cleanup_lives: list[str] = []


def load_env() -> dict[str, str]:
    out: dict[str, str] = {}
    for line in ENV_PATH.read_text(encoding="utf-8").splitlines():
        t = line.strip()
        if not t or t.startswith("#") or "=" not in t:
            continue
        k, v = t.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def req(
    method: str,
    url: str,
    token: str,
    *,
    body: Any = None,
    extra: dict[str, str] | None = None,
    timeout: int = 60,
) -> dict[str, Any]:
    headers = {
        "apikey": ANON if token != SVC else SVC,
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }
    if extra:
        headers.update(extra)
    data = None if body is None else json.dumps(body).encode("utf-8")
    r = Request(url, data=data, headers=headers, method=method)
    try:
        with urlopen(r, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", "replace")
            parsed: Any = None
            if raw:
                try:
                    parsed = json.loads(raw)
                except json.JSONDecodeError:
                    parsed = raw
            return {"http": resp.status, "body": parsed, "raw": raw[:4000]}
    except HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        parsed: Any = raw
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            pass
        return {"http": e.code, "body": parsed, "raw": raw[:4000]}
    except URLError as e:
        return {"http": 0, "body": {"error": str(e.reason)}, "raw": str(e)}


def rest(method: str, path: str, token: str, body: Any = None, qs: str = "") -> dict[str, Any]:
    url = f"{URL}/rest/v1/{path}"
    if qs:
        url += ("&" if "?" in path else "?") + qs if "?" in path else f"?{qs}"
    return req(method, url, token, body=body)


def rpc(name: str, token: str, body: dict[str, Any]) -> dict[str, Any]:
    return req("POST", f"{URL}/rest/v1/rpc/{name}", token, body=body)


def fn(name: str, token: str, body: dict[str, Any], extra: dict[str, str] | None = None) -> dict[str, Any]:
    return req("POST", f"{URL}/functions/v1/{name}", token, body=body, extra=extra, timeout=90)


def login(email: str, password: str) -> str:
    r = req(
        "POST",
        f"{URL}/auth/v1/token?grant_type=password",
        ANON,
        body={"email": email, "password": password},
        extra={"apikey": ANON, "Authorization": f"Bearer {ANON}"},
    )
    tok = ""
    if isinstance(r["body"], dict):
        tok = str(r["body"].get("access_token") or "")
    if not tok:
        raise SystemExit(f"login failed {email}: {r}")
    return tok


def row(res: dict[str, Any]) -> dict[str, Any] | None:
    b = res.get("body")
    if isinstance(b, list) and b:
        return dict(b[0]) if isinstance(b[0], dict) else None
    if isinstance(b, dict) and "id" in b:
        return b
    return None


def rows(res: dict[str, Any]) -> list[dict[str, Any]]:
    b = res.get("body")
    if isinstance(b, list):
        return [dict(x) for x in b if isinstance(x, dict)]
    return []


def n(v: Any) -> float:
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


def rec_find(
    fid: str,
    sev: str,
    title: str,
    *,
    invariant: str,
    comportamento: str,
    regra: str,
    intencional: str,
    autoridade: str,
    invariante_quebrada: str,
    impacto: str,
    evidence_obj: Any,
    broken: bool,
) -> None:
    findings.append(
        {
            "id": fid,
            "sev": sev if broken else "INFO",
            "title": title,
            "invariant": invariant,
            "broken": broken,
            "COMPORTAMENTO": comportamento,
            "REGRA_FUNCIONAL_RECONSTRUIDA": regra,
            "INTENCIONAL": intencional,
            "AUTORIDADE_CORRECTA": autoridade,
            "INVARIANTE_QUEBRADA": invariante_quebrada if broken else "",
            "IMPACTO_REAL": impacto if broken else "sem quebra demonstrada",
            "evidence": evidence_obj,
        }
    )


def rec_race(name: str, payload: dict[str, Any]) -> None:
    races.append({"name": name, "at": datetime.now(timezone.utc).isoformat(), **payload})


def product(seller: str, qty: int, price: float, suffix: str) -> dict[str, Any]:
    p = row(
        rest(
            "POST",
            "products",
            SVC,
            {
                "seller_id": seller,
                "title": f"{TAG} {suffix}",
                "price": price,
                "quantity": qty,
                "ref_code": f"CR-{suffix[:8]}-{uuid.uuid4().hex[:8]}",
                "list_on_marketplace": True,
                "available_for_live": False,
                "is_sold": False,
                "image_urls": [],
            },
        )
    )
    if not p or not p.get("id"):
        raise RuntimeError(f"product insert failed {suffix}")
    cleanup_products.append(str(p["id"]))
    return p


def order(
    buyer: str,
    seller: str,
    product_id: str,
    *,
    qty: int = 1,
    price: float = 5.0,
    status: str = "reserva_pendente",
    pm: str = "Pagamento na app (Seguro Fleaber)",
    ship: str = "entrega em mão",
    token: str | None = None,
) -> dict[str, Any]:
    tok = token or BUYER
    o = row(
        rest(
            "POST",
            "orders",
            tok,
            {
                "buyer_id": buyer,
                "seller_id": seller,
                "product_id": product_id,
                "quantity": qty,
                "price_total": price * qty,
                "status": status,
                "payment_method": pm,
                "shipping_method": ship,
            },
        )
    )
    if not o or not o.get("id"):
        # JWT may strip fields; retry as buyer with minimal
        o = row(
            rest(
                "POST",
                "orders",
                tok,
                {
                    "buyer_id": buyer,
                    "seller_id": seller,
                    "product_id": product_id,
                    "quantity": qty,
                    "price_total": price * qty,
                    "status": "reserva_pendente",
                    "payment_method": pm,
                },
            )
        )
    if not o or not o.get("id"):
        raise RuntimeError("order insert failed")
    cleanup_orders.append(str(o["id"]))
    return o


def get_order(oid: str) -> dict[str, Any] | None:
    return row(
        rest(
            "GET",
            "orders",
            SVC,
            qs=f"id=eq.{oid}&select=id,status,amount_paid_cents,stock_units_applied,quantity,contract_qty,price_total,payment_method,stripe_payment_intent_id,stripe_checkout_session_id,stripe_refund_id,wallet_release_processed_at,wallet_refund_processed_at,product_id,buyer_id,seller_id",
        )
    )


def get_product(pid: str) -> dict[str, Any] | None:
    return row(rest("GET", "products", SVC, qs=f"id=eq.{pid}&select=id,quantity,is_sold,seller_id,price"))


def get_wallet(uid: str) -> float:
    r = row(rest("GET", "wallets", SVC, qs=f"id=eq.{uid}&select=id,balance"))
    return n(r.get("balance") if r else 0)


def wallet_txs(oid: str) -> list[dict[str, Any]]:
    return rows(
        rest(
            "GET",
            "wallet_transactions",
            SVC,
            qs=f"order_id=eq.{oid}&select=id,wallet_id,amount,type,description,order_id,created_at",
        )
    )


def net_order(oid: str) -> float:
    s = 0.0
    for t in wallet_txs(oid):
        typ = str(t.get("type") or "").lower()
        amt = n(t.get("amount"))
        if typ in ("venda", "reembolso"):
            s += amt
        elif typ == "estorno":
            s -= amt
    return round(s, 2)


def e2e(body: dict[str, Any]) -> dict[str, Any]:
    extra = {}
    if E2E:
        extra["x-fleaber-e2e-secret"] = E2E
        extra["x-fleaber-crash-inject-secret"] = E2E
    return fn("sec-fase2-e2e-oversell", SVC, body, extra=extra)


def checkout(body: dict[str, Any], token: str) -> dict[str, Any]:
    return fn("create-payment-intent", token, body)


def settle_get(session_id: str) -> dict[str, Any]:
    q = urlencode({"checkout_return": "success", "session_id": session_id})
    return req("GET", f"{URL}/functions/v1/create-payment-intent?{q}", ANON, timeout=90)


# ---------------------------------------------------------------------------
# PASS 1 — PAYMENT × STOCK
# ---------------------------------------------------------------------------
def pass1() -> None:
    ev: dict[str, Any] = {}
    # 1a seller MB WAY concurrent pago stock=1
    p = product(SELLER_ID, 1, 5.0, "P1-MB-Q1")
    o1 = order(BUYER_ID, SELLER_ID, p["id"], pm="MB WAY", price=5.0)
    o2 = order(BUYER_ID, SELLER_ID, p["id"], pm="MB WAY", price=5.0)
    ev["mb_orders"] = [o1["id"], o2["id"]]

    def patch_pago(oid: str) -> dict[str, Any]:
        return rest("PATCH", "orders", SELLER, {"status": "pago"}, qs=f"id=eq.{oid}")

    with ThreadPoolExecutor(max_workers=2) as ex:
        futs = [ex.submit(patch_pago, o1["id"]), ex.submit(patch_pago, o2["id"])]
        ev["mb_parallel_http"] = [f.result()["http"] for f in futs]
    a, b = get_order(o1["id"]), get_order(o2["id"])
    prod = get_product(p["id"])
    pago = [
        x
        for x in (a, b)
        if x and str(x.get("status")).lower() == "pago" and n(x.get("stock_units_applied")) >= 1
    ]
    ev["mb_after"] = {"a": a, "b": b, "product": prod, "valid_sales": len(pago)}
    rec_race("p1_mbway_parallel_stock1", ev["mb_after"])
    rec_find(
        "CR-P1-01",
        "P0",
        "Duas vendas MB WAY válidas a partir de stock=1",
        invariant="I1",
        comportamento="Seller marca pago em duas orders do mesmo SKU qty=1 em paralelo.",
        regra="Off-platform: seller atesta pagamento; trigger consome stock atomicamente.",
        intencional="Seller→pago MB WAY é produto. Duas vendas físicas no mesmo SKU não.",
        autoridade="Trigger stock FOR UPDATE + quantity >= units.",
        invariante_quebrada="I1",
        impacto="Duas unidades económicas a partir de uma física.",
        evidence_obj=ev["mb_after"],
        broken=len(pago) >= 2 or (prod is not None and n(prod.get("quantity")) < 0),
    )

    # 1b sequential reverse order
    p2 = product(SELLER_ID, 1, 5.0, "P1-MB-SEQ")
    s1 = order(BUYER_ID, SELLER_ID, p2["id"], pm="MB WAY")
    s2 = order(BUYER_ID, SELLER_ID, p2["id"], pm="MB WAY")
    rest("PATCH", "orders", SELLER, {"status": "pago"}, qs=f"id=eq.{s2['id']}")
    rest("PATCH", "orders", SELLER, {"status": "pago"}, qs=f"id=eq.{s1['id']}")
    seq = {
        "first": get_order(s2["id"]),
        "second": get_order(s1["id"]),
        "product": get_product(p2["id"]),
    }
    seq_valid = [
        x
        for x in (seq["first"], seq["second"])
        if x and str(x.get("status")).lower() == "pago" and n(x.get("stock_units_applied")) >= 1
    ]
    ev["mb_seq"] = {**seq, "valid": len(seq_valid)}
    rec_find(
        "CR-P1-02",
        "P0",
        "MB WAY sequencial B→A stock=1",
        invariant="I1",
        comportamento="Seller pago na segunda order primeiro, depois na primeira.",
        regra="Primeiro pago consome a unidade; o outro falha o trigger.",
        intencional="Não.",
        autoridade="Trigger stock.",
        invariante_quebrada="I1",
        impacto="Segunda venda válida.",
        evidence_obj=ev["mb_seq"],
        broken=len(seq_valid) >= 2,
    )

    # 1c two checkout sessions while stock=1 (TOCTOU quote)
    p3 = product(SELLER_ID, 1, 8.0, "P1-CK-TOCTOU")
    c1 = order(BUYER_ID, SELLER_ID, p3["id"], price=8.0)
    c2 = order(BUYER_ID, SELLER_ID, p3["id"], price=8.0)
    body1 = {
        "buyer_id": BUYER_ID,
        "order_id": c1["id"],
        "product_id": p3["id"],
        "seller_id": SELLER_ID,
        "shipping_method": "hand",
        "quantity": 1,
    }
    body2 = {**body1, "order_id": c2["id"]}
    with ThreadPoolExecutor(max_workers=2) as ex:
        r1 = ex.submit(checkout, body1, BUYER)
        r2 = ex.submit(checkout, body2, BUYER)
        ck = [r1.result(), r2.result()]
    sessions = []
    for r in ck:
        b = r.get("body") if isinstance(r.get("body"), dict) else {}
        sid = str((b or {}).get("sessionId") or (b or {}).get("id") or "")
        url = str((b or {}).get("url") or "")
        sessions.append({"http": r["http"], "session": sid, "url_prefix": url[:80], "err": (b or {}).get("error")})
    ev["two_sessions"] = sessions
    rec_race("p1_two_checkout_sessions_stock1", {"sessions": sessions, "product": get_product(p3["id"])})
    both_open = sum(1 for s in sessions if s["http"] in (200, 201) and s["session"]) >= 2
    rec_find(
        "CR-P1-03",
        "P2",
        "Duas Checkout Sessions abertas para stock=1",
        invariant="I1/I8",
        comportamento="Dois POSTs create-payment-intent em paralelo com stock=1.",
        regra="Quote lê stock sem reservar; settle é a autoridade.",
        intencional="Retry de Session unpaid é esperado; duas Sessions simultâneas no mesmo SKU são TOCTOU até ao settle.",
        autoridade="Settle + trigger stock + oversell refund.",
        invariante_quebrada="",
        impacto="Não é venda dupla por si; só se ambas capturarem e ambas ficarem pago.",
        evidence_obj=sessions,
        broken=False,
    )
    ev["two_sessions_both_created"] = both_open

    # 1d same order two sessions sequential
    p4 = product(SELLER_ID, 2, 8.0, "P1-DUP-SESS")
    d1 = order(BUYER_ID, SELLER_ID, p4["id"], price=8.0)
    ck_a = checkout({**body1, "order_id": d1["id"], "product_id": p4["id"]}, BUYER)
    ck_b = checkout({**body1, "order_id": d1["id"], "product_id": p4["id"]}, BUYER)
    ev["same_order_two_sessions"] = {
        "a_http": ck_a["http"],
        "b_http": ck_b["http"],
        "a": ck_a.get("body") if isinstance(ck_a.get("body"), dict) else ck_a.get("raw", "")[:300],
        "b": ck_b.get("body") if isinstance(ck_b.get("body"), dict) else ck_b.get("raw", "")[:300],
    }

    # 1e Stripe TEST two captures via e2e harness (real PIs, sequential settle)
    ov = e2e({"buyer_id": BUYER_ID, "seller_id": SELLER_ID})
    ev["e2e_oversell"] = {
        "http": ov["http"],
        "ok": (ov.get("body") or {}).get("ok") if isinstance(ov.get("body"), dict) else None,
        "body_keys": list((ov.get("body") or {}).keys()) if isinstance(ov.get("body"), dict) else ov.get("raw", "")[:400],
    }
    body = ov.get("body") if isinstance(ov.get("body"), dict) else {}
    if body.get("product_id"):
        cleanup_products.append(str(body["product_id"]))
    oa, ob = body.get("order_a_after") or body.get("order_a"), body.get("order_b_after") or body.get("order_b")
    winner_pago = False
    loser_refunded = False
    two_pago = False
    if isinstance(body, dict):
        oa = body.get("order_a_after") or {}
        ob = body.get("order_b_after") or {}
        if not oa:
            oa = {}
        if not ob:
            ob = {}
        st_a = str(oa.get("status") or "").lower()
        st_b = str(ob.get("status") or "").lower()
        winner_pago = st_a == "pago" or st_b == "pago"
        loser_refunded = bool(oa.get("stripe_refund_id") or ob.get("stripe_refund_id") or body.get("loser_refund"))
        two_pago = st_a == "pago" and st_b == "pago"
        # list refunds if we have PIs
        loser_pi = None
        if isinstance(body.get("loser_pi"), dict):
            loser_pi = body["loser_pi"].get("id")
        if loser_pi:
            listed = e2e({"probe": "list_stripe_refunds", "payment_intent_id": loser_pi})
            ev["loser_refunds"] = listed.get("body")
            if isinstance(listed.get("body"), dict):
                loser_refunded = listed["body"].get("refund_count", 0) >= 1 or loser_refunded
    rec_find(
        "CR-P1-04",
        "P0",
        "Duas capturas Stripe stock=1 — ambas vendas válidas",
        invariant="I1/I3",
        comportamento="Dois PaymentIntents succeeded no mesmo SKU qty=1; settle A depois B.",
        regra="Primeiro settle consome stock; segundo refund oversell.",
        intencional="Refund do segundo é a defesa, não a segunda venda.",
        autoridade="settleOrderPaidOrRefundOversell + Stripe refund.",
        invariante_quebrada="I1 e/ou I3",
        impacto="Duas vendas pagas permanentes.",
        evidence_obj=ev["e2e_oversell"] | {"loser_refunds": ev.get("loser_refunds")},
        broken=two_pago,
    )
    ev["stripe_two_valid"] = two_pago
    ev["stripe_second_refunded"] = loser_refunded
    ev["stripe_one_paid"] = winner_pago

    # 1f concurrent e2e settle: two setup_paid_order cannot share SKU.
    # Instead: create stock=1 product, two orders JWT, two setup? no.
    # Drain stock between session and settle: create session, seller qty=0, GET settle unpaid.
    p5 = product(SELLER_ID, 1, 8.0, "P1-DRAIN")
    od = order(BUYER_ID, SELLER_ID, p5["id"], price=8.0)
    ck = checkout(
        {
            "buyer_id": BUYER_ID,
            "order_id": od["id"],
            "product_id": p5["id"],
            "seller_id": SELLER_ID,
            "shipping_method": "hand",
        },
        BUYER,
    )
    rest("PATCH", "products", SELLER, {"quantity": 0}, qs=f"id=eq.{p5['id']}")
    ev["drain_after_session"] = {
        "checkout_http": ck["http"],
        "product": get_product(p5["id"]),
        "order": get_order(od["id"]),
        "checkout_body_err": (ck.get("body") or {}).get("error") if isinstance(ck.get("body"), dict) else ck.get("raw", "")[:200],
    }

    # 1g retries of unpaid settle GET
    if isinstance(ck.get("body"), dict) and ck["body"].get("sessionId"):
        sid = str(ck["body"]["sessionId"])
        g1 = settle_get(sid)
        g2 = settle_get(sid)
        ev["settle_retry_unpaid"] = {
            "g1": g1["http"],
            "g2": g2["http"],
            "order": get_order(od["id"]),
        }

    evidence["passes"]["pass1"] = ev


# ---------------------------------------------------------------------------
# PASS 2 — BAG × STOCK × REFUND
# ---------------------------------------------------------------------------
def pass2() -> None:
    ev: dict[str, Any] = {}
    # mixed sellers
    p_s = product(SELLER_ID, 2, 6.0, "P2-MIX-S")
    # buyer-owned second product? need another seller. Skip if only one seller.
    # Use same seller vs spoofed line.seller_id of buyer
    o_a = order(BUYER_ID, SELLER_ID, p_s["id"], price=6.0)
    o_b = order(BUYER_ID, SELLER_ID, p_s["id"], price=6.0)
    mix = checkout(
        {
            "buyer_id": BUYER_ID,
            "order_id": o_a["id"],
            "bag_checkout": True,
            "shipping_method": "hand",
            "bag_lines": [
                {"order_id": o_a["id"], "product_id": p_s["id"], "seller_id": SELLER_ID},
                {"order_id": o_b["id"], "product_id": p_s["id"], "seller_id": BUYER_ID},
            ],
        },
        BUYER,
    )
    ev["mixed_seller_claim"] = {"http": mix["http"], "err": (mix.get("body") or {}).get("error") if isinstance(mix.get("body"), dict) else mix.get("raw", "")[:300]}

    # same SKU qty 2 stock 1 in bag
    p1 = product(SELLER_ID, 1, 6.0, "P2-SAME-SKU")
    b1 = order(BUYER_ID, SELLER_ID, p1["id"], price=6.0)
    b2 = order(BUYER_ID, SELLER_ID, p1["id"], price=6.0)
    same = checkout(
        {
            "buyer_id": BUYER_ID,
            "order_id": b1["id"],
            "bag_checkout": True,
            "shipping_method": "hand",
            "bag_lines": [
                {"order_id": b1["id"], "product_id": p1["id"], "seller_id": SELLER_ID},
                {"order_id": b2["id"], "product_id": p1["id"], "seller_id": SELLER_ID},
            ],
        },
        BUYER,
    )
    ev["same_sku_over_stock"] = {
        "http": same["http"],
        "err": (same.get("body") or {}).get("error") if isinstance(same.get("body"), dict) else same.get("raw", "")[:300],
        "session": (same.get("body") or {}).get("sessionId") if isinstance(same.get("body"), dict) else None,
    }
    rec_find(
        "CR-P2-01",
        "P1",
        "Bag mesmo SKU qty=2 com stock=1 criou Session",
        invariant="I1/I10/I11",
        comportamento="Checkout de saco com duas linhas do mesmo SKU e stock=1.",
        regra="Quote soma qty por produto e bloqueia se need > stock.",
        intencional="Não deve criar captura.",
        autoridade="resolveServerCheckoutQuote qtyByProduct.",
        invariante_quebrada="I10",
        impacto="Captura sobre quantidade acima do stock.",
        evidence_obj=ev["same_sku_over_stock"],
        broken=ev["same_sku_over_stock"]["http"] in (200, 201) and bool(ev["same_sku_over_stock"]["session"]),
    )

    # paid bag via e2e then refund one line
    bag = e2e({"probe": "setup_paid_bag", "buyer_id": BUYER_ID, "seller_id": SELLER_ID})
    ev["setup_paid_bag"] = {"http": bag["http"], "body": bag.get("body") if isinstance(bag.get("body"), dict) else bag.get("raw", "")[:800]}
    b = bag.get("body") if isinstance(bag.get("body"), dict) else {}
    for k in ("product_a_id", "product_b_id"):
        if b.get(k):
            cleanup_products.append(str(b[k]))
    oid_a, oid_b = b.get("order_a_id"), b.get("order_b_id")
    pi = b.get("payment_intent_id")
    if oid_a and oid_b and pi:
        # concurrent refund both lines (seller)
        extra = {}
        if E2E:
            extra["x-fleaber-crash-inject-secret"] = E2E

        def refund_line(oid: str) -> dict[str, Any]:
            return fn("refund-order", SELLER, {"order_id": oid}, extra=extra)

        with ThreadPoolExecutor(max_workers=2) as ex:
            ra, rb = ex.submit(refund_line, str(oid_a)), ex.submit(refund_line, str(oid_b))
            rr = [ra.result(), rb.result()]
        after_a, after_b = get_order(str(oid_a)), get_order(str(oid_b))
        listed = e2e({"probe": "list_stripe_refunds", "payment_intent_id": pi})
        listed_b = listed.get("body") if isinstance(listed.get("body"), dict) else {}
        refunds = listed_b.get("refunds") or []
        refund_sum = sum(n(x.get("amount")) for x in refunds if str(x.get("status")).lower() not in ("failed", "canceled"))
        pi_amt = n(listed_b.get("payment_intent", {}).get("amount_received") or listed_b.get("payment_intent", {}).get("amount") or b.get("pi_amount_cents"))
        meta_orders = [str((x.get("metadata") or {}).get("fleaber_order_id") or "") for x in refunds]
        ev["bag_dual_refund"] = {
            "refund_http": [x["http"] for x in rr],
            "refund_bodies": [x.get("body") for x in rr],
            "order_a": after_a,
            "order_b": after_b,
            "refund_sum": refund_sum,
            "pi_amt": pi_amt,
            "meta_orders": meta_orders,
            "refund_count": listed_b.get("refund_count"),
        }
        rec_race("p2_bag_parallel_refund", ev["bag_dual_refund"])
        # Did refund of A mark B refunded without money?
        a_ref = str((after_a or {}).get("stripe_refund_id") or "")
        b_ref = str((after_b or {}).get("stripe_refund_id") or "")
        same_refund_id = a_ref and b_ref and a_ref == b_ref
        rec_find(
            "CR-P2-02",
            "P1",
            "Refund de uma linha do saco reutiliza refund da outra",
            invariant="I6/I2",
            comportamento="Refund paralelo das duas linhas que partilham PaymentIntent.",
            regra="Cada linha tem refund Stripe com metadata fleaber_order_id próprio.",
            intencional="Não.",
            autoridade="findExistingOrderRefund + amount_paid_cents da linha.",
            invariante_quebrada="I6",
            impacto="Linha marcada refundada sem devolução correspondente.",
            evidence_obj=ev["bag_dual_refund"],
            broken=bool(same_refund_id),
        )
        over_refund = pi_amt > 0 and refund_sum > pi_amt + 1
        rec_find(
            "CR-P2-03",
            "P0",
            "Σ refunds Stripe do saco > captura do PI",
            invariant="I2",
            comportamento="Dois refunds sobre PI partilhado.",
            regra="amount_paid_cents por linha; residual do PI.",
            intencional="Não.",
            autoridade="refund-order cap remaining.",
            invariante_quebrada="I2",
            impacto="Dinheiro devolvido acima do capturado.",
            evidence_obj={"refund_sum": refund_sum, "pi_amt": pi_amt},
            broken=over_refund,
        )
        sum_paid = n((after_a or {}).get("amount_paid_cents")) + n((after_b or {}).get("amount_paid_cents"))
        ev["sum_amount_paid"] = {"sum": sum_paid, "pi": pi_amt, "invariant": abs(sum_paid - pi_amt) <= 1}
        rec_find(
            "CR-P2-04",
            "P1",
            "Σ amount_paid_cents das linhas ≠ captura",
            invariant="I2",
            comportamento="Após settle de saco, soma das parcelas vs PI.",
            regra="Alocação proporcional; última linha recebe resto.",
            intencional="Arredondamento ±1 cêntimo aceitável.",
            autoridade="settlePaidBagOrders.",
            invariante_quebrada="I2",
            impacto="Parcela incorrecta distorce refunds posteriores.",
            evidence_obj=ev["sum_amount_paid"],
            broken=pi_amt > 0 and abs(sum_paid - pi_amt) > 1,
        )

    evidence["passes"]["pass2"] = ev


# ---------------------------------------------------------------------------
# PASS 3+4 — RELEASE × REFUND × PARTIAL × PAYOUT × CLAWBACK
# ---------------------------------------------------------------------------
def pass3_4() -> None:
    ev: dict[str, Any] = {}
    setup = e2e({"probe": "setup_paid_order", "buyer_id": BUYER_ID, "seller_id": SELLER_ID, "initial_qty": 2})
    ev["setup"] = {"http": setup["http"], "body": setup.get("body") if isinstance(setup.get("body"), dict) else setup.get("raw", "")[:800]}
    b = setup.get("body") if isinstance(setup.get("body"), dict) else {}
    oid = str(b.get("order_id") or "")
    pid = str(b.get("product_id") or "")
    pi = str(b.get("payment_intent_id") or "")
    if pid:
        cleanup_products.append(pid)
    if not oid:
        evidence["passes"]["pass3_4"] = ev
        return
    cleanup_orders.append(oid)
    before_s = get_wallet(SELLER_ID)
    before_b = get_wallet(BUYER_ID)
    captured = n((get_order(oid) or {}).get("amount_paid_cents"))

    # logistics → concluido
    rest("PATCH", "orders", SELLER, {"status": "enviado"}, qs=f"id=eq.{oid}")
    rest("PATCH", "orders", BUYER, {"status": "concluido"}, qs=f"id=eq.{oid}")
    ev["after_concluido"] = get_order(oid)

    rel = rpc("batata_release_seller_wallet_for_order", BUYER, {"p_order_id": oid})
    rel2 = rpc("batata_release_seller_wallet_for_order", BUYER, {"p_order_id": oid})
    ev["release"] = {"first": rel, "retry": rel2, "seller_wallet": get_wallet(SELLER_ID), "net": net_order(oid), "txs": wallet_txs(oid)}
    rec_find(
        "CR-P3-01",
        "P0",
        "Retry de release duplica crédito seller",
        invariant="I8/I2",
        comportamento="Duas chamadas seguidas de batata_release_seller_wallet_for_order.",
        regra="Flag wallet_release_processed_at + credit_wallet_once.",
        intencional="Não.",
        autoridade="RPC release.",
        invariante_quebrada="I8",
        impacto="Mint de saldo levantável.",
        evidence_obj=ev["release"],
        broken=get_wallet(SELLER_ID) > before_s + captured / 100.0 + 0.05,
    )

    # concurrent release || refund path: another paid order
    setup2 = e2e({"probe": "setup_paid_order", "buyer_id": BUYER_ID, "seller_id": SELLER_ID, "initial_qty": 2})
    b2 = setup2.get("body") if isinstance(setup2.get("body"), dict) else {}
    oid2 = str(b2.get("order_id") or "")
    if b2.get("product_id"):
        cleanup_products.append(str(b2["product_id"]))
    if oid2:
        cleanup_orders.append(oid2)
        rest("PATCH", "orders", SELLER, {"status": "enviado"}, qs=f"id=eq.{oid2}")
        rest("PATCH", "orders", BUYER, {"status": "concluido"}, qs=f"id=eq.{oid2}")
        # seller tries devolvida while buyer releases
        def rel_f() -> dict[str, Any]:
            return rpc("batata_release_seller_wallet_for_order", BUYER, {"p_order_id": oid2})

        def dev_f() -> dict[str, Any]:
            return rest("PATCH", "orders", SELLER, {"status": "devolvida"}, qs=f"id=eq.{oid2}")

        with ThreadPoolExecutor(max_workers=2) as ex:
            x1, x2 = ex.submit(rel_f), ex.submit(dev_f)
            ev["release_vs_devolvida"] = {"rel": x1.result(), "dev": x2.result()}
        o2 = get_order(oid2)
        net2 = net_order(oid2)
        ev["release_vs_devolvida_after"] = {"order": o2, "net": net2, "txs": wallet_txs(oid2), "captured": n((o2 or {}).get("amount_paid_cents"))}
        rec_race("p3_release_parallel_devolvida", ev["release_vs_devolvida_after"])
        cap_eur = n((o2 or {}).get("amount_paid_cents")) / 100.0
        rec_find(
            "CR-P3-02",
            "P0",
            "Release || devolvida distribui acima da captura",
            invariant="I6/I2",
            comportamento="Release seller e PATCH devolvida em paralelo na mesma order paga.",
            regra="Ambos fazem FOR UPDATE na order; remaining cap.",
            intencional="Não.",
            autoridade="RPCs wallet + trigger status.",
            invariante_quebrada="I6",
            impacto="Buyer e seller creditados acima dos fundos.",
            evidence_obj=ev["release_vs_devolvida_after"],
            broken=cap_eur > 0 and net2 > cap_eur + 0.02,
        )

    # payout after release on oid
    seller_bal = get_wallet(SELLER_ID)
    payout_amt = max(1, int(round(min(seller_bal, 5.0) * 100))) if seller_bal >= 0.50 else 0
    ev["payout_pre"] = {"seller_balance": seller_bal, "attempt_cents": payout_amt}
    k1 = f"comprace_{TAG}_po1_{uuid.uuid4().hex[:10]}"
    k2 = f"comprace_{TAG}_po2_{uuid.uuid4().hex[:10]}"
    extra = {}
    if E2E:
        extra["x-fleaber-crash-inject-secret"] = E2E

    def payout(key: str, cents: int, crash: str | None = None) -> dict[str, Any]:
        body: dict[str, Any] = {"user_id": SELLER_ID, "amount": cents, "idempotency_key": key}
        if crash:
            body["crash_inject"] = crash
            extra2 = dict(extra)
            extra2["x-fleaber-crash-inject"] = crash
            return fn("create-connect-account", SELLER, body, extra=extra2)
        return fn("create-connect-account", SELLER, body, extra=extra)

    if payout_amt >= 50:
        with ThreadPoolExecutor(max_workers=2) as ex:
            pa, pb = ex.submit(payout, k1, payout_amt), ex.submit(payout, k1, payout_amt)
            same_key = [pa.result(), pb.result()]
        ev["payout_same_key_parallel"] = {
            "http": [x["http"] for x in same_key],
            "bodies": [x.get("body") for x in same_key],
            "wallet": get_wallet(SELLER_ID),
        }
        led = rows(rest("GET", "wallet_payout_ledger", SVC, qs=f"idempotency_key=eq.{k1}&select=*"))
        ev["payout_ledger_k1"] = led
        transfers = [x.get("stripe_transfer_id") for x in led if x.get("stripe_transfer_id")]
        rec_find(
            "CR-P4-01",
            "P0",
            "Mesma idempotency_key de payout criou duas Transfers",
            invariant="I4",
            comportamento="Dois POSTs paralelos create-connect-account com a mesma key.",
            regra="Ledger unique + Stripe idempotency fleaber_wd_<key>.",
            intencional="Não.",
            autoridade="batata_wallet_payout_debit + Stripe Transfer idempotency.",
            invariante_quebrada="I4",
            impacto="Dois levantamentos para uma intenção.",
            evidence_obj={"ledger": led, "http": ev["payout_same_key_parallel"]["http"]},
            broken=len(set(filter(None, transfers))) > 1,
        )

        # crash after debit
        kcrash = f"comprace_{TAG}_crash_{uuid.uuid4().hex[:8]}"
        cents2 = 50
        if get_wallet(SELLER_ID) * 100 >= cents2:
            c1 = payout(kcrash, cents2, crash="after_debit_before_stripe")
            c2 = payout(kcrash, cents2)  # retry same key
            ev["payout_crash_debit"] = {"crash": c1.get("body"), "retry": c2.get("body"), "ledger": rows(rest("GET", "wallet_payout_ledger", SVC, qs=f"idempotency_key=eq.{kcrash}&select=*"))}
            rec_race("p4_crash_after_debit", ev["payout_crash_debit"])

            kcrash2 = f"comprace_{TAG}_c2_{uuid.uuid4().hex[:8]}"
            c3 = payout(kcrash2, cents2, crash="after_stripe_before_finish")
            c4 = payout(kcrash2, cents2)
            ev["payout_crash_transfer"] = {"crash": c3.get("body"), "retry": c4.get("body"), "ledger": rows(rest("GET", "wallet_payout_ledger", SVC, qs=f"idempotency_key=eq.{kcrash2}&select=*"))}

            # two legitimate same amount
            kL1 = f"comprace_{TAG}_leg1_{uuid.uuid4().hex[:8]}"
            kL2 = f"comprace_{TAG}_leg2_{uuid.uuid4().hex[:8]}"
            # ensure first finished
            time.sleep(1)
            l1 = payout(kL1, cents2)
            l2 = payout(kL2, cents2)
            led1 = rows(rest("GET", "wallet_payout_ledger", SVC, qs=f"idempotency_key=eq.{kL1}&select=*"))
            led2 = rows(rest("GET", "wallet_payout_ledger", SVC, qs=f"idempotency_key=eq.{kL2}&select=*"))
            ev["two_legit"] = {"l1": l1.get("body"), "l2": l2.get("body"), "led1": led1, "led2": led2}
            remapped = False
            if led2 and led1 and str(led2[0].get("idempotency_key")) == str(led1[0].get("idempotency_key")):
                remapped = True
            rec_find(
                "CR-P4-02",
                "P1",
                "Segunda intenção de payout do mesmo valor foi engolida",
                invariant="I5",
                comportamento="Duas keys distintas, mesmo amount_cents, após a primeira ter terminado (ou órfã).",
                regra="Remap só para órfão debited; duas intenções concluídas devem coexistir.",
                intencional="Remap de crash é produto; remap de intenções concluídas não.",
                autoridade="create-connect-account orphan resume.",
                invariante_quebrada="I5",
                impacto="Seller não consegue dois levantamentos legítimos do mesmo valor.",
                evidence_obj=ev["two_legit"],
                broken=remapped and str((l1.get("body") or {}).get("transferId") or "") == str((l2.get("body") or {}).get("transferId") or "") and str((l2.get("body") or {}).get("transferId") or "") != "",
            )
    else:
        ev["payout_skipped"] = "saldo seller < 0.50 EUR após release"

    # clawback after draining wallet (fungible)
    # If payout succeeded, wallet may already be low. Force-drain remaining release credit via service_role fixture.
    o_live = get_order(oid)
    if o_live and n(o_live.get("amount_paid_cents")) > 0:
        # dispute + partial after possible drain
        ins = rest(
            "POST",
            "order_disputes",
            BUYER,
            {
                "order_id": oid,
                "buyer_id": BUYER_ID,
                "reason": "outro",
                "description": f"{TAG} partial race",
            },
        )
        drow = row(ins)
        ev["dispute_insert"] = {"http": ins["http"], "row": drow}
        if drow and drow.get("id"):
            rest(
                "PATCH",
                "order_disputes",
                SELLER,
                {
                    "seller_offer_type": "partial_refund",
                    "seller_refund_percent": 50,
                    "current_turn": "comprador",
                },
                qs=f"id=eq.{drow['id']}",
            )
            # drain seller wallet to 0 to simulate payout already taken (fixture)
            rest("PATCH", "wallets", SVC, {"balance": 0}, qs=f"id=eq.{SELLER_ID}")
            ev["wallet_drained_fixture"] = True
            part = rpc("batata_process_partial_refund_dispute", BUYER, {"p_order_id": oid, "p_refund_percent": 50})
            part2 = rpc("batata_process_partial_refund_dispute", BUYER, {"p_order_id": oid, "p_refund_percent": 80})
            after_w_s = get_wallet(SELLER_ID)
            after_w_b = get_wallet(BUYER_ID)
            netp = net_order(oid)
            cap_eur = captured / 100.0
            ev["partial_after_drain"] = {
                "part": part,
                "retry_higher_pct": part2,
                "seller_wallet": after_w_s,
                "buyer_wallet": after_w_b,
                "buyer_delta": after_w_b - before_b,
                "seller_end": after_w_s,
                "net": netp,
                "captured_eur": cap_eur,
                "txs": wallet_txs(oid),
            }
            rec_race("p3_partial_after_wallet_drain", ev["partial_after_drain"])
            # mint if seller wallet rose from 0 after clawback failed to recover AND buyer also credited
            rec_find(
                "CR-P3-03",
                "P0",
                "Partial após carteira seller vazia reminta residual",
                invariant="I6/I2",
                comportamento="Release feito; saldo seller forçado a 0 (payout/fungível); buyer aceita partial.",
                regra="Clawback deve recuperar o crédito 'venda' antes de novo split. Floor a 0 sem bloquear o refund cria furo.",
                intencional="Proteção ao comprador pode ser produto; remint seller NÃO.",
                autoridade="batata_clawback + remaining.",
                invariante_quebrada="I6",
                impacto="Buyer creditado + seller volta a receber residual sem recuperação do primeiro crédito.",
                evidence_obj=ev["partial_after_drain"],
                broken=after_w_s > 0.01 and (after_w_b - before_b) > 0.01 and netp > cap_eur + 0.02,
            )
            rec_find(
                "CR-P3-04",
                "P1",
                "Partial retry com percent diferente altera o resultado",
                invariant="I8",
                comportamento="Segunda chamada process_partial com 80% após 50%.",
                regra="Flag wallet_refund_processed_at congela.",
                intencional="Não.",
                autoridade="RPC partial.",
                invariante_quebrada="I8",
                impacto="Split económico muda no retry.",
                evidence_obj={"first": part, "second": part2, "net": netp},
                broken=False if (part2.get("body") in (False, None) or (isinstance(part2.get("body"), dict) and part2["body"].get("ok") is False)) else (
                    isinstance(part.get("body"), (bool, dict)) and part2.get("http") == 200 and str(part.get("raw")) != str(part2.get("raw")) and netp > cap_eur + 0.02
                ),
            )

    # Stripe refund vs wallet on a FRESH paid order
    setup3 = e2e({"probe": "setup_paid_order", "buyer_id": BUYER_ID, "seller_id": SELLER_ID, "initial_qty": 1})
    b3 = setup3.get("body") if isinstance(setup3.get("body"), dict) else {}
    oid3 = str(b3.get("order_id") or "")
    pi3 = str(b3.get("payment_intent_id") or "")
    if b3.get("product_id"):
        cleanup_products.append(str(b3["product_id"]))
    if oid3:
        cleanup_orders.append(oid3)
        rest("PATCH", "orders", SELLER, {"status": "enviado"}, qs=f"id=eq.{oid3}")
        rest("PATCH", "orders", BUYER, {"status": "concluido"}, qs=f"id=eq.{oid3}")
        rpc("batata_release_seller_wallet_for_order", BUYER, {"p_order_id": oid3})
        extra = {}
        if E2E:
            extra["x-fleaber-crash-inject-secret"] = E2E

        def stripe_refund() -> dict[str, Any]:
            return fn("refund-order", SELLER, {"order_id": oid3}, extra=extra)

        def stripe_refund_crash() -> dict[str, Any]:
            extra2 = dict(extra)
            extra2["x-fleaber-crash-inject"] = "after_stripe_before_db"
            return fn("refund-order", SELLER, {"order_id": oid3, "crash_inject": "after_stripe_before_db"}, extra=extra2)

        crash_r = stripe_refund_crash()
        retry_r = stripe_refund()
        listed = e2e({"probe": "list_stripe_refunds", "payment_intent_id": pi3}) if pi3 else {}
        ev["refund_crash"] = {
            "crash": crash_r.get("body"),
            "retry": retry_r.get("body"),
            "order": get_order(oid3),
            "stripe": listed.get("body") if isinstance(listed, dict) else None,
            "net": net_order(oid3),
            "txs": wallet_txs(oid3),
        }
        rec_race("p3_refund_crash_retry", ev["refund_crash"])
        listed_b = listed.get("body") if isinstance(listed.get("body"), dict) else {}
        rcount = n(listed_b.get("refund_count"))
        rec_find(
            "CR-P3-05",
            "P0",
            "Crash após refund Stripe + retry cria dois refunds",
            invariant="I8/I3",
            comportamento="refund-order crash_inject after_stripe_before_db e retry.",
            regra="Idempotency fleaber_order_refund_<order> + metadata order_id.",
            intencional="Não.",
            autoridade="refund-order.",
            invariante_quebrada="I8",
            impacto="Dois refunds Stripe da mesma order.",
            evidence_obj=ev["refund_crash"],
            broken=rcount > 1,
        )

    evidence["passes"]["pass3_4"] = ev


# ---------------------------------------------------------------------------
# PASS 5 — DISPUTE × MONEY
# ---------------------------------------------------------------------------
def pass5() -> None:
    ev: dict[str, Any] = {}
    setup = e2e({"probe": "setup_paid_order", "buyer_id": BUYER_ID, "seller_id": SELLER_ID, "initial_qty": 1})
    b = setup.get("body") if isinstance(setup.get("body"), dict) else {}
    oid = str(b.get("order_id") or "")
    if b.get("product_id"):
        cleanup_products.append(str(b["product_id"]))
    if not oid:
        evidence["passes"]["pass5"] = ev
        return
    cleanup_orders.append(oid)
    rest("PATCH", "orders", SELLER, {"status": "enviado"}, qs=f"id=eq.{oid}")
    d = row(
        rest(
            "POST",
            "order_disputes",
            BUYER,
            {"order_id": oid, "buyer_id": BUYER_ID, "reason": "danificado", "description": f"{TAG} d5"},
        )
    )
    ev["dispute"] = d
    if not d:
        evidence["passes"]["pass5"] = ev
        return
    did = d["id"]
    # seller offer
    rest(
        "PATCH",
        "order_disputes",
        SELLER,
        {"seller_offer_type": "partial_refund", "seller_refund_percent": 30, "current_turn": "comprador"},
        qs=f"id=eq.{did}",
    )
    # buyer tries current_turn administracao without resolve
    t1 = rest("PATCH", "order_disputes", BUYER, {"current_turn": "administracao"}, qs=f"id=eq.{did}")
    after = row(rest("GET", "order_disputes", SVC, qs=f"id=eq.{did}&select=*"))
    ev["turn_admin"] = {"http": t1["http"], "after": after}
    rec_find(
        "CR-P5-01",
        "P2",
        "Buyer força current_turn=administracao sem resolver",
        invariant="I14",
        comportamento="PATCH só current_turn enquanto disputa aberta.",
        regra="Turn administração só com status terminal.",
        intencional="Não (DoS de UI).",
        autoridade="batata_order_disputes_guard_authority.",
        invariante_quebrada="",
        impacto="UI bloqueada; não é mint.",
        evidence_obj=ev["turn_admin"],
        broken=str((after or {}).get("current_turn") or "").lower() == "administracao" and str((after or {}).get("status") or "").lower() == "aberta",
    )

    # close + partial concurrent
    rest("PATCH", "orders", BUYER, {"status": "concluido"}, qs=f"id=eq.{oid}")

    def close_d() -> dict[str, Any]:
        return rest("PATCH", "order_disputes", BUYER, {"status": "resolvida", "buyer_decision": "accepted"}, qs=f"id=eq.{did}")

    def partial_d() -> dict[str, Any]:
        return rpc("batata_process_partial_refund_dispute", BUYER, {"p_order_id": oid})

    def rel_d() -> dict[str, Any]:
        return rpc("batata_release_seller_wallet_for_order", BUYER, {"p_order_id": oid})

    with ThreadPoolExecutor(max_workers=3) as ex:
        f1, f2, f3 = ex.submit(close_d), ex.submit(partial_d), ex.submit(rel_d)
        ev["triple"] = {"close": f1.result().get("body"), "partial": f2.result().get("body"), "release": f3.result().get("body")}
    o = get_order(oid)
    cap = n((o or {}).get("amount_paid_cents")) / 100.0
    net = net_order(oid)
    ev["after_triple"] = {"order": o, "net": net, "cap": cap, "txs": wallet_txs(oid), "dispute": row(rest("GET", "order_disputes", SVC, qs=f"id=eq.{did}&select=*"))}
    rec_race("p5_close_partial_release", ev["after_triple"])
    rec_find(
        "CR-P5-02",
        "P0",
        "Disputa+release+partial distribuem acima da captura",
        invariant="I6",
        comportamento="close || partial || release em paralelo.",
        regra="Um único pool remaining por order.",
        intencional="Não.",
        autoridade="RPCs wallet.",
        invariante_quebrada="I6",
        impacto="Dois rails (release venda + reembolso) acima dos fundos.",
        evidence_obj=ev["after_triple"],
        broken=cap > 0 and net > cap + 0.02,
    )

    # review while dispute open — may already be concluido
    rev = rest(
        "POST",
        "reviews",
        BUYER,
        {
            "order_id": oid,
            "buyer_id": BUYER_ID,
            "rating": 5,
            "comment": f"{TAG} review-dispute",
            "author_role": "buyer",
        },
    )
    ev["review_during_dispute"] = {"http": rev["http"], "body": rev.get("body") if not isinstance(rev.get("body"), list) else row(rev)}
    evidence["passes"]["pass5"] = ev


# ---------------------------------------------------------------------------
# PASS 6 — RESERVATION × BAG × STOCK
# ---------------------------------------------------------------------------
def pass6() -> None:
    ev: dict[str, Any] = {}
    live = row(
        rest(
            "POST",
            "lives",
            SVC,
            {
                "seller_id": SELLER_ID,
                "title": f"{TAG} live",
                "status": "ended",
                "is_active": False,
            },
        )
    )
    if not live:
        # try vendedor_id
        live = row(rest("POST", "lives", SVC, {"seller_id": SELLER_ID, "status": "ended", "is_active": False, "title": f"{TAG} live"}))
    ev["live"] = live
    if live and live.get("id"):
        cleanup_lives.append(str(live["id"]))
        lid = str(live["id"])
        p = product(SELLER_ID, 1, 7.0, "P6-LI")
        li = row(
            rest(
                "POST",
                "live_items",
                SVC,
                {
                    "live_id": lid,
                    "product_id": p["id"],
                    "seller_id": SELLER_ID,
                    "title": f"{TAG} item",
                    "price": 7.0,
                    "quantity": 1,
                },
            )
        )
        ev["live_item"] = li
        if li and li.get("id"):
            liid = str(li["id"])
            # buyer pending high qty — waitlist, NOT a bug if stays pending
            pend = rest(
                "POST",
                "live_reservation_requests",
                BUYER,
                {
                    "live_id": lid,
                    "live_item_id": liid,
                    "buyer_id": BUYER_ID,
                    "seller_id": SELLER_ID,
                    "requested_qty": 9,
                    "status": "accepted",
                    "source": "fleaber_live",
                },
            )
            prow = row(pend)
            ev["buyer_insert_accepted"] = {"http": pend["http"], "row": prow}
            rec_find(
                "CR-P6-01",
                "P1",
                "Buyer JWT insere reserva já accepted",
                invariant="I12",
                comportamento="INSERT reservation status=accepted qty=9 com JWT buyer.",
                regra="Buyer só nasce pending; accept é seller.",
                intencional="pending qty alta = lista de espera (OK). accepted pelo buyer NÃO.",
                autoridade="batata_live_reservation_guard_authority.",
                invariante_quebrada="I12",
                impacto="Lista de espera vira slot aceite sem o vendedor.",
                evidence_obj=ev["buyer_insert_accepted"],
                broken=bool(prow) and str(prow.get("status") or "").lower() == "accepted",
            )
            # seller accepts two pendings over stock
            r1 = row(
                rest(
                    "POST",
                    "live_reservation_requests",
                    BUYER,
                    {
                        "live_id": lid,
                        "live_item_id": liid,
                        "buyer_id": BUYER_ID,
                        "seller_id": SELLER_ID,
                        "requested_qty": 1,
                        "status": "pending",
                        "source": "fleaber_live",
                    },
                )
            )
            r2 = row(
                rest(
                    "POST",
                    "live_reservation_requests",
                    BUYER,
                    {
                        "live_id": lid,
                        "live_item_id": liid,
                        "buyer_id": BUYER_ID,
                        "seller_id": SELLER_ID,
                        "requested_qty": 1,
                        "status": "pending",
                        "source": "fleaber_live",
                    },
                )
            )
            if r1 and r2:
                rest("PATCH", "live_reservation_requests", SELLER, {"status": "accepted"}, qs=f"id=eq.{r1['id']}")
                rest("PATCH", "live_reservation_requests", SELLER, {"status": "accepted"}, qs=f"id=eq.{r2['id']}")
                a1 = row(rest("GET", "live_reservation_requests", SVC, qs=f"id=eq.{r1['id']}&select=id,status,requested_qty"))
                a2 = row(rest("GET", "live_reservation_requests", SVC, qs=f"id=eq.{r2['id']}&select=id,status,requested_qty"))
                ev["seller_double_accept"] = {"a1": a1, "a2": a2}
                # transform to orders + checkout
                o1 = order(BUYER_ID, SELLER_ID, p["id"], price=7.0)
                o2 = order(BUYER_ID, SELLER_ID, p["id"], price=7.0)
                ck1 = checkout(
                    {
                        "buyer_id": BUYER_ID,
                        "order_id": o1["id"],
                        "product_id": p["id"],
                        "seller_id": SELLER_ID,
                        "shipping_method": "hand",
                        "reservation_request_id": r1["id"],
                        "live_item_id": liid,
                        "live_id": lid,
                    },
                    BUYER,
                )
                ck2 = checkout(
                    {
                        "buyer_id": BUYER_ID,
                        "order_id": o2["id"],
                        "product_id": p["id"],
                        "seller_id": SELLER_ID,
                        "shipping_method": "hand",
                        "reservation_request_id": r2["id"],
                        "live_item_id": liid,
                        "live_id": lid,
                    },
                    BUYER,
                )
                ev["accept_then_checkout"] = {
                    "ck1": {"http": ck1["http"], "err": (ck1.get("body") or {}).get("error") if isinstance(ck1.get("body"), dict) else None, "sid": (ck1.get("body") or {}).get("sessionId") if isinstance(ck1.get("body"), dict) else None},
                    "ck2": {"http": ck2["http"], "err": (ck2.get("body") or {}).get("error") if isinstance(ck2.get("body"), dict) else None, "sid": (ck2.get("body") or {}).get("sessionId") if isinstance(ck2.get("body"), dict) else None},
                }
                both_sess = bool(ev["accept_then_checkout"]["ck1"]["sid"]) and bool(ev["accept_then_checkout"]["ck2"]["sid"])
                rec_find(
                    "CR-P6-02",
                    "P1",
                    "Dois accepted acima do stock geram duas Sessions",
                    invariant="I12/I1",
                    comportamento="Seller aceita duas reservas qty=1 com live_item qty=1; ambos fazem checkout.",
                    regra="Accept pode ser waitlist; venda só no settle. Duas Sessions é TOCTOU, não venda.",
                    intencional="Accept acima da capacidade pode ser lista. Duas capturas válidas não.",
                    autoridade="Checkout quote + settle stock.",
                    invariante_quebrada="I12",
                    impacto="Só é P1 se ambas as Sessions existirem E o quote não reservar — risco de dupla captura.",
                    evidence_obj=ev["accept_then_checkout"],
                    broken=both_sess,
                )
            conv = rpc("batata_live_reservation_stripe_convert", BUYER, {"p_request_id": (r1 or {}).get("id"), "p_order_id": cleanup_orders[-1] if cleanup_orders else None})
            ev["jwt_convert"] = conv
            rec_find(
                "CR-P6-03",
                "P1",
                "Buyer JWT converte reserva em venda",
                invariant="I12",
                comportamento="RPC batata_live_reservation_stripe_convert com JWT buyer.",
                regra="Convert só service_role no settle.",
                intencional="Não.",
                autoridade="GRANT + RPC.",
                invariante_quebrada="I12",
                impacto="Waitlist → sold sem pagamento.",
                evidence_obj=conv,
                broken=isinstance(conv.get("body"), dict) and conv["body"].get("ok") is True,
            )
            # buyer PATCH pending → accepted
            if prow and str(prow.get("status")).lower() == "pending":
                up = rest("PATCH", "live_reservation_requests", BUYER, {"status": "accepted"}, qs=f"id=eq.{prow['id']}")
                live_row = row(rest("GET", "live_reservation_requests", SVC, qs=f"id=eq.{prow['id']}&select=id,status"))
                ev["buyer_patch_accept"] = {"http": up["http"], "row": live_row}
                rec_find(
                    "CR-P6-04",
                    "P1",
                    "Buyer PATCH pending→accepted",
                    invariant="I12",
                    comportamento="UPDATE status accepted pelo comprador.",
                    regra="Trigger reverte / exception.",
                    intencional="Não.",
                    autoridade="reservation guard.",
                    invariante_quebrada="I12",
                    impacto="Auto-aceitação.",
                    evidence_obj=ev["buyer_patch_accept"],
                    broken=str((live_row or {}).get("status") or "").lower() == "accepted",
                )
    evidence["passes"]["pass6"] = ev


# ---------------------------------------------------------------------------
# PASS 7 — STATES × REVIEW
# ---------------------------------------------------------------------------
def pass7() -> None:
    ev: dict[str, Any] = {}
    p = product(SELLER_ID, 2, 5.0, "P7-ST")
    # unpaid stripe-labelled
    o = order(BUYER_ID, SELLER_ID, p["id"], pm="Pagamento na app (Seguro Fleaber)", status="reserva_pendente")
    seq = []
    for st in ("entregue", "concluido", "enviado", "pago", "PAGO", "Concluido"):
        r = rest("PATCH", "orders", BUYER, {"status": st}, qs=f"id=eq.{o['id']}")
        live = get_order(o["id"])
        seq.append({"try": st, "http": r["http"], "status": (live or {}).get("status")})
    ev["buyer_aliases"] = seq
    rec_find(
        "CR-P7-01",
        "P1",
        "Buyer leva Stripe unpaid a estado terminal",
        invariant="I7/I14",
        comportamento="PATCH buyer entregue/concluido/pago em order plataforma sem captura.",
        regra="Logística exige pagamento confirmado; buyer nunca atesta pago.",
        intencional="Não.",
        autoridade="batata_orders_guard_paid_status.",
        invariante_quebrada="I7",
        impacto="Estados comerciais falsos.",
        evidence_obj=seq,
        broken=any(str(x["status"]).lower() in ("entregue", "concluido", "pago", "enviado") for x in seq),
    )
    rev = rest(
        "POST",
        "reviews",
        BUYER,
        {"order_id": o["id"], "buyer_id": BUYER_ID, "rating": 5, "comment": f"{TAG} fake", "author_role": "comprador"},
    )
    ev["review_unpaid"] = {"http": rev["http"], "body": rev.get("raw", "")[:400]}
    rec_find(
        "CR-P7-02",
        "P1",
        "Review em order plataforma não paga",
        invariant="I14",
        comportamento="INSERT reviews em reserva_pendente Stripe.",
        regra="Review só concluido/entregue com payment confirmed.",
        intencional="Não.",
        autoridade="batata_reviews_guard_insert.",
        invariante_quebrada="I14",
        impacto="Reputação falsa.",
        evidence_obj=ev["review_unpaid"],
        broken=rev["http"] in (200, 201),
    )
    # off-platform seller pago then review — product, not bypass
    o2 = order(BUYER_ID, SELLER_ID, p["id"], pm="MB WAY")
    rest("PATCH", "orders", SELLER, {"status": "pago"}, qs=f"id=eq.{o2['id']}")
    rest("PATCH", "orders", SELLER, {"status": "enviado"}, qs=f"id=eq.{o2['id']}")
    rest("PATCH", "orders", BUYER, {"status": "concluido"}, qs=f"id=eq.{o2['id']}")
    live2 = get_order(o2["id"])
    rev2 = rest(
        "POST",
        "reviews",
        BUYER,
        {"order_id": o2["id"], "buyer_id": BUYER_ID, "rating": 1, "comment": f"{TAG} mb", "author_role": "BUYER"},
    )
    rev3 = rest(
        "POST",
        "reviews",
        BUYER,
        {"order_id": o2["id"], "buyer_id": BUYER_ID, "rating": 5, "comment": f"{TAG} mb2", "author_role": "comprador"},
    )
    ev["mb_review"] = {"order": live2, "rev_alias": {"http": rev2["http"], "raw": rev2.get("raw", "")[:250]}, "dup": {"http": rev3["http"], "raw": rev3.get("raw", "")[:250]}}
    rec_find(
        "CR-P7-03",
        "P1",
        "Duas reviews por aliases author_role na mesma order",
        invariant="I7",
        comportamento="author_role BUYER depois comprador.",
        regra="Canonicalização + unique por papel.",
        intencional="Não.",
        autoridade="reviews guard.",
        invariante_quebrada="I7",
        impacto="Duas avaliações.",
        evidence_obj=ev["mb_review"],
        broken=rev2["http"] in (200, 201) and rev3["http"] in (200, 201),
    )
    evidence["passes"]["pass7"] = ev


# ---------------------------------------------------------------------------
# PASS 8 — FREE COMPOSITION
# ---------------------------------------------------------------------------
def pass8() -> None:
    ev: dict[str, Any] = {}
    # JWT mint RPCs
    mint_calls = []
    for name, body in [
        ("batata_credit_wallet_once", {"p_user_id": BUYER_ID, "p_order_id": str(uuid.uuid4()), "p_amount": 50, "p_type": "credito", "p_description": TAG}),
        ("batata_wallet_payout_debit", {"p_user_id": BUYER_ID, "p_amount_cents": 100, "p_idempotency_key": f"{TAG}_debit"}),
        ("batata_wallet_payout_finish", {"p_idempotency_key": f"{TAG}_debit", "p_stripe_transfer_id": "tr_fake", "p_failed": False}),
        ("batata_clawback_seller_wallet_for_order", {"p_order_id": str(uuid.uuid4())}),
    ]:
        r = rpc(name, BUYER, body)
        mint_calls.append({"rpc": name, "http": r["http"], "body": r.get("body")})
    ev["jwt_mint_rpcs"] = mint_calls
    rec_find(
        "CR-P8-01",
        "P0",
        "JWT executa credit/payout internos",
        invariant="I14",
        comportamento="authenticated EXECUTE em RPCs de mint/payout.",
        regra="GRANT só service_role.",
        intencional="Não.",
        autoridade="REVOKE authenticated.",
        invariante_quebrada="I14",
        impacto="Mint directo.",
        evidence_obj=mint_calls,
        broken=any(x["http"] == 200 and x["body"] not in (None, False) and not (isinstance(x["body"], dict) and x["body"].get("ok") is False) for x in mint_calls if "credit" in x["rpc"] or "payout_debit" in x["rpc"]),
    )

    # INSERT order with money cols
    p = product(SELLER_ID, 1, 5.0, "P8-INS")
    ins = rest(
        "POST",
        "orders",
        BUYER,
        {
            "buyer_id": BUYER_ID,
            "seller_id": SELLER_ID,
            "product_id": p["id"],
            "status": "pago",
            "amount_paid_cents": 99999,
            "stock_units_applied": 1,
            "stripe_payment_intent_id": "pi_fake_comprace",
            "price_total": 5,
            "quantity": 1,
            "payment_method": "Pagamento na app (Seguro Fleaber)",
        },
    )
    o = row(ins)
    live = get_order(str(o["id"])) if o else None
    ev["insert_money"] = {"http": ins["http"], "live": live}
    rec_find(
        "CR-P8-02",
        "P0",
        "JWT INSERT fabrica captura/stock",
        invariant="I14/I10",
        comportamento="INSERT pago + amount_paid_cents + PI fake.",
        regra="Guard money cols limpa flags no INSERT JWT.",
        intencional="Não.",
        autoridade="batata_orders_guard_money_cols.",
        invariante_quebrada="I14",
        impacto="Venda falsa com fundos.",
        evidence_obj=ev["insert_money"],
        broken=bool(live) and (n(live.get("amount_paid_cents")) > 0 or str(live.get("status")).lower() == "pago" and str(live.get("stripe_payment_intent_id") or "") != ""),
    )

    # seller mismatch: buyer order with product, then... product stays seller's
    # bag vs individual same SKU
    p2 = product(SELLER_ID, 1, 6.0, "P8-BAG-IND")
    o1 = order(BUYER_ID, SELLER_ID, p2["id"], price=6.0)
    o2 = order(BUYER_ID, SELLER_ID, p2["id"], price=6.0)
    ck_ind = checkout({"buyer_id": BUYER_ID, "order_id": o1["id"], "product_id": p2["id"], "seller_id": SELLER_ID, "shipping_method": "hand"}, BUYER)
    ck_bag = checkout(
        {
            "buyer_id": BUYER_ID,
            "order_id": o2["id"],
            "bag_checkout": True,
            "shipping_method": "hand",
            "bag_lines": [{"order_id": o2["id"], "product_id": p2["id"], "seller_id": SELLER_ID}],
        },
        BUYER,
    )
    ev["bag_and_individual"] = {
        "ind": {"http": ck_ind["http"], "sid": (ck_ind.get("body") or {}).get("sessionId") if isinstance(ck_ind.get("body"), dict) else None},
        "bag": {"http": ck_bag["http"], "sid": (ck_bag.get("body") or {}).get("sessionId") if isinstance(ck_bag.get("body"), dict) else None},
        "stock": get_product(p2["id"]),
    }
    rec_find(
        "CR-P8-03",
        "P2",
        "Checkout individual e bag simultâneos no mesmo SKU stock=1",
        invariant="I1",
        comportamento="Duas Sessions (linha + saco) sem reservar stock.",
        regra="Settle serializa. Sessions duplas = retry/TOCTOU.",
        intencional="Parcialmente (retry). Risco só na captura dupla.",
        autoridade="Settle.",
        invariante_quebrada="",
        impacto="Duas Sessions; não prova duas vendas.",
        evidence_obj=ev["bag_and_individual"],
        broken=False,
    )

    # payment_method alias to off-platform to skip capture gate
    o3 = order(BUYER_ID, SELLER_ID, p["id"], pm="Pagamento na app (Seguro Fleaber)")
    pm_try = rest("PATCH", "orders", BUYER, {"payment_method": "MB WAY", "status": "pago"}, qs=f"id=eq.{o3['id']}")
    live3 = get_order(o3["id"])
    ev["pm_swap"] = {"http": pm_try["http"], "order": live3}
    rec_find(
        "CR-P8-04",
        "P1",
        "Buyer troca payment_method para MB WAY e marca pago",
        invariant="I13/I14",
        comportamento="PATCH payment_method + status na mesma operação.",
        regra="payment_method imutável no money guard; status gated.",
        intencional="Não.",
        autoridade="money cols + paid status.",
        invariante_quebrada="I13",
        impacto="Plataforma vira off-platform sem captura.",
        evidence_obj=ev["pm_swap"],
        broken=str((live3 or {}).get("payment_method") or "").lower().find("mb") >= 0 and str((live3 or {}).get("status") or "").lower() == "pago",
    )

    # seller PATCH amount_paid
    o4 = order(BUYER_ID, SELLER_ID, p["id"], pm="MB WAY")
    rest("PATCH", "orders", SELLER, {"status": "pago"}, qs=f"id=eq.{o4['id']}")
    ap = rest("PATCH", "orders", SELLER, {"amount_paid_cents": 50000}, qs=f"id=eq.{o4['id']}")
    live4 = get_order(o4["id"])
    ev["seller_amount_paid"] = {"http": ap["http"], "order": live4}
    rec_find(
        "CR-P8-05",
        "P0",
        "Seller JWT escreve amount_paid_cents após MB WAY pago",
        invariant="I14/I2",
        comportamento="PATCH amount_paid_cents=50000 em order off-platform já pago.",
        regra="Money cols imutáveis para JWT.",
        intencional="Não — transformaria MB WAY em fundos plataforma.",
        autoridade="guard money cols.",
        invariante_quebrada="I14",
        impacto="Release wallet a partir de captura fabricada.",
        evidence_obj=ev["seller_amount_paid"],
        broken=n((live4 or {}).get("amount_paid_cents")) >= 50000,
    )
    if n((live4 or {}).get("amount_paid_cents")) >= 50000:
        rest("PATCH", "orders", SELLER, {"status": "enviado"}, qs=f"id=eq.{o4['id']}")
        rest("PATCH", "orders", BUYER, {"status": "concluido"}, qs=f"id=eq.{o4['id']}")
        rel = rpc("batata_release_seller_wallet_for_order", BUYER, {"p_order_id": o4["id"]})
        ev["release_forged_capture"] = {"rel": rel, "wallet": get_wallet(SELLER_ID), "net": net_order(o4["id"])}

    # first-row-wins: two products, stale bag metadata cannot be tested without Stripe session mutate.
    # null quantity order
    o5 = rest(
        "POST",
        "orders",
        BUYER,
        {
            "buyer_id": BUYER_ID,
            "seller_id": SELLER_ID,
            "product_id": p["id"],
            "quantity": None,
            "price_total": 5,
            "payment_method": "MB WAY",
            "status": "reserva_pendente",
        },
    )
    ev["null_qty"] = {"http": o5["http"], "row": row(o5)}

    # anon rest
    anon_orders = rest("GET", "orders", ANON, qs="select=id,buyer_id,amount_paid_cents&limit=3")
    ev["anon_orders"] = {"http": anon_orders["http"], "n": len(rows(anon_orders))}
    rec_find(
        "CR-P8-06",
        "P2",
        "Anon lê orders",
        invariant="I14",
        comportamento="GET orders com anon key.",
        regra="RLS parties only.",
        intencional="Não.",
        autoridade="RLS.",
        invariante_quebrada="",
        impacto="PII / financeiro.",
        evidence_obj=ev["anon_orders"],
        broken=anon_orders["http"] == 200 and len(rows(anon_orders)) > 0,
    )

    evidence["passes"]["pass8"] = ev


# ---------------------------------------------------------------------------
# PASS 9 variants of any P0/P1 + saturation
# ---------------------------------------------------------------------------
def pass9_sat() -> None:
    ev: dict[str, Any] = {}
    broken_before = {f["id"] for f in findings if f.get("broken") and f.get("sev") in ("P0", "P1")}
    # invert actors: seller tries buyer RPCs
    p = product(SELLER_ID, 1, 5.0, "P9-INV")
    o = order(BUYER_ID, SELLER_ID, p["id"], pm="Pagamento na app (Seguro Fleaber)")
    rel_s = rpc("batata_release_seller_wallet_for_order", SELLER, {"p_order_id": o["id"]})
    part_s = rpc("batata_process_partial_refund_dispute", SELLER, {"p_order_id": o["id"], "p_refund_percent": 100})
    ref_b = fn("refund-order", BUYER, {"order_id": o["id"]})
    ev["inverted"] = {"seller_release_unpaid": rel_s.get("body"), "seller_partial": part_s.get("http"), "buyer_refund_order": ref_b.get("http")}
    rec_find(
        "CR-P9-01",
        "P1",
        "Seller faz partial (buyer-only) em order unpaid",
        invariant="I14",
        comportamento="JWT seller chama process_partial.",
        regra="Buyer-only + fundos plataforma.",
        intencional="Não.",
        autoridade="RPC authz.",
        invariante_quebrada="I14",
        impacto="Mint se devolver true com crédito.",
        evidence_obj=ev["inverted"],
        broken=part_s.get("http") == 200 and part_s.get("body") is True,
    )

    # qty 99 vs stock 1 seller pago
    p2 = product(SELLER_ID, 1, 5.0, "P9-Q99")
    o99 = order(BUYER_ID, SELLER_ID, p2["id"], qty=1, pm="MB WAY")
    rest("PATCH", "orders", BUYER, {"quantity": 99}, qs=f"id=eq.{o99['id']}")
    live_q = get_order(o99["id"])
    rest("PATCH", "orders", SELLER, {"status": "pago"}, qs=f"id=eq.{o99['id']}")
    after = get_order(o99["id"])
    prod = get_product(p2["id"])
    ev["qty_bump"] = {"before_pago": live_q, "after": after, "product": prod}
    rec_find(
        "CR-P9-02",
        "P1",
        "Buyer aumenta quantity antes do pago MB WAY",
        invariant="I10",
        comportamento="PATCH quantity=99 depois INSERT qty=1; seller marca pago.",
        regra="contract_qty selado; JWT não muda quantity.",
        intencional="Não.",
        autoridade="seal + quantity authority.",
        invariante_quebrada="I10",
        impacto="Consome 99 de stock=1 ou aplica units inflacionadas.",
        evidence_obj=ev["qty_bump"],
        broken=n((after or {}).get("stock_units_applied")) > 1 or n((after or {}).get("quantity")) >= 99,
    )

    # null payment_method treated as platform vs off
    o_n = rest(
        "POST",
        "orders",
        BUYER,
        {
            "buyer_id": BUYER_ID,
            "seller_id": SELLER_ID,
            "product_id": p["id"],
            "quantity": 1,
            "price_total": 5,
            "status": "reserva_pendente",
        },
    )
    on = row(o_n)
    if on:
        rest("PATCH", "orders", SELLER, {"status": "pago"}, qs=f"id=eq.{on['id']}")
        ev["null_pm"] = get_order(on["id"])
        rec_find(
            "CR-P9-03",
            "P1",
            "payment_method vazio + seller pago (fail-closed plataforma?)",
            invariant="I13",
            comportamento="Order sem payment_method; seller PATCH pago.",
            regra="Vazio = plataforma fail-closed, exige captura.",
            intencional="Se permitir, vira off-platform implícito.",
            autoridade="is_platform_payment / is_off_platform.",
            invariante_quebrada="I13",
            impacto="Venda sem rail.",
            evidence_obj=ev["null_pm"],
            broken=str((ev["null_pm"] or {}).get("status") or "").lower() == "pago" and n((ev["null_pm"] or {}).get("amount_paid_cents")) <= 0,
        )

    broken_after = {f["id"] for f in findings if f.get("broken") and f.get("sev") in ("P0", "P1")}
    ev["new_p0p1_after_sat"] = sorted(broken_after - broken_before)
    evidence["passes"]["pass9_sat"] = ev
    evidence["saturation_new_classes"] = ev["new_p0p1_after_sat"]


def cleanup() -> None:
    # end lives we created
    for lid in cleanup_lives:
        rest("PATCH", "lives", SVC, {"status": "ended", "is_active": False}, qs=f"id=eq.{lid}")
    # do not delete orders with stripe (audit trail); mark products unsold leftover
    for pid in cleanup_products:
        rest("PATCH", "products", SVC, {"list_on_marketplace": False, "available_for_live": False}, qs=f"id=eq.{pid}")
    evidence["cleanup"] = {"products": cleanup_products, "orders": cleanup_orders, "lives": cleanup_lives}


def main() -> int:
    global URL, ANON, SVC, BUYER, SELLER, BUYER_ID, SELLER_ID, E2E
    env = load_env()
    URL = env["SUPABASE_URL"].strip().rstrip("/")
    for suffix in ("/rest/v1", "/auth/v1", "/functions/v1"):
        if URL.endswith(suffix):
            URL = URL[: -len(suffix)].rstrip("/")
    if STAGING_REF not in URL:
        print("ABORT: not staging", URL)
        return 2
    ANON = env["SUPABASE_ANON_KEY"]
    SVC = env["SUPABASE_SERVICE_ROLE_KEY"]
    E2E = env.get("FLEABER_STAGING_CRASH_INJECT_SECRET", "").strip()
    BUYER_ID = env["LIVE_OPS_TEST_BUYER_ID"]
    SELLER_ID = env["LIVE_OPS_TEST_SELLER_ID"]
    BUYER = login(env["LIVE_OPS_TEST_BUYER_EMAIL"], env["LIVE_OPS_TEST_BUYER_PASSWORD"])
    SELLER = login(env["LIVE_OPS_TEST_SELLER_EMAIL"], env["LIVE_OPS_TEST_SELLER_PASSWORD"])
    evidence["identities"] = {"buyer": BUYER_ID, "seller": SELLER_ID}

    errors = []
    for name, fn_pass in [
        ("pass1", pass1),
        ("pass2", pass2),
        ("pass3_4", pass3_4),
        ("pass5", pass5),
        ("pass6", pass6),
        ("pass7", pass7),
        ("pass8", pass8),
        ("pass9_sat", pass9_sat),
    ]:
        try:
            fn_pass()
            print(f"OK {name}")
        except Exception as e:
            errors.append({"pass": name, "error": repr(e)})
            print(f"ERR {name}: {e!r}")
            evidence.setdefault("errors", []).append({"pass": name, "error": repr(e)})
    try:
        cleanup()
    except Exception as e:
        evidence.setdefault("errors", []).append({"pass": "cleanup", "error": repr(e)})

    evidence["finished_at"] = datetime.now(timezone.utc).isoformat()
    evidence["findings_count"] = {
        "P0": sum(1 for f in findings if f.get("broken") and f.get("sev") == "P0"),
        "P1": sum(1 for f in findings if f.get("broken") and f.get("sev") == "P1"),
        "P2": sum(1 for f in findings if f.get("broken") and f.get("sev") == "P2"),
        "INFO": sum(1 for f in findings if not f.get("broken")),
    }
    REPORTS.mkdir(parents=True, exist_ok=True)
    ev_path = REPORTS / "COMP_RACE_20260827_EVIDENCE.json"
    rc_path = REPORTS / "COMP_RACE_20260827_RACES.json"
    if ev_path.exists() or rc_path.exists():
        stamp = datetime.now(timezone.utc).strftime("%H%M%S")
        ev_path = REPORTS / f"COMP_RACE_20260827_EVIDENCE_{stamp}.json"
        rc_path = REPORTS / f"COMP_RACE_20260827_RACES_{stamp}.json"
    ev_path.write_text(json.dumps({"evidence": evidence, "findings": findings}, indent=2, default=str), encoding="utf-8")
    rc_path.write_text(json.dumps(races, indent=2, default=str), encoding="utf-8")
    print("WROTE", ev_path)
    print("WROTE", rc_path)
    print("FINDINGS_BROKEN", [f["id"] for f in findings if f.get("broken")])
    return 0


if __name__ == "__main__":
    sys.exit(main())
