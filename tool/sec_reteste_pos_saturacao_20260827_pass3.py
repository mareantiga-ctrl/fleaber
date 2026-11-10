#!/usr/bin/env python3
"""Pass 3: bag order_id, live_items kind, disputes, buyer self-complete, chat, credit wallet."""
from __future__ import annotations

import json
import ssl
import time
import uuid
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
ENV = {}
for line in (ROOT / "tool" / "live_ops_staging.env").read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, v = line.split("=", 1)
        ENV[k.strip()] = v.strip()
BASE = "https://fxdknzrqjenzqcvnwqqq.supabase.co"
ANON, SVC = ENV["SUPABASE_ANON_KEY"], ENV["SUPABASE_SERVICE_ROLE_KEY"]
BUYER_ID, SELLER_ID = ENV["LIVE_OPS_TEST_BUYER_ID"], ENV["LIVE_OPS_TEST_SELLER_ID"]
CTX = ssl.create_default_context()
TAG = f"RETSAT3-{int(time.time())}"
OUT = {"tag": TAG}
CREATED = {"products": [], "orders": [], "lives": [], "reservations": [], "disputes": [], "reviews": []}


def snip(o, n=300):
    return json.dumps(o, default=str, ensure_ascii=False)[:n]


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
        with urlopen(req, timeout=60, context=CTX) as r:
            raw = r.read()
            return r.status, json.loads(raw.decode() or "null")
    except HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw.decode() or "null")
        except Exception:
            return e.code, raw.decode("utf-8", "replace")[:800]
    except URLError as e:
        return 0, {"error": str(e.reason)}


def rest(method, path, token, body=None, qs=""):
    return http(method, f"{BASE}/rest/v1/{path}{qs}", token, body, {"Prefer": "return=representation"})


def rpc(name, token, args=None):
    return http("POST", f"{BASE}/rest/v1/rpc/{name}", token, args or {})


def edge(name, token, body=None):
    return http("POST", f"{BASE}/functions/v1/{name}", token, body)


def login(email, pw):
    st, p = http("POST", f"{BASE}/auth/v1/token?grant_type=password", ANON, {"email": email, "password": pw})
    return p["access_token"]


def row(p):
    if isinstance(p, list) and p and isinstance(p[0], dict):
        return p[0]
    return p if isinstance(p, dict) else {}


def track(kind, p):
    r = row(p)
    if r.get("id"):
        CREATED.setdefault(kind, []).append(str(r["id"]))
    return r


def amounts(p):
    if not isinstance(p, dict):
        return {"raw": snip(p)}
    url = p.get("checkoutUrl") or p.get("url") or ""
    sid = None
    if isinstance(url, str) and "cs_test_" in url:
        sid = "cs_test_" + url.split("cs_test_")[1].split("#")[0].split("/")[0]
    return {"server_amount_cents": p.get("server_amount_cents"), "amount_total": p.get("amount_total"), "session_id": sid, "error": p.get("error"), "url": url[:160] if url else None}


def product(seller, price, qty, title):
    st, p = rest("POST", "products", seller, {
        "seller_id": SELLER_ID, "title": title, "price": price, "quantity": qty,
        "list_on_marketplace": False, "available_for_live": True, "state": "Bom",
        "category": "Outros", "description": TAG,
    })
    r = track("products", p)
    print("product", st, r.get("id"), flush=True)
    return r.get("id")


def order(token, extra):
    body = {
        "buyer_id": BUYER_ID, "seller_id": SELLER_ID, "price_total": 40,
        "shipping_method": "Envio Transportadora (€3.50)", "payment_method": "Pagamento na App",
        "status": "reserva_pendente", "quantity": 1, **extra,
    }
    st, p = rest("POST", "orders", token, body)
    r = track("orders", p) if st in (200, 201) else {**row(p), "_err": p}
    return st, r


