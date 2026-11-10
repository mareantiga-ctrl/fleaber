#!/usr/bin/env python3
# COMP_RACE follow-up C — live_item kind correcto + disputa após concluido.
from __future__ import annotations
import json, time, uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
ENV = {}
for line in (ROOT / "tool/live_ops_staging.env").read_text(encoding="utf-8").splitlines():
    t = line.strip()
    if t and not t.startswith("#") and "=" in t:
        k, v = t.split("=", 1)
        ENV[k.strip()] = v.strip()
URL = ENV["SUPABASE_URL"].strip().rstrip("/")
for s in ("/rest/v1", "/auth/v1", "/functions/v1"):
    if URL.endswith(s):
        URL = URL[: -len(s)].rstrip("/")
ANON, SVC = ENV["SUPABASE_ANON_KEY"], ENV["SUPABASE_SERVICE_ROLE_KEY"]
E2E = ENV.get("FLEABER_STAGING_CRASH_INJECT_SECRET", "").strip()
BUYER_ID, SELLER_ID = ENV["LIVE_OPS_TEST_BUYER_ID"], ENV["LIVE_OPS_TEST_SELLER_ID"]


def req(method, url, token, body=None):
    headers = {
        "apikey": ANON if token != SVC else SVC,
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }
    data = None if body is None else json.dumps(body).encode()
    r = Request(url, data=data, headers=headers, method=method)
    try:
        with urlopen(r, timeout=90) as resp:
            raw = resp.read().decode("utf-8", "replace")
            return {"http": resp.status, "body": json.loads(raw) if raw else None, "raw": raw[:1500]}
    except HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        try:
            parsed = json.loads(raw)
        except Exception:
            parsed = raw
        return {"http": e.code, "body": parsed, "raw": raw[:1500]}


def rest(m, path, tok, body=None, qs=""):
    return req(m, f"{URL}/rest/v1/{path}" + (f"?{qs}" if qs else ""), tok, body)


def rpc(name, tok, body):
    return req("POST", f"{URL}/rest/v1/rpc/{name}", tok, body)


def login(email, pw):
    r = req("POST", f"{URL}/auth/v1/token?grant_type=password", ANON, {"email": email, "password": pw})
    return r["body"]["access_token"]


def row(res):
    b = res.get("body")
    if isinstance(b, list) and b:
        return b[0]
    if isinstance(b, dict) and b.get("id"):
        return b
    return None


