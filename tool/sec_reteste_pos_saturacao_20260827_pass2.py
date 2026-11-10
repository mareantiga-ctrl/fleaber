#!/usr/bin/env python3
"""Pass 2: gaps from pass 1 (price_total, live svc fixture, JWT lab, bag, disputes, offers)."""
from __future__ import annotations

import json
import ssl
import time
import uuid
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
ENV: dict[str, str] = {}
for line in (ROOT / "tool" / "live_ops_staging.env").read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, v = line.split("=", 1)
        ENV[k.strip()] = v.strip()
STAGING = "fxdknzrqjenzqcvnwqqq"
BASE = f"https://{STAGING}.supabase.co"
ANON, SVC = ENV["SUPABASE_ANON_KEY"], ENV["SUPABASE_SERVICE_ROLE_KEY"]
BUYER_ID, SELLER_ID = ENV["LIVE_OPS_TEST_BUYER_ID"], ENV["LIVE_OPS_TEST_SELLER_ID"]
CTX = ssl.create_default_context()
TAG = f"RETSAT2-{int(time.time())}"
OUT: dict[str, Any] = {"tag": TAG, "staging": STAGING}
CREATED: dict[str, list[str]] = {"products": [], "orders": [], "lives": [], "reservations": [], "disputes": [], "reviews": [], "offers": []}


def snip(o: Any, n: int = 400) -> str:
    return json.dumps(o, default=str, ensure_ascii=False)[:n]


def http(method: str, url: str, token: str, body: Any = None, extra: dict | None = None) -> tuple[int, Any]:
    headers = {"Accept": "application/json", "apikey": ANON, "Authorization": f"Bearer {token}"}
    if token == SVC:
        headers["apikey"] = SVC
    if extra:
        headers.update(extra)
    data = None
    if body is not None:
        data = json.dumps(body).encode() if not isinstance(body, (bytes, bytearray)) else body
        headers.setdefault("Content-Type", "application/json")
    req = Request(url, data=data, headers=headers, method=method)
    try:
        with urlopen(req, timeout=60, context=CTX) as r:
            raw = r.read()
            try:
                return r.status, json.loads(raw.decode() or "null")
            except Exception:
                return r.status, raw.decode("utf-8", "replace")[:2000]
    except HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw.decode() or "null")
        except Exception:
            return e.code, raw.decode("utf-8", "replace")[:2000]
    except URLError as e:
        return 0, {"error": str(e.reason)}


def rest(method: str, path: str, token: str, body: Any = None, qs: str = "") -> tuple[int, Any]:
    return http(method, f"{BASE}/rest/v1/{path}{qs}", token, body, {"Prefer": "return=representation"})


def rpc(name: str, token: str, args: dict | None = None) -> tuple[int, Any]:
    return http("POST", f"{BASE}/rest/v1/rpc/{name}", token, args or {})


def edge(name: str, token: str, body: Any = None, qs: str = "") -> tuple[int, Any]:
    return http("POST", f"{BASE}/functions/v1/{name}{qs}", token, body)


def login(email: str, pw: str) -> str:
    st, p = http("POST", f"{BASE}/auth/v1/token?grant_type=password", ANON, {"email": email, "password": pw})
    return p["access_token"]


def row(p: Any) -> dict:
    if isinstance(p, list) and p and isinstance(p[0], dict):
        return p[0]
    return p if isinstance(p, dict) else {}


def track(kind: str, p: Any) -> dict:
    r = row(p)
    if r.get("id"):
        CREATED.setdefault(kind, []).append(str(r["id"]))
    return r


def amounts(p: Any) -> dict:
    if not isinstance(p, dict):
        return {"raw": snip(p)}
    url = p.get("checkoutUrl") or p.get("url") or p.get("checkout_url")
    sid = None
    if isinstance(url, str) and "cs_test_" in url:
        sid = "cs_test_" + url.split("cs_test_")[1].split("#")[0].split("/")[0]
    return {
        "server_amount_cents": p.get("server_amount_cents"),
        "amount_total": p.get("amount_total"),
        "session_id": sid,
        "error": p.get("error"),
        "snip": snip(p, 350),
    }


