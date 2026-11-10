#!/usr/bin/env python3
# Follow-up COMP_RACE_20260827 — superfícies que a 1ª passagem não instrumentou bem.
# NÃO sobrescreve EVIDENCE/RACES originais.
from __future__ import annotations

import json
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = ROOT / "tool" / "live_ops_staging.env"
REPORTS = ROOT / "tool" / "reports"
TAG = f"COMP_RACE_20260827_B_{int(time.time())}"
STAGING_REF = "fxdknzrqjenzqcvnwqqq"


def load_env():
    out = {}
    for line in ENV_PATH.read_text(encoding="utf-8").splitlines():
        t = line.strip()
        if not t or t.startswith("#") or "=" not in t:
            continue
        k, v = t.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def req(method, url, token, body=None, extra=None, timeout=60):
    headers = {
        "apikey": ANON if token != SVC else SVC,
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }
    if extra:
        headers.update(extra)
    data = None if body is None else json.dumps(body).encode()
    r = Request(url, data=data, headers=headers, method=method)
    try:
        with urlopen(r, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", "replace")
            parsed = json.loads(raw) if raw else None
            return {"http": resp.status, "body": parsed, "raw": raw[:3000]}
    except HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            parsed = raw
        return {"http": e.code, "body": parsed, "raw": raw[:3000]}
    except URLError as e:
        return {"http": 0, "body": {"error": str(e.reason)}, "raw": str(e)}


def rest(method, path, token, body=None, qs=""):
    url = f"{URL}/rest/v1/{path}"
    if qs:
        url += f"?{qs}"
    return req(method, url, token, body)


def rpc(name, token, body):
    return req("POST", f"{URL}/rest/v1/rpc/{name}", token, body)


def fn(name, token, body, extra=None):
    return req("POST", f"{URL}/functions/v1/{name}", token, body, extra, timeout=90)


def login(email, password):
    r = req(
        "POST",
        f"{URL}/auth/v1/token?grant_type=password",
        ANON,
        {"email": email, "password": password},
        extra={"apikey": ANON, "Authorization": f"Bearer {ANON}"},
    )
    return r["body"]["access_token"]


def row(res):
    b = res.get("body")
    if isinstance(b, list) and b and isinstance(b[0], dict):
        return b[0]
    if isinstance(b, dict) and b.get("id"):
        return b
    return None


def main():
    global URL, ANON, SVC, BUYER, SELLER, BUYER_ID, SELLER_ID, E2E
    env = load_env()
    URL = env["SUPABASE_URL"].strip().rstrip("/")
    for s in ("/rest/v1", "/auth/v1", "/functions/v1"):
        if URL.endswith(s):
            URL = URL[: -len(s)].rstrip("/")
    ANON, SVC = env["SUPABASE_ANON_KEY"], env["SUPABASE_SERVICE_ROLE_KEY"]
    E2E = env.get("FLEABER_STAGING_CRASH_INJECT_SECRET", "").strip()
    BUYER_ID, SELLER_ID = env["LIVE_OPS_TEST_BUYER_ID"], env["LIVE_OPS_TEST_SELLER_ID"]
    BUYER = login(env["LIVE_OPS_TEST_BUYER_EMAIL"], env["LIVE_OPS_TEST_BUYER_PASSWORD"])
    SELLER = login(env["LIVE_OPS_TEST_SELLER_EMAIL"], env["LIVE_OPS_TEST_SELLER_PASSWORD"])
    extra = {}
    if E2E:
        extra["x-fleaber-e2e-secret"] = E2E
        extra["x-fleaber-crash-inject-secret"] = E2E

    out = {"tag": TAG, "at": datetime.now(timezone.utc).isoformat(), "tests": {}}

    # credit with correct signature
    mint = rpc(
        "batata_credit_wallet_once",
        BUYER,
        {
            "p_wallet_id": BUYER_ID,
            "p_order_id": str(uuid.uuid4()),
            "p_amount": 50,
            "p_type": "credito",
            "p_description": TAG,
        },
    )
    out["tests"]["credit_wallet_once_jwt"] = mint

    # reviews with stars
    p = row(
        rest(
            "POST",
            "products",
            SVC,
            {
                "seller_id": SELLER_ID,
                "title": f"{TAG} rev",
                "price": 5,
                "quantity": 2,
                "ref_code": f"CRB-{uuid.uuid4().hex[:8]}",
                "list_on_marketplace": True,
                "is_sold": False,
                "image_urls": [],
            },
        )
    )
    o_unpaid = row(
        rest(
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
                "payment_method": "Pagamento na app (Seguro Fleaber)",
            },
        )
    )
    rev_unpaid = rest(
        "POST",
        "reviews",
        BUYER,
        {
            "order_id": o_unpaid["id"],
            "buyer_id": BUYER_ID,
            "stars": 5,
            "comment": f"{TAG} unpaid",
            "author_role": "comprador",
        },
    )
    o_mb = row(
        rest(
            "POST",
            "orders",
            BUYER,
            {
                "buyer_id": BUYER_ID,
                "seller_id": SELLER_ID,
                "product_id": p["id"],
                "quantity": 1,
                "price_total": 5,
                "payment_method": "MB WAY",
            },
        )
    )
    rest("PATCH", "orders", SELLER, {"status": "pago"}, qs=f"id=eq.{o_mb['id']}")
    rest("PATCH", "orders", SELLER, {"status": "enviado"}, qs=f"id=eq.{o_mb['id']}")
    rest("PATCH", "orders", BUYER, {"status": "concluido"}, qs=f"id=eq.{o_mb['id']}")
    om = row(rest("GET", "orders", SVC, qs=f"id=eq.{o_mb['id']}&select=id,status,stock_units_applied,amount_paid_cents,payment_method"))
    rev1 = rest(
        "POST",
        "reviews",
        BUYER,
        {"order_id": o_mb["id"], "buyer_id": BUYER_ID, "stars": 1, "comment": f"{TAG} a", "author_role": "BUYER"},
    )
    rev2 = rest(
        "POST",
        "reviews",
        BUYER,
        {"order_id": o_mb["id"], "buyer_id": BUYER_ID, "stars": 5, "comment": f"{TAG} b", "author_role": "comprador"},
    )
    out["tests"]["reviews"] = {
        "unpaid": {"http": rev_unpaid["http"], "raw": rev_unpaid["raw"][:400]},
        "mb_order": om,
        "alias_buyer": {"http": rev1["http"], "raw": rev1["raw"][:400]},
        "alias_comprador": {"http": rev2["http"], "raw": rev2["raw"][:400]},
    }

    # reservation
    live = row(
        rest(
            "POST",
            "lives",
            SVC,
            {"seller_id": SELLER_ID, "title": f"{TAG} live", "status": "ended", "is_active": False},
        )
    )
    li = rest(
        "POST",
        "live_items",
        SVC,
        {
            "live_id": live["id"],
            "product_id": p["id"],
            "title": f"{TAG} item",
            "price": 7,
            "quantity": 1,
            "ref_code": f"CRB-LI-{uuid.uuid4().hex[:6]}",
            "status": "available",
            "is_active": False,
        },
    )
    out["tests"]["live_item_insert"] = {"http": li["http"], "raw": li["raw"][:500], "row": row(li)}
    lirow = row(li)
    if lirow:
        pend_acc = rest(
            "POST",
            "live_reservation_requests",
            BUYER,
            {
                "live_id": live["id"],
                "live_item_id": lirow["id"],
                "buyer_id": BUYER_ID,
                "seller_id": SELLER_ID,
                "requested_qty": 9,
                "status": "accepted",
                "source": "fleaber_live",
            },
        )
        prow = row(pend_acc)
        out["tests"]["buyer_insert_accepted"] = {"http": pend_acc["http"], "row": prow, "raw": pend_acc["raw"][:400]}
        r1 = row(
            rest(
                "POST",
                "live_reservation_requests",
                BUYER,
                {
                    "live_id": live["id"],
                    "live_item_id": lirow["id"],
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
                    "live_id": live["id"],
                    "live_item_id": lirow["id"],
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
            a1 = row(rest("GET", "live_reservation_requests", SVC, qs=f"id=eq.{r1['id']}&select=id,status,requested_qty,queue_position"))
            a2 = row(rest("GET", "live_reservation_requests", SVC, qs=f"id=eq.{r2['id']}&select=id,status,requested_qty,queue_position"))
            out["tests"]["double_accept"] = {"a1": a1, "a2": a2}
            if prow and str(prow.get("status")).lower() == "pending":
                up = rest("PATCH", "live_reservation_requests", BUYER, {"status": "accepted"}, qs=f"id=eq.{prow['id']}")
                livep = row(rest("GET", "live_reservation_requests", SVC, qs=f"id=eq.{prow['id']}&select=id,status"))
                out["tests"]["buyer_patch_accept"] = {"http": up["http"], "row": livep}
        conv = rpc(
            "batata_live_reservation_stripe_convert",
            BUYER,
            {"p_request_id": (r1 or {}).get("id"), "p_order_id": o_mb["id"]},
        )
        out["tests"]["jwt_convert"] = conv
        rest("PATCH", "lives", SVC, {"status": "ended", "is_active": False}, qs=f"id=eq.{live['id']}")

    # dispute on FRESH paid order
    setup = fn(
        "sec-fase2-e2e-oversell",
        SVC,
        {"probe": "setup_paid_order", "buyer_id": BUYER_ID, "seller_id": SELLER_ID, "initial_qty": 1},
        extra=extra,
    )
    b = setup.get("body") if isinstance(setup.get("body"), dict) else {}
    oid = b.get("order_id")
    out["tests"]["dispute_setup"] = {"http": setup["http"], "oid": oid}
    if oid:
        rest("PATCH", "orders", SELLER, {"status": "enviado"}, qs=f"id=eq.{oid}")
        d = rest(
            "POST",
            "order_disputes",
            BUYER,
            {"order_id": oid, "buyer_id": BUYER_ID, "reason": "danificado", "description": f"{TAG} d"},
        )
        drow = row(d)
        out["tests"]["dispute_insert"] = {"http": d["http"], "row": drow, "raw": d["raw"][:400]}
        if drow:
            did = drow["id"]
            rest(
                "PATCH",
                "order_disputes",
                SELLER,
                {"seller_offer_type": "partial_refund", "seller_refund_percent": 40, "current_turn": "comprador"},
                qs=f"id=eq.{did}",
            )
            tadmin = rest("PATCH", "order_disputes", BUYER, {"current_turn": "administracao"}, qs=f"id=eq.{did}")
            after_turn = row(rest("GET", "order_disputes", SVC, qs=f"id=eq.{did}&select=id,status,current_turn,seller_refund_percent"))
            rest("PATCH", "orders", BUYER, {"status": "concluido"}, qs=f"id=eq.{oid}")

            def close():
                return rest(
                    "PATCH",
                    "order_disputes",
                    BUYER,
                    {"status": "resolvida", "buyer_decision": "accepted"},
                    qs=f"id=eq.{did}",
                )

            def partial():
                return rpc("batata_process_partial_refund_dispute", BUYER, {"p_order_id": oid})

            def release():
                return rpc("batata_release_seller_wallet_for_order", BUYER, {"p_order_id": oid})

            with ThreadPoolExecutor(3) as ex:
                f1, f2, f3 = ex.submit(close), ex.submit(partial), ex.submit(release)
                out["tests"]["triple_race"] = {
                    "close": f1.result(),
                    "partial": f2.result(),
                    "release": f3.result(),
                }
            oafter = row(
                rest(
                    "GET",
                    "orders",
                    SVC,
                    qs=f"id=eq.{oid}&select=id,status,amount_paid_cents,wallet_release_processed_at,wallet_refund_processed_at",
                )
            )
            txs = rest("GET", "wallet_transactions", SVC, qs=f"order_id=eq.{oid}&select=amount,type,wallet_id")
            net = 0.0
            for t in txs.get("body") or []:
                typ = str(t.get("type") or "").lower()
                amt = float(t.get("amount") or 0)
                if typ in ("venda", "reembolso"):
                    net += amt
                elif typ == "estorno":
                    net -= amt
            out["tests"]["after_triple"] = {
                "order": oafter,
                "net": round(net, 2),
                "cap": (oafter or {}).get("amount_paid_cents"),
                "txs": txs.get("body"),
                "turn_admin": {"http": tadmin["http"], "after": after_turn},
            }
            rev_d = rest(
                "POST",
                "reviews",
                BUYER,
                {
                    "order_id": oid,
                    "buyer_id": BUYER_ID,
                    "stars": 5,
                    "comment": f"{TAG} during dispute",
                    "author_role": "comprador",
                },
            )
            out["tests"]["review_paid_stripe"] = {"http": rev_d["http"], "raw": rev_d["raw"][:400]}

    # concurrent GET settle of two sessions already created — unpaid, expect not paid
    # plus JWT convert grant check already above

    path = REPORTS / "COMP_RACE_20260827_EVIDENCE_B.json"
    if path.exists():
        path = REPORTS / f"COMP_RACE_20260827_EVIDENCE_B_{int(time.time())}.json"
    path.write_text(json.dumps(out, indent=2, default=str), encoding="utf-8")
    print("WROTE", path)
    print(json.dumps({k: {kk: vv if kk != "raw" else str(vv)[:80] for kk, vv in (v.items() if isinstance(v, dict) else [])} if isinstance(v, dict) else v for k, v in out["tests"].items()}, default=str)[:2000])


if __name__ == "__main__":
    main()