def main():
    BUYER = login(ENV["LIVE_OPS_TEST_BUYER_EMAIL"], ENV["LIVE_OPS_TEST_BUYER_PASSWORD"])
    SELLER = login(ENV["LIVE_OPS_TEST_SELLER_EMAIL"], ENV["LIVE_OPS_TEST_SELLER_PASSWORD"])
    extra = {"x-fleaber-e2e-secret": E2E, "x-fleaber-crash-inject-secret": E2E} if E2E else {}
    out = {"tag": f"COMP_RACE_C_{int(time.time())}", "at": datetime.now(timezone.utc).isoformat()}

    p = row(rest("POST", "products", SVC, {
        "seller_id": SELLER_ID, "title": "COMP_RACE_C item", "price": 7, "quantity": 1,
        "ref_code": f"CRC-{uuid.uuid4().hex[:8]}", "list_on_marketplace": True, "is_sold": False, "image_urls": [],
    }))
    live = row(rest("POST", "lives", SVC, {"seller_id": SELLER_ID, "title": "COMP_RACE_C live", "status": "ended", "is_active": False}))
    li = rest("POST", "live_items", SVC, {
        "live_id": live["id"], "product_id": p["id"], "title": "COMP_RACE_C li", "price": 7,
        "ref_code": f"CRC-LI-{uuid.uuid4().hex[:6]}", "item_kind": "marketplace_product",
        "status": "available", "is_active": False,
    })
    out["live_item"] = {"http": li["http"], "row": row(li), "raw": li["raw"][:400]}
    lirow = row(li)
    if lirow:
        acc = rest("POST", "live_reservation_requests", BUYER, {
            "live_id": live["id"], "live_item_id": lirow["id"], "buyer_id": BUYER_ID, "seller_id": SELLER_ID,
            "requested_qty": 9, "status": "accepted", "source": "fleaber_live",
        })
        out["buyer_insert_accepted"] = {"http": acc["http"], "row": row(acc), "raw": acc["raw"][:350]}
        r1 = row(rest("POST", "live_reservation_requests", BUYER, {
            "live_id": live["id"], "live_item_id": lirow["id"], "buyer_id": BUYER_ID, "seller_id": SELLER_ID,
            "requested_qty": 1, "status": "pending", "source": "fleaber_live",
        }))
        r2 = row(rest("POST", "live_reservation_requests", BUYER, {
            "live_id": live["id"], "live_item_id": lirow["id"], "buyer_id": BUYER_ID, "seller_id": SELLER_ID,
            "requested_qty": 1, "status": "pending", "source": "fleaber_live",
        }))
        if r1 and r2:
            rest("PATCH", "live_reservation_requests", SELLER, {"status": "accepted"}, qs=f"id=eq.{r1['id']}")
            rest("PATCH", "live_reservation_requests", SELLER, {"status": "accepted"}, qs=f"id=eq.{r2['id']}")
            out["double_accept"] = {
                "a1": row(rest("GET", "live_reservation_requests", SVC, qs=f"id=eq.{r1['id']}&select=id,status,requested_qty")),
                "a2": row(rest("GET", "live_reservation_requests", SVC, qs=f"id=eq.{r2['id']}&select=id,status,requested_qty")),
            }
            o1 = row(rest("POST", "orders", BUYER, {
                "buyer_id": BUYER_ID, "seller_id": SELLER_ID, "product_id": p["id"], "quantity": 1, "price_total": 7,
                "payment_method": "Pagamento na app (Seguro Fleaber)", "live_item_id": lirow["id"], "live_id": live["id"],
            }))
            o2 = row(rest("POST", "orders", BUYER, {
                "buyer_id": BUYER_ID, "seller_id": SELLER_ID, "product_id": p["id"], "quantity": 1, "price_total": 7,
                "payment_method": "Pagamento na app (Seguro Fleaber)", "live_item_id": lirow["id"], "live_id": live["id"],
            }))
            def ck(oid, rid):
                return req("POST", f"{URL}/functions/v1/create-payment-intent", BUYER, {
                    "buyer_id": BUYER_ID, "order_id": oid, "product_id": p["id"], "seller_id": SELLER_ID,
                    "shipping_method": "hand", "reservation_request_id": rid, "live_item_id": lirow["id"], "live_id": live["id"],
                })
            c1, c2 = ck(o1["id"], r1["id"]), ck(o2["id"], r2["id"])
            def sid(c):
                b = c.get("body") if isinstance(c.get("body"), dict) else {}
                return b.get("checkoutSessionId") or b.get("sessionId")
            out["checkout_after_double_accept"] = {
                "c1": {"http": c1["http"], "sid": sid(c1), "err": (c1.get("body") or {}).get("error") if isinstance(c1.get("body"), dict) else c1["raw"][:200]},
                "c2": {"http": c2["http"], "sid": sid(c2), "err": (c2.get("body") or {}).get("error") if isinstance(c2.get("body"), dict) else c2["raw"][:200]},
            }
        conv = rpc("batata_live_reservation_stripe_convert", BUYER, {"p_request_id": r1["id"] if r1 else None, "p_order_id": o1["id"] if r1 else None})
        out["jwt_convert"] = conv
        pend = row(acc)
        if pend:
            up = rest("PATCH", "live_reservation_requests", BUYER, {"status": "accepted"}, qs=f"id=eq.{pend['id']}")
            out["buyer_patch"] = {"http": up["http"], "after": row(rest("GET", "live_reservation_requests", SVC, qs=f"id=eq.{pend['id']}&select=id,status"))}
        rest("PATCH", "lives", SVC, {"status": "ended", "is_active": False}, qs=f"id=eq.{live['id']}")

    # dispute after concluido, before release
    setup = req("POST", f"{URL}/functions/v1/sec-fase2-e2e-oversell", SVC, {
        "probe": "setup_paid_order", "buyer_id": BUYER_ID, "seller_id": SELLER_ID, "initial_qty": 1,
    })
    # add e2e headers
    headers_extra = Request  # placeholder
    oid = (setup.get("body") or {}).get("order_id") if isinstance(setup.get("body"), dict) else None
    if not oid:
        r = Request(f"{URL}/functions/v1/sec-fase2-e2e-oversell", data=json.dumps({
            "probe": "setup_paid_order", "buyer_id": BUYER_ID, "seller_id": SELLER_ID, "initial_qty": 1,
        }).encode(), method="POST")
        r.add_header("Authorization", f"Bearer {SVC}")
        r.add_header("apikey", SVC)
        r.add_header("Content-Type", "application/json")
        if E2E:
            r.add_header("x-fleaber-e2e-secret", E2E)
        with urlopen(r, timeout=90) as resp:
            body = json.loads(resp.read().decode())
        oid = body.get("order_id")
        out["setup2"] = {"oid": oid, "ok": body.get("ok")}
    else:
        out["setup2"] = {"oid": oid, "http": setup["http"]}
    if oid:
        rest("PATCH", "orders", SELLER, {"status": "enviado"}, qs=f"id=eq.{oid}")
        rest("PATCH", "orders", BUYER, {"status": "concluido"}, qs=f"id=eq.{oid}")
        d = rest("POST", "order_disputes", BUYER, {
            "order_id": oid, "buyer_id": BUYER_ID, "reason": "danificado", "description": "COMP_RACE_C dispute",
        })
        drow = row(d)
        out["dispute"] = {"http": d["http"], "row": drow, "raw": d["raw"][:300]}
        if drow:
            rest("PATCH", "order_disputes", SELLER, {
                "seller_offer_type": "partial_refund", "seller_refund_percent": 40, "current_turn": "comprador",
            }, qs=f"id=eq.{drow['id']}")
            tadmin = rest("PATCH", "order_disputes", BUYER, {"current_turn": "administracao"}, qs=f"id=eq.{drow['id']}")
            after = row(rest("GET", "order_disputes", SVC, qs=f"id=eq.{drow['id']}&select=id,status,current_turn"))
            out["turn_admin"] = {"http": tadmin["http"], "after": after}

            def close():
                return rest("PATCH", "order_disputes", BUYER, {"status": "resolvida", "buyer_decision": "accepted"}, qs=f"id=eq.{drow['id']}")
            def partial():
                return rpc("batata_process_partial_refund_dispute", BUYER, {"p_order_id": oid})
            def release():
                return rpc("batata_release_seller_wallet_for_order", BUYER, {"p_order_id": oid})
            with ThreadPoolExecutor(3) as ex:
                a, b, c = ex.submit(close), ex.submit(partial), ex.submit(release)
                out["triple"] = {"close": a.result(), "partial": b.result(), "release": c.result()}
            oafter = row(rest("GET", "orders", SVC, qs=f"id=eq.{oid}&select=id,status,amount_paid_cents,wallet_release_processed_at,wallet_refund_processed_at"))
            txs = rest("GET", "wallet_transactions", SVC, qs=f"order_id=eq.{oid}&select=amount,type,wallet_id")["body"] or []
            net = 0.0
            for t in txs:
                typ = str(t.get("type") or "").lower()
                amt = float(t.get("amount") or 0)
                if typ in ("venda", "reembolso"):
                    net += amt
                elif typ == "estorno":
                    net -= amt
            out["after_triple"] = {"order": oafter, "net": round(net, 2), "cap_cents": (oafter or {}).get("amount_paid_cents"), "txs": txs}

    path = ROOT / "tool/reports/COMP_RACE_20260827_EVIDENCE_C.json"
    if path.exists():
        path = ROOT / f"tool/reports/COMP_RACE_20260827_EVIDENCE_C_{int(time.time())}.json"
    path.write_text(json.dumps(out, indent=2, default=str), encoding="utf-8")
    print("WROTE", path)


if __name__ == "__main__":
    main()