def product(seller: str, price: float, qty: int, title: str) -> str | None:
    st, p = rest("POST", "products", seller, {
        "seller_id": SELLER_ID, "title": title, "price": price, "quantity": qty,
        "list_on_marketplace": False, "available_for_live": True, "state": "Bom",
        "category": "Outros", "description": TAG,
    })
    r = track("products", p)
    print(f"  product {title} st={st} id={r.get('id')}", flush=True)
    return r.get("id")


def order(token: str, extra: dict) -> tuple[int, dict]:
    body = {
        "buyer_id": BUYER_ID, "seller_id": SELLER_ID,
        "price_total": extra.get("price_total", 40),
        "shipping_method": "Envio Transportadora (€3.50)",
        "payment_method": "Pagamento na App",
        "status": "reserva_pendente", "quantity": 1, **extra,
    }
    st, p = rest("POST", "orders", token, body)
    r = track("orders", p) if st in (200, 201) else row(p)
    if st not in (200, 201):
        r = {**r, "_err": p}
    return st, r


def checkout(token: str, oid: str, extra: dict | None = None) -> tuple[int, dict]:
    body = {"order_id": oid, "buyer_id": BUYER_ID, "shipping_method": "hand", **(extra or {})}
    st, p = edge("create-payment-intent", token, body)
    return st, p