def main():
    buyer = login(ENV["LIVE_OPS_TEST_BUYER_EMAIL"], ENV["LIVE_OPS_TEST_BUYER_PASSWORD"])
    seller = login(ENV["LIVE_OPS_TEST_SELLER_EMAIL"], ENV["LIVE_OPS_TEST_SELLER_PASSWORD"])
    pid = product(seller, 40, 5, f"{TAG} 40x5")
    pidb = product(seller, 25, 3, f"{TAG} 25x3")

    # bag with order_id required by Edge
    st, a = order(buyer, {"product_id": pid, "contract_unit_cents": 100, "price_total": 1})
    st, b = order(buyer, {"product_id": pidb, "contract_unit_cents": 100, "price_total": 1})
    OUT["bag_orders"] = {"a": {"id": a.get("id"), "c": a.get("contract_unit_cents")}, "b": {"id": b.get("id"), "c": b.get("contract_unit_cents")}}
    if a.get("id") and b.get("id"):
        stc, pc = edge("create-payment-intent", buyer, {
            "order_id": a["id"], "buyer_id": BUYER_ID, "bag_checkout": True,
            "bag_lines": [{"order_id": a["id"]}, {"order_id": b["id"]}],
            "shipping_method": "carrier", "amount": 50,
        })
        OUT["bag_checkout"] = {"st": stc, **amounts(pc), "snip": snip(pc, 250)}

    # buyer self-complete off-platform isolated
    st, o = order(buyer, {"product_id": pid, "payment_method": "mb way", "price_total": 40})
    oid = o.get("id")
    seq = []
    if oid:
        before = row(rest("GET", "orders", buyer, qs=f"?id=eq.{oid}&select=id,status,amount_paid_cents,stock_units_applied")[1])
        for want in ["entregue", "concluido"]:
            st2, p2 = rest("PATCH", "orders", buyer, {"status": want}, qs=f"?id=eq.{oid}")
            after = row(p2) or row(rest("GET", "orders", buyer, qs=f"?id=eq.{oid}&select=id,status,amount_paid_cents,completed_at")[1])
            seq.append({"want": want, "st": st2, "after": after.get("status"), "paid": after.get("amount_paid_cents"), "completed_at": after.get("completed_at")})
        stock = row(rest("GET", "products", seller, qs=f"?id=eq.{pid}&select=id,quantity")[1])
        st3, p3 = rest("POST", "reviews", buyer, {"stars": 1, "comment": f"{TAG} fake complete", "order_id": oid, "is_automatic": True})
        rv = track("reviews", p3)
        OUT["buyer_self_complete_offplat"] = {
            "oid": oid, "before": before.get("status"), "seq": seq, "stock": stock.get("quantity"),
            "review": {"st": st3, "id": rv.get("id"), "stars": rv.get("stars"), "auto": rv.get("is_automatic"), "err": snip(p3, 180) if not rv.get("id") else None},
        }
        # cleanup cancel if still unpaid
        rest("PATCH", "orders", SVC, {"status": "cancelado"}, qs=f"?id={oid}" if False else f"?id=eq.{oid}")

    # platform empty method seller pago isolated
    st, o = order(buyer, {"product_id": pid, "payment_method": "", "price_total": 40})
    if o.get("id"):
        st2, p2 = rest("PATCH", "orders", seller, {"status": "pago"}, qs=f"?id=eq.{o['id']}")
        after = row(p2) or row(rest("GET", "orders", seller, qs=f"?id=eq.{o['id']}&select=id,status")[1])
        OUT["empty_pm_seller_pago"] = {"st": st2, "after": after.get("status"), "stored_pm": o.get("payment_method")}

    # disputes: GET existing resolvida + insert with reason
    st, p = rest("GET", "order_disputes", seller, qs="?status=eq.resolvida&select=id,order_id,status,seller_refund_percent,seller_offer_type,buyer_decision&limit=5")
    OUT["existing_resolved"] = {"st": st, "n": len(p) if isinstance(p, list) else 0, "sample": snip(p, 400)}
    target = None
    if isinstance(p, list) and p:
        target = p[0]
    if target and target.get("id"):
        before_pct = target.get("seller_refund_percent")
        st2, p2 = rest("PATCH", "order_disputes", seller, {"seller_refund_percent": 10}, qs=f"?id=eq.{target['id']}")
        after = row(p2) or row(rest("GET", "order_disputes", seller, qs=f"?id=eq.{target['id']}&select=*")[1])
        OUT["patch_existing_resolved"] = {
            "id": target["id"], "before": before_pct, "st": st2,
            "after_pct": after.get("seller_refund_percent"), "after_status": after.get("status"),
        }
        # restore if mutated
        if after.get("seller_refund_percent") != before_pct:
            rest("PATCH", "order_disputes", SVC, {"seller_refund_percent": before_pct}, qs=f"?id=eq.{target['id']}")

    st, o = order(buyer, {"product_id": pid, "payment_method": "Pagamento direto ao vendedor (MB WAY/Transf)", "price_total": 40})
    if o.get("id"):
        rest("PATCH", "orders", seller, {"status": "pago"}, qs=f"?id=eq.{o['id']}")
        rest("PATCH", "orders", seller, {"status": "enviado"}, qs=f"?id=eq.{o['id']}")
        rest("PATCH", "orders", buyer, {"status": "concluido"}, qs=f"?id=eq.{o['id']}")
        st, p = rest("POST", "order_disputes", buyer, {"order_id": o["id"], "buyer_id": BUYER_ID, "reason": "outro", "description": TAG})
        d = track("disputes", p)
        OUT["open_dispute"] = {"st": st, "id": d.get("id"), "status": d.get("status"), "err": snip(p, 220) if not d.get("id") else None}
        if d.get("id"):
            st2, p2 = rest("PATCH", "order_disputes", seller, {"seller_refund_percent": 50, "seller_offer_type": "partial"}, qs=f"?id=eq.{d['id']}")
            after = row(p2) or row(rest("GET", "order_disputes", seller, qs=f"?id=eq.{d['id']}&select=*")[1])
            OUT["open_seller_offer"] = {"st": st2, "pct": after.get("seller_refund_percent"), "type": after.get("seller_offer_type"), "status": after.get("status")}
        # resolved fixture with reason
        st, p = rest("POST", "order_disputes", SVC, {
            "order_id": o["id"], "buyer_id": BUYER_ID, "reason": "outro", "description": TAG,
            "status": "resolvida", "seller_refund_percent": 100, "seller_offer_type": "full_refund",
        })
        d2 = track("disputes", p)
        OUT["svc_resolved"] = {"st": st, "id": d2.get("id"), "pct": d2.get("seller_refund_percent"), "status": d2.get("status"), "err": snip(p, 200) if not d2.get("id") else None}
        if d2.get("id"):
            st2, p2 = rest("PATCH", "order_disputes", seller, {"seller_refund_percent": 10, "status": "aberta"}, qs=f"?id=eq.{d2['id']}")
            after = row(p2) or row(rest("GET", "order_disputes", seller, qs=f"?id=eq.{d2['id']}&select=*")[1])
            OUT["patch_svc_resolved"] = {"st": st2, "pct": after.get("seller_refund_percent"), "status": after.get("status")}
            rest("PATCH", "order_disputes", SVC, {"seller_refund_percent": 100, "status": "resolvida"}, qs=f"?id=eq.{d2['id']}")

    # live items marketplace_product
    st, p = rest("POST", "lives", SVC, {"seller_id": SELLER_ID, "vendedor_id": SELLER_ID, "title": TAG, "status": "ended", "is_active": False})
    live = track("lives", p)
    OUT["live"] = {"st": st, "id": live.get("id"), "err": snip(p, 160)}
    lid = live.get("id")
    if lid:
        st, p = rest("POST", "live_items", SVC, {
            "live_id": lid, "ref_code": f"M{int(time.time())%9999}", "title": TAG,
            "price": 40, "product_id": pid, "item_kind": "marketplace_product", "is_active": True,
        })
        item = row(p)
        OUT["live_item"] = {"st": st, "id": item.get("id"), "err": snip(p, 200) if not item.get("id") else None}
        iid = item.get("id")
        if not iid:
            st, p = rest("POST", "live_items", SVC, {
                "live_id": lid, "ref_code": f"B{int(time.time())%9999}", "title": TAG,
                "price": 40, "item_kind": "live_only", "quantity": 2, "is_active": True,
            })
            item = row(p)
            OUT["live_item_only"] = {"st": st, "id": item.get("id"), "err": snip(p, 200) if not item.get("id") else None}
            iid = item.get("id")
            pid_for_order = None
        else:
            pid_for_order = pid
        if iid:
            st, r1 = rest("POST", "live_reservation_requests", buyer, {
                "live_id": lid, "live_item_id": iid, "seller_id": SELLER_ID, "buyer_id": BUYER_ID,
                "requested_qty": 99, "source": "fleaber_live", "status": "accepted",
            })
            r1r = track("reservations", r1) if st in (200, 201) else row(r1)
            OUT["res_accepted99"] = {"st": st, "status": r1r.get("status"), "qty": r1r.get("requested_qty"), "qpos": r1r.get("queue_position"), "id": r1r.get("id"), "err": snip(r1, 180) if st not in (200, 201) else None}
            st, r2 = rest("POST", "live_reservation_requests", buyer, {
                "live_id": lid, "live_item_id": iid, "seller_id": SELLER_ID, "buyer_id": BUYER_ID,
                "requested_qty": 1, "source": "fleaber_live", "status": "pending", "queue_position": 1,
            })
            r2r = track("reservations", r2) if st in (200, 201) else row(r2)
            OUT["res_pending"] = {"st": st, "status": r2r.get("status"), "qty": r2r.get("requested_qty"), "qpos": r2r.get("queue_position"), "id": r2r.get("id"), "err": snip(r2, 180) if st not in (200, 201) else None}
            rid = r2r.get("id") or r1r.get("id")
            if rid:
                st2, p2 = rest("PATCH", "live_reservation_requests", buyer, {"status": "accepted", "requested_qty": 50, "queue_position": 1}, qs=f"?id=eq.{rid}")
                after = row(rest("GET", "live_reservation_requests", buyer, qs=f"?id=eq.{rid}&select=*")[1])
                OUT["res_buyer_patch"] = {"st": st2, "status": after.get("status"), "qty": after.get("requested_qty"), "qpos": after.get("queue_position")}
                st3, p3 = rpc("batata_process_live_reservation_request", buyer, {"p_request_id": rid, "p_action": "accept"})
                OUT["res_buyer_rpc"] = {"st": st3, "body": snip(p3, 180)}
                st4, p4 = rpc("batata_process_live_reservation_request", seller, {"p_request_id": rid, "p_action": "accept"})
                OUT["res_seller_rpc"] = {"st": st4, "body": snip(p4, 220)}
                after = row(rest("GET", "live_reservation_requests", seller, qs=f"?id=eq.{rid}&select=*")[1])
                OUT["res_after_seller"] = {"status": after.get("status"), "qty": after.get("requested_qty")}
                if pid_for_order:
                    st5, o5 = order(buyer, {"product_id": pid_for_order, "live_item_id": iid, "live_id": lid, "quantity": 8, "price_total": 40})
                    OUT["order_gt_res"] = {"st": st5, "q": o5.get("quantity"), "err": snip(o5.get("_err"), 160)}
                    st6, o6 = order(buyer, {"product_id": pid_for_order, "live_item_id": iid, "live_id": lid, "quantity": 1, "price_total": 40})
                    OUT["order_ok"] = {"st": st6, "q": o6.get("quantity"), "cq": o6.get("contract_qty"), "c": o6.get("contract_unit_cents"), "oid": o6.get("id")}
                    if o6.get("id"):
                        stc, pc = edge("create-payment-intent", buyer, {"order_id": o6["id"], "buyer_id": BUYER_ID, "shipping_method": "hand"})
                        OUT["order_ok_checkout"] = amounts(pc)
                st7, p7 = rpc("batata_live_bag_update_qty", buyer, {"p_request_id": rid, "p_qty": 50})
                OUT["bag_update_qty"] = {"st": st7, "body": snip(p7, 200)}
            for q in (0, -1, 100, 9999):
                st, rq = rest("POST", "live_reservation_requests", buyer, {
                    "live_id": lid, "live_item_id": iid, "seller_id": SELLER_ID, "buyer_id": BUYER_ID,
                    "requested_qty": q, "source": "fleaber_live",
                })
                OUT[f"res_qty_{q}"] = {"st": st, "body": snip(rq, 120)}

    # chat
    st, p = rest("POST", "chats", buyer, {"user_a": BUYER_ID, "user_b": SELLER_ID, "product_id": pid})
    ch = row(p)
    OUT["chat"] = {"st": st, "id": ch.get("id"), "a": ch.get("user_a"), "b": ch.get("user_b"), "err": snip(p, 180) if not ch.get("id") else None}
    if ch.get("id"):
        st2, p2 = rest("PATCH", "chats", buyer, {"user_b": BUYER_ID}, qs=f"?id=eq.{ch['id']}")
        after = row(p2) or row(rest("GET", "chats", buyer, qs=f"?id=eq.{ch['id']}&select=*")[1])
        OUT["chat_swap"] = {"st": st2, "b": after.get("user_b")}
        # messages table probe
        st3, p3 = rest("POST", "messages", buyer, {"chat_id": ch["id"], "sender_id": SELLER_ID, "content": TAG})
        OUT["msg_spoof"] = {"st": st3, "body": snip(p3, 180)}
        st4, p4 = rest("POST", "chat_messages", buyer, {"chat_id": ch["id"], "sender_id": SELLER_ID, "content": TAG})
        OUT["chat_messages_spoof"] = {"st": st4, "body": snip(p4, 180)}

    # credit wallet correct arity
    dummy = str(uuid.uuid4())
    st, p = rpc("batata_credit_wallet_once", buyer, {
        "p_wallet_id": SELLER_ID, "p_order_id": dummy, "p_amount": 500, "p_type": "venda", "p_description": TAG,
    })
    OUT["credit_wallet"] = {"st": st, "body": snip(p, 200)}
    st, p = rpc("batata_credit_wallet_once", ANON, {
        "p_wallet_id": SELLER_ID, "p_order_id": dummy, "p_amount": 500, "p_type": "venda", "p_description": TAG,
    })
    OUT["credit_wallet_anon"] = {"st": st, "body": snip(p, 200)}

    # extra lab-ish names from repo
    extra = [
        "batata_staging_h_v1_ux_demo_seed",
        "sec_fase2_e2e_oversell",
        "batata_lab_seed_fm",
        "batata_repair_stock",
        "batata_debug_wallet",
        "batata_reset_live_queue",
    ]
    extra_res = []
    for name in extra:
        for role, tok in [("anon", ANON), ("buyer", buyer)]:
            st, p = rpc(name, tok, {})
            extra_res.append({"name": name, "role": role, "st": st, "body": snip(p, 100)})
    OUT["extra_rpc"] = extra_res

    # cleanup
    for x in CREATED.get("products") or []:
        rest("PATCH", "products", seller, {"quantity": 0, "list_on_marketplace": False}, qs=f"?id=eq.{x}")
    for x in CREATED.get("lives") or []:
        rest("PATCH", "lives", SVC, {"status": "ended", "is_active": False}, qs=f"?id=eq.{x}")
    for x in CREATED.get("orders") or []:
        rest("PATCH", "orders", SVC, {"status": "cancelado"}, qs=f"?id=eq.{x}")
    for x in CREATED.get("reservations") or []:
        rest("PATCH", "live_reservation_requests", SVC, {"status": "rejected"}, qs=f"?id=eq.{x}")
    rest("PATCH", "profiles", SVC, {"user_type": "comprador"}, qs=f"?id=eq.{BUYER_ID}")

    OUT["created"] = CREATED
    path = ROOT / "tool" / "reports" / "RETESTE_POS_SATURACAO_2026-08-27_PASS3.json"
    path.write_text(json.dumps(OUT, indent=2, default=str), encoding="utf-8")
    print("WROTE", path, flush=True)


if __name__ == "__main__":
    main()