def main() -> None:
    buyer = login(ENV["LIVE_OPS_TEST_BUYER_EMAIL"], ENV["LIVE_OPS_TEST_BUYER_PASSWORD"])
    seller = login(ENV["LIVE_OPS_TEST_SELLER_EMAIL"], ENV["LIVE_OPS_TEST_SELLER_PASSWORD"])
    pid = product(seller, 40.0, 8, f"{TAG} 40x8")
    assert pid

    # --- OpenAPI with JWT ---
    st, spec = http("GET", f"{BASE}/rest/v1/", buyer, extra={"Accept": "application/openapi+json"})
    names = []
    if isinstance(spec, dict):
        for pth in (spec.get("paths") or {}):
            if "/rpc/" in str(pth):
                names.append(str(pth).split("/rpc/")[-1].split("{")[0].strip("/"))
    needles = ("lab", "staging", "test", "nuke", "seed", "clear", "reset", "repair", "debug", "e2e", "feedback", "demo")
    labish = sorted({n for n in names if any(x in n.lower() for x in needles)})
    OUT["openapi"] = {"st": st, "rpc_count": len(names), "labish": labish}

    # --- Lab RPCs JWT+anon correct signatures ---
    lab_calls = [
        ("batata_lab_clear_all_fm_pending", {}),
        ("batata_lab_clear_fm_pending", {"p_live_id": str(uuid.uuid4())}),
        ("batata_generate_auto_feedback", {}),
        ("batata_generate_auto_feedback", {"p_now": "2099-01-01T00:00:00Z"}),
        ("batata_staging_h_v1_ux_demo_seed", {}),
        ("batata_staging_set_fleahub_test_state", {"p_seller_id": SELLER_ID}),
        ("staging_nuke_user_data", {"p_user_id": BUYER_ID}),
        ("staging_restore_stock_before_nuke", {"p_user_id": BUYER_ID}),
        ("batata_expire_product_offers", {}),
        ("batata_draw_live_raffle_winners", {"p_raffle_id": str(uuid.uuid4())}),
    ]
    for n in labish:
        lab_calls.append((n, {}))
    lab_res = []
    executable = []
    for name, args in lab_calls:
        for role, tok in [("anon", ANON), ("buyer", buyer), ("seller", seller)]:
            st, p = rpc(name, tok, args)
            rec = {"name": name, "role": role, "st": st, "args": args, "body": snip(p, 160)}
            lab_res.append(rec)
            if st == 200:
                executable.append(rec)
    OUT["lab"] = {"results": lab_res, "executable": executable}

    # --- Legitimate offer ---
    st, p = rest("POST", "product_offers", buyer, {
        "product_id": pid, "buyer_id": BUYER_ID, "seller_id": SELLER_ID,
        "amount": 12.00, "status": "pending", "offered_by": "buyer",
    })
    off = track("offers", p)
    OUT["offer_pending"] = {"st": st, "id": off.get("id"), "status": off.get("status"), "body": snip(p, 220)}
    if off.get("id"):
        st2, p2 = rest("PATCH", "product_offers", buyer, {"status": "accepted"}, qs=f"?id=eq.{off['id']}")
        after = row(p2) or row(rest("GET", "product_offers", buyer, qs=f"?id=eq.{off['id']}&select=*")[1])
        OUT["offer_buyer_self_accept"] = {"st": st2, "status": after.get("status"), "body": snip(p2, 200)}
        st3, p3 = rest("PATCH", "product_offers", seller, {"status": "accepted"}, qs=f"?id=eq.{off['id']}")
        after3 = row(p3) or row(rest("GET", "product_offers", seller, qs=f"?id=eq.{off['id']}&select=*")[1])
        OUT["offer_seller_accept"] = {"st": st3, "status": after3.get("status"), "amount": after3.get("amount"), "responded_at": after3.get("responded_at")}
        if str(after3.get("status") or "").lower() == "accepted":
            st4, o4 = order(buyer, {"product_id": pid, "product_offer_id": off["id"], "price_total": 99})
            stc, pc = checkout(buyer, o4["id"]) if o4.get("id") else (0, {})
            OUT["order_legit_offer"] = {"st": st4, "contract": o4.get("contract_unit_cents"), "offer_id": o4.get("product_offer_id"), "oid": o4.get("id"), "checkout": amounts(pc)}
            # rejected other product spoof already done; try pending leftover
        # expired: svc
        rest("PATCH", "product_offers", SVC, {"expires_at": "2020-01-01T00:00:00Z", "status": "accepted", "responded_at": "2020-01-01T00:00:00Z"}, qs=f"?id=eq.{off['id']}")
        # new product order with expired id
        st5, o5 = order(buyer, {"product_id": pid, "product_offer_id": off["id"], "price_total": 12})
        stc, pc = checkout(buyer, o5["id"]) if o5.get("id") else (0, {})
        OUT["order_after_expire_offer"] = {"st": st5, "contract": o5.get("contract_unit_cents"), "offer_id": o5.get("product_offer_id"), "checkout": amounts(pc) if stc else {}}

    # --- qty freeze + bag ---
    pid2 = product(seller, 25.0, 5, f"{TAG} 25x5")
    st, o = order(buyer, {"product_id": pid, "quantity": 1, "price_total": 40})
    if o.get("id"):
        st2, p2 = rest("PATCH", "orders", buyer, {"quantity": 5, "contract_qty": 5, "contract_unit_cents": 50}, qs=f"?id=eq.{o['id']}")
        after = row(p2) or row(rest("GET", "orders", buyer, qs=f"?id=eq.{o['id']}&select=id,quantity,contract_qty,contract_unit_cents")[1])
        OUT["qty_update_buyer"] = {"st": st2, "q": after.get("quantity"), "cq": after.get("contract_qty"), "c": after.get("contract_unit_cents")}
        st3, p3 = rest("PATCH", "orders", seller, {"quantity": 7, "contract_qty": 7}, qs=f"?id=eq.{o['id']}")
        afters = row(p3) or row(rest("GET", "orders", seller, qs=f"?id=eq.{o['id']}&select=id,quantity,contract_qty")[1])
        OUT["qty_update_seller"] = {"st": st3, "q": afters.get("quantity"), "cq": afters.get("contract_qty")}
    st_a, a = order(buyer, {"product_id": pid, "quantity": 1, "contract_unit_cents": 100, "price_total": 1})
    st_b, b = order(buyer, {"product_id": pid2, "quantity": 1, "contract_unit_cents": 100, "price_total": 1}) if pid2 else (0, {})
    OUT["bag_insert"] = {"a": {"st" : st_a, "c": a.get("contract_unit_cents"), "id": a.get("id")}, "b": {"st": st_b, "c": b.get("contract_unit_cents"), "id": b.get("id")}}
    if a.get("id") and b.get("id"):
        stc, pc = edge("create-payment-intent", buyer, {
            "bag_checkout": True, "bag_lines": [{"order_id": a["id"]}, {"order_id": b["id"]}],
            "shipping_method": "carrier", "amount": 50, "buyer_id": BUYER_ID,
        })
        OUT["bag_checkout"] = {"st": stc, **amounts(pc)}

    # --- payment machine ---
    pms = ["", " ", "pix", "mbwy", "MB WAY", "mb way",
           "Pagamento direto ao vendedor (MB WAY/Transf)", "Pagamento na App",
           "Seguro Fleaber", "plataforma", "transferencia", "pix mb way"]
    pm_out = []
    for pm in pms:
        st, r = order(buyer, {"product_id": pid, "payment_method": pm, "price_total": 40, "quantity": 1})
        rec = {"pm": pm, "st": st, "stored": r.get("payment_method"), "status": r.get("status"), "oid": r.get("id"), "err": snip(r.get("_err"), 120) if st not in (200, 201) else None}
        if r.get("id"):
            transitions = []
            for who, tok in [("buyer", buyer), ("seller", seller)]:
                for want in ["pago", "enviado", "entregue", "concluido", "cancelado"]:
                    st2, p2 = rest("PATCH", "orders", tok, {"status": want}, qs=f"?id=eq.{r['id']}")
                    after = row(p2) or row(rest("GET", "orders", tok, qs=f"?id=eq.{r['id']}&select=id,status,amount_paid_cents")[1])
                    transitions.append({"who": who, "want": want, "after": after.get("status"), "paid": after.get("amount_paid_cents")})
                    rest("PATCH", "orders", tok, {"status": "reserva_pendente"}, qs=f"?id=eq.{r['id']}")  # try revert; may freeze
            rec["transitions"] = transitions
        pm_out.append(rec)
    OUT["payment_methods"] = pm_out

    # dedicated off-platform
    st, r = order(buyer, {"product_id": pid, "payment_method": "Pagamento direto ao vendedor (MB WAY/Transf)", "price_total": 40, "quantity": 1})
    offplat = {"insert": {"st": st, "oid": r.get("id"), "status": r.get("status"), "pm": r.get("payment_method")}}
    if r.get("id"):
        stock0 = row(rest("GET", "products", seller, qs=f"?id=eq.{pid}&select=id,quantity")[1])
        st2, p2 = rest("PATCH", "orders", seller, {"status": "pago"}, qs=f"?id=eq.{r['id']}")
        after = row(p2) or row(rest("GET", "orders", seller, qs=f"?id=eq.{r['id']}&select=*")[1])
        stock1 = row(rest("GET", "products", seller, qs=f"?id=eq.{pid}&select=id,quantity")[1])
        stw, pw = rest("GET", "wallet_transactions", SVC, qs=f"?order_id=eq.{r['id']}&select=*")
        offplat["seller_pago"] = {
            "st": st2, "status": after.get("status"), "amount_paid": after.get("amount_paid_cents"),
            "stock_applied": after.get("stock_units_applied"), "release": after.get("wallet_release_processed_at"),
            "stock_before": stock0.get("quantity"), "stock_after": stock1.get("quantity"),
            "wallet_tx": snip(pw, 200),
        }
        st3, p3 = rest("PATCH", "orders", seller, {"status": "enviado"}, qs=f"?id=eq.{r['id']}")
        after3 = row(p3) or row(rest("GET", "orders", seller, qs=f"?id=eq.{r['id']}&select=id,status")[1])
        offplat["enviado"] = {"st": st3, "status": after3.get("status")}
        st4, p4 = rest("PATCH", "orders", buyer, {"status": "concluido"}, qs=f"?id=eq.{r['id']}")
        after4 = row(p4) or row(rest("GET", "orders", buyer, qs=f"?id=eq.{r['id']}&select=id,status,completed_at")[1])
        offplat["concluido"] = {"st": st4, "status": after4.get("status"), "completed_at": after4.get("completed_at")}
        st5, p5 = rest("PATCH", "orders", buyer, {"status": "cancelado"}, qs=f"?id=eq.{r['id']}")
        after5 = row(p5) or row(rest("GET", "orders", buyer, qs=f"?id=eq.{r['id']}&select=id,status")[1])
        offplat["cancel_after"] = {"st": st5, "status": after5.get("status")}
        # review
        st6, p6 = rest("POST", "reviews", buyer, {"stars": 4, "comment": f"{TAG} offplat", "order_id": r["id"], "is_automatic": True})
        rv = track("reviews", p6)
        offplat["review"] = {"st": st6, "id": rv.get("id"), "stars": rv.get("stars"), "auto": rv.get("is_automatic"), "err": snip(p6, 180) if not rv.get("id") else None}
        if rv.get("id"):
            st7, p7 = rest("PATCH", "reviews", buyer, {"stars": 1, "comment": "hack", "is_automatic": True}, qs=f"?id=eq.{rv['id']}")
            after7 = row(p7) or row(rest("GET", "reviews", buyer, qs=f"?id=eq.{rv['id']}&select=id,stars,comment,is_automatic")[1])
            offplat["review_patch"] = {"st": st7, "stars": after7.get("stars"), "comment": after7.get("comment"), "auto": after7.get("is_automatic")}
    OUT["offplat"] = offplat

    # platform unpaid → pago
    st, r = order(buyer, {"product_id": pid, "payment_method": "Pagamento na App", "price_total": 40})
    plat = {"oid": r.get("id")}
    if r.get("id"):
        seq = []
        for who, tok in [("buyer", buyer), ("seller", seller)]:
            for want in ["pago", "enviado", "entregue", "concluido"]:
                st2, p2 = rest("PATCH", "orders", tok, {"status": want}, qs=f"?id=eq.{r['id']}")
                after = row(p2) or row(rest("GET", "orders", tok, qs=f"?id=eq.{r['id']}&select=id,status,amount_paid_cents,wallet_release_processed_at")[1])
                seq.append({"who": who, "want": want, "after": after.get("status"), "paid": after.get("amount_paid_cents"), "rel": after.get("wallet_release_processed_at")})
        plat["seq"] = seq
        stc, pc = checkout(buyer, r["id"], {"amount": 50, "product_id": str(uuid.uuid4()), "quantity": 99})
        plat["underpay"] = amounts(pc)
        stg, pg = edge("create-payment-intent", buyer, {"order_id": r["id"], "payment_intent_id": "pi_x"}, "?fase2_e2e_settle=1")
        plat["settle_jwt"] = {"st": stg, "body": snip(pg, 180)}
        stf, pf = edge("refund-order", buyer, {"order_id": r["id"]})
        plat["refund_buyer"] = {"st": stf, "body": snip(pf, 180)}
        sts, ps = edge("refund-order", seller, {"order_id": r["id"]})
        plat["refund_seller"] = {"st": sts, "body": snip(ps, 180)}
    OUT["platform"] = plat

    # --- disputes ---
    st, r = order(buyer, {"product_id": pid, "payment_method": "Pagamento direto ao vendedor (MB WAY/Transf)", "price_total": 40})
    disp: dict[str, Any] = {}
    if r.get("id"):
        st, p = rest("POST", "order_disputes", SVC, {
            "order_id": r["id"], "buyer_id": BUYER_ID, "status": "resolvida",
            "seller_refund_percent": 100, "seller_offer_type": "full_refund",
        })
        d = track("disputes", p)
        disp["svc_resolved"] = {"st": st, "id": d.get("id"), "pct": d.get("seller_refund_percent"), "status": d.get("status"), "err": snip(p, 200) if not d.get("id") else None}
        if d.get("id"):
            st2, p2 = rest("PATCH", "order_disputes", seller, {"seller_refund_percent": 10, "seller_offer_type": "partial", "status": "aberta"}, qs=f"?id=eq.{d['id']}")
            after = row(p2) or row(rest("GET", "order_disputes", seller, qs=f"?id=eq.{d['id']}&select=*")[1])
            disp["seller_patch"] = {"st": st2, "pct": after.get("seller_refund_percent"), "status": after.get("status"), "type": after.get("seller_offer_type"), "body": snip(p2, 200)}
            st3, p3 = rest("PATCH", "order_disputes", buyer, {"seller_refund_percent": 1, "buyer_decision": "accept"}, qs=f"?id=eq.{d['id']}")
            afterb = row(p3) or row(rest("GET", "order_disputes", buyer, qs=f"?id=eq.{d['id']}&select=*")[1])
            disp["buyer_patch"] = {"st": st3, "pct": afterb.get("seller_refund_percent"), "status": afterb.get("status"), "decision": afterb.get("buyer_decision")}
        # open dispute
        st, r2 = order(buyer, {"product_id": pid, "payment_method": "Pagamento direto ao vendedor (MB WAY/Transf)", "price_total": 40})
        if r2.get("id"):
            rest("PATCH", "orders", seller, {"status": "pago"}, qs=f"?id=eq.{r2['id']}")
            rest("PATCH", "orders", seller, {"status": "enviado"}, qs=f"?id=eq.{r2['id']}")
            rest("PATCH", "orders", buyer, {"status": "concluido"}, qs=f"?id=eq.{r2['id']}")
            st, p = rest("POST", "order_disputes", buyer, {"order_id": r2["id"]})
            d2 = track("disputes", p)
            disp["open_insert"] = {"st": st, "id": d2.get("id"), "status": d2.get("status"), "body": snip(p, 200)}
            if d2.get("id"):
                st4, p4 = rest("PATCH", "order_disputes", seller, {"seller_refund_percent": 50}, qs=f"?id=eq.{d2['id']}")
                after4 = row(p4) or row(rest("GET", "order_disputes", seller, qs=f"?id=eq.{d2['id']}&select=*")[1])
                disp["open_offer"] = {"st": st4, "pct": after4.get("seller_refund_percent"), "status": after4.get("status")}
    OUT["disputes"] = disp

    # --- live via service_role fixture ---
    st, p = rest("POST", "lives", SVC, {
        "seller_id": SELLER_ID, "vendedor_id": SELLER_ID, "title": f"{TAG} live",
        "status": "ended", "is_active": False,
    })
    live = track("lives", p)
    OUT["live_svc"] = {"st": st, "id": live.get("id"), "err": snip(p, 180) if not live.get("id") else None}
    lid = live.get("id")
    live_out: dict[str, Any] = {}
    if lid:
        st, p = rest("POST", "live_items", SVC, {
            "live_id": lid, "ref_code": f"R{int(time.time())%9999}", "title": TAG,
            "price": 40, "product_id": pid, "is_active": True,
        })
        item = row(p)
        if item.get("id"):
            CREATED.setdefault("live_items", []).append(item["id"])
        iid = item.get("id")
        live_out["item"] = {"st": st, "id": iid, "err": snip(p, 180) if not iid else None}
        if iid:
            def res(token, extra):
                st, p = rest("POST", "live_reservation_requests", token, {
                    "live_id": lid, "live_item_id": iid, "seller_id": SELLER_ID, "buyer_id": BUYER_ID,
                    "requested_qty": 1, "source": "fleaber_live", **extra,
                })
                r = track("reservations", p) if st in (200, 201) else row(p)
                return st, r if st in (200, 201) else {**r, "_err": p}

            st, r1 = res(buyer, {"requested_qty": 99, "status": "accepted"})
            live_out["insert_accepted99"] = {"st": st, "status": r1.get("status"), "qty": r1.get("requested_qty"), "qpos": r1.get("queue_position"), "id": r1.get("id"), "err": snip(r1.get("_err"), 160)}
            st, r2 = res(buyer, {"requested_qty": 1, "status": "pending"})
            live_out["insert_pending"] = {"st": st, "status": r2.get("status"), "qty": r2.get("requested_qty"), "qpos": r2.get("queue_position"), "id": r2.get("id"), "err": snip(r2.get("_err"), 160)}
            if r2.get("id"):
                st2, p2 = rest("PATCH", "live_reservation_requests", buyer, {"status": "accepted", "requested_qty": 50, "queue_position": 1}, qs=f"?id=eq.{r2['id']}")
                after = row(rest("GET", "live_reservation_requests", buyer, qs=f"?id=eq.{r2['id']}&select=*")[1])
                live_out["buyer_patch"] = {"st": st2, "status": after.get("status"), "qty": after.get("requested_qty"), "qpos": after.get("queue_position"), "patch": snip(p2, 160)}
            st, r3 = res(buyer, {"requested_qty": 1, "queue_position": 1})
            live_out["insert_qpos1"] = {"st": st, "qpos": r3.get("queue_position"), "status": r3.get("status"), "id": r3.get("id")}
            for q in (0, -1, 100, 9999):
                st, rq = res(buyer, {"requested_qty": q})
                live_out[f"qty_{q}"] = {"st": st, "qty": rq.get("requested_qty"), "err": snip(rq.get("_err"), 120)}
            # seller accept
            rid = r2.get("id") or r1.get("id")
            if rid:
                st4, p4 = rpc("batata_process_live_reservation_request", buyer, {"p_request_id": rid, "p_action": "accept"})
                live_out["buyer_rpc_accept"] = {"st": st4, "body": snip(p4, 200)}
                st5, p5 = rpc("batata_process_live_reservation_request", seller, {"p_request_id": rid, "p_action": "accept"})
                live_out["seller_rpc_accept"] = {"st": st5, "body": snip(p5, 250)}
                after = row(rest("GET", "live_reservation_requests", seller, qs=f"?id=eq.{rid}&select=*")[1])
                live_out["after_accept"] = {"status": after.get("status"), "qty": after.get("requested_qty")}
                st6, o6 = order(buyer, {"product_id": pid, "live_item_id": iid, "live_id": lid, "quantity": 8, "price_total": 40})
                live_out["order_gt_res"] = {"st": st6, "q": o6.get("quantity"), "cq": o6.get("contract_qty"), "err": snip(o6.get("_err"), 160)}
                st7, o7 = order(buyer, {"product_id": pid, "live_item_id": iid, "live_id": lid, "quantity": 1, "price_total": 40})
                live_out["order_ok"] = {"st": st7, "q": o7.get("quantity"), "cq": o7.get("contract_qty"), "c": o7.get("contract_unit_cents"), "oid": o7.get("id")}
                if o7.get("id"):
                    stc, pc = checkout(buyer, o7["id"])
                    live_out["order_ok"]["checkout"] = amounts(pc)
                st8, p8 = rpc("batata_live_bag_update_qty", buyer, {"p_request_id": rid, "p_qty": 50})
                live_out["bag_qty"] = {"st": st8, "body": snip(p8, 220)}
            # two pending last unit
            pid_last = product(seller, 15.0, 1, f"{TAG} last1")
            st, p = rest("POST", "live_items", SVC, {"live_id": lid, "ref_code": "L1", "title": "last", "price": 15, "product_id": pid_last, "is_active": True})
            i2 = row(p).get("id")
            if i2:
                st_a, ra = rest("POST", "live_reservation_requests", buyer, {
                    "live_id": lid, "live_item_id": i2, "seller_id": SELLER_ID, "buyer_id": BUYER_ID,
                    "requested_qty": 1, "source": "fleaber_live", "status": "pending",
                })
                st_b, rb = rest("POST", "live_reservation_requests", buyer, {
                    "live_id": lid, "live_item_id": i2, "seller_id": SELLER_ID, "buyer_id": BUYER_ID,
                    "requested_qty": 1, "source": "fleaber_live", "status": "pending",
                })
                live_out["two_pending"] = {
                    "a": {"st": st_a, "id": row(ra).get("id"), "status": row(ra).get("status"), "qty": row(ra).get("requested_qty")},
                    "b": {"st": st_b, "id": row(rb).get("id"), "status": row(rb).get("status"), "err": snip(rb, 160)},
                }
    OUT["live"] = live_out

    # --- chats ---
    st, p = rest("GET", "chats", SVC, qs="?select=*&limit=1")
    chat_cols = list(row(p).keys())
    OUT["chat_cols"] = chat_cols
    payload = {"buyer_id": BUYER_ID, "seller_id": SELLER_ID}
    for c in chat_cols:
        if c in ("id", "created_at", "updated_at"):
            continue
    st, p = rest("POST", "chats", buyer, payload)
    ch = row(p)
    OUT["chat_insert"] = {"st": st, "id": ch.get("id"), "err": snip(p, 200)}
    if ch.get("id"):
        st2, p2 = rest("PATCH", "chats", buyer, {"seller_id": BUYER_ID}, qs=f"?id=eq.{ch['id']}")
        after = row(p2) or row(rest("GET", "chats", buyer, qs=f"?id=eq.{ch['id']}&select=*")[1])
        OUT["chat_swap"] = {"st": st2, "seller": after.get("seller_id")}

    # --- wallet credit variants ---
    dummy = str(uuid.uuid4())
    for args in [
        {"p_user_id": SELLER_ID, "p_amount": 500, "p_order_id": dummy, "p_type": "venda", "p_description": "x"},
        {"p_wallet_id": SELLER_ID, "p_amount": 500, "p_order_id": dummy, "p_type": "venda", "p_description": "x", "p_source": "x"},
    ]:
        st, p = rpc("batata_credit_wallet_once", buyer, args)
        OUT.setdefault("wallet_credit", []).append({"st": st, "args": list(args), "body": snip(p, 160)})

    # raffles list
    st, p = rest("GET", "live_raffles", seller, qs="?select=id,status,live_id&limit=5")
    OUT["raffles"] = {"st": st, "n": len(p) if isinstance(p, list) else 0, "body": snip(p, 200)}
    if isinstance(p, list) and p:
        st2, p2 = rpc("batata_draw_live_raffle_winners", buyer, {"p_raffle_id": p[0]["id"]})
        OUT["draw_real_raffle_buyer"] = {"st": st2, "body": snip(p2, 220), "raffle": p[0]["id"]}

    # stream keys seller own
    st, p = rest("GET", "lives", seller, qs=f"?seller_id=eq.{SELLER_ID}&select=id,mux_stream_key,stream_key,status&limit=3")
    keys = []
    if isinstance(p, list):
        keys = [x.get("mux_stream_key") or x.get("stream_key") for x in p if x.get("mux_stream_key") or x.get("stream_key")]
    OUT["seller_own_keys"] = {"st": st, "n_keys": len(keys), "has_key": bool(keys)}

    # flags raffle/offer update
    st, o = order(buyer, {"product_id": pid, "price_total": 40})
    if o.get("id"):
        st2, p2 = rest("PATCH", "orders", buyer, {"live_raffle_id": str(uuid.uuid4()), "product_offer_id": str(uuid.uuid4()), "payment_method": "pix"}, qs=f"?id=eq.{o['id']}")
        after = row(p2) or row(rest("GET", "orders", buyer, qs=f"?id=eq.{o['id']}&select=id,live_raffle_id,product_offer_id,payment_method,contract_unit_cents")[1])
        OUT["update_privileged_ids"] = {"st": st2, "raffle": after.get("live_raffle_id"), "offer": after.get("product_offer_id"), "pm": after.get("payment_method"), "c": after.get("contract_unit_cents")}

    # user_type restore
    rest("PATCH", "profiles", SVC, {"user_type": "comprador"}, qs=f"?id=eq.{BUYER_ID}")

    # cleanup
    for pid_ in CREATED.get("products") or []:
        rest("PATCH", "products", seller, {"quantity": 0, "list_on_marketplace": False, "title": f"{TAG} DONE"}, qs=f"?id=eq.{pid_}")
    for lid_ in CREATED.get("lives") or []:
        rest("PATCH", "lives", SVC, {"status": "ended", "is_active": False}, qs=f"?id=eq.{lid_}")
    for oid in CREATED.get("orders") or []:
        rest("PATCH", "orders", SVC, {"status": "cancelado"}, qs=f"?id=eq.{oid}")
    for rid in CREATED.get("reservations") or []:
        rest("PATCH", "live_reservation_requests", SVC, {"status": "rejected"}, qs=f"?id=eq.{rid}")

    OUT["created"] = CREATED
    path = ROOT / "tool" / "reports" / "RETESTE_POS_SATURACAO_2026-08-27_PASS2.json"
    path.write_text(json.dumps(OUT, indent=2, default=str), encoding="utf-8")
    print("WROTE", path, flush=True)


if __name__ == "__main__":
    main()
