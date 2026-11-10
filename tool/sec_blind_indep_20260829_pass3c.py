#!/usr/bin/env python3
"""Pass 3c — RPC grants, stock/live races with valid inserts, Stripe session. Staging only."""
from __future__ import annotations

import json
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
ENV = ROOT / "tool" / "live_ops_staging.env"
PROJECT = "fxdknzrqjenzqcvnwqqq"
OUT = ROOT / "tool" / "reports" / "RT_BLIND_INDEP_20260829_PASS3C.json"
TAG = f"rtb29c-{int(time.time()) if False else 0}"
import time
TAG = f"rtb29c-{int(time.time())}"


def load_env():
    out = {}
    for line in ENV.read_text(encoding="utf-8").splitlines():
        t = line.strip()
        if not t or t.startswith("#") or "=" not in t:
            continue
        k, v = t.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def req(method, url, headers, body=None, timeout=45):
    data = None
    hdrs = dict(headers)
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        hdrs.setdefault("Content-Type", "application/json")
    r = Request(url, data=data, headers=hdrs, method=method)
    try:
        with urlopen(r, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            try:
                parsed = json.loads(raw) if raw else None
            except json.JSONDecodeError:
                parsed = raw[:2000]
            return {"http": resp.status, "body": parsed, "text": raw[:2500]}
    except HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            parsed = raw[:2000]
        return {"http": e.code, "body": parsed, "text": raw[:2500]}
    except URLError as e:
        return {"http": 0, "body": None, "text": str(e)}


def row(r):
    b = r.get("body")
    if isinstance(b, list) and b and isinstance(b[0], dict):
        return b[0]
    if isinstance(b, dict) and b.get("id"):
        return b
    return None


def err(r):
    b = r.get("body")
    if isinstance(b, dict):
        return b.get("message") or b.get("error") or b.get("code") or b
    return (r.get("text") or "")[:200]


class C:
    def __init__(self, env):
        raw = env["SUPABASE_URL"].strip().rstrip("/")
        for s in ("/rest/v1", "/auth/v1", "/functions/v1"):
            if raw.endswith(s):
                raw = raw[: -len(s)].rstrip("/")
        self.base = raw
        self.anon = env["SUPABASE_ANON_KEY"]
        self.svc = env["SUPABASE_SERVICE_ROLE_KEY"]
        self.buyer = env["LIVE_OPS_TEST_BUYER_ID"]
        self.seller = env["LIVE_OPS_TEST_SELLER_ID"]
        self.bemail = env["LIVE_OPS_TEST_BUYER_EMAIL"]
        self.semail = env["LIVE_OPS_TEST_SELLER_EMAIL"]
        self.bj = self.login(env["LIVE_OPS_TEST_BUYER_EMAIL"], env["LIVE_OPS_TEST_BUYER_PASSWORD"])
        self.sj = self.login(env["LIVE_OPS_TEST_SELLER_EMAIL"], env["LIVE_OPS_TEST_SELLER_PASSWORD"])
        self.out = {"tag": TAG, "tests": []}

    def login(self, email, password):
        r = req(
            "POST",
            f"{self.base}/auth/v1/token?grant_type=password",
            {"apikey": self.anon, "Content-Type": "application/json"},
            {"email": email, "password": password},
        )
        assert r["http"] == 200, r
        return r["body"]["access_token"]

    def H(self, tok):
        key = self.svc if tok == self.svc else self.anon
        return {
            "apikey": key,
            "Authorization": f"Bearer {tok}",
            "Content-Type": "application/json",
            "Prefer": "return=representation",
        }

    def rest(self, method, path, tok, body=None):
        return req(method, f"{self.base}/rest/v1/{path}", self.H(tok), body)

    def rpc(self, name, tok, params=None):
        return req("POST", f"{self.base}/rest/v1/rpc/{name}", self.H(tok), params or {})

    def edge(self, name, tok, body):
        return req(
            "POST",
            f"{self.base}/functions/v1/{name}",
            {
                "apikey": self.anon,
                "Authorization": f"Bearer {tok}",
                "Content-Type": "application/json",
            },
            body,
        )

    def rec(self, name, **k):
        self.out["tests"].append({"name": name, **k})
        print("TEST", name, json.dumps({x: k[x] for x in k if x != "raw"}, default=str)[:500], flush=True)

    def rpcs(self):
        uid = str(uuid.uuid4())
        calls = [
            ("buyer", "batata_admin_list_profiles", {"p_limit": 10}),
            ("buyer", "batata_admin_resolve_dispute", {"p_dispute_id": uid, "p_resolution": "favor_buyer_refund"}),
            ("buyer", "staging_nuke_user_data", {"p_user_id": self.buyer}),
            ("buyer", "batata_clawback_seller_wallet_for_order", {"p_order_id": uid}),
            ("buyer", "batata_find_user_id_by_email", {"p_email": self.semail}),
            ("anon", "batata_find_user_id_by_email", {"p_email": self.semail}),
            ("buyer", "batata_seller_direct_payment_details", {"p_seller_id": self.seller}),
            ("buyer", "batata_get_my_payout_details", {}),
            ("buyer", "batata_send_live_tip_from_wallet", {"p_live_id": uid, "p_amount": 1}),
            ("buyer", "batata_wallet_apply_tip_once", {}),
            ("buyer", "batata_settle_live_tip_from_stripe", {"p_session_id": "cs_test_x"}),
            ("buyer", "batata_process_partial_refund_dispute", {"p_dispute_id": uid}),
            ("buyer", "batata_record_buyer_refund_ledger", {"p_order_id": uid, "p_amount": 10}),
            ("buyer", "batata_credit_wallet_once", {
                "p_wallet_id": self.buyer, "p_order_id": uid, "p_amount": 5, "p_type": "venda", "p_description": TAG
            }),
            ("buyer", "batata_debit_wallet_once", {
                "p_wallet_id": self.seller, "p_order_id": uid, "p_amount": 1, "p_type": "estorno", "p_description": TAG
            }),
            ("buyer", "batata_wallet_payout_debit", {
                "p_user_id": self.seller, "p_amount_cents": 50, "p_idempotency_key": TAG + "x"
            }),
            ("buyer", "batata_finalize_stripe_order_refund", {
                "p_order_id": uid, "p_refund_id": "re_x", "p_payment_intent_id": "pi_x", "p_session_id": "cs_x", "p_amount_cents": 100
            }),
            ("buyer", "batata_create_raffle_prize_order", {"p_raffle_id": uid, "p_user_id": self.buyer, "p_qty": 1}),
            ("buyer", "batata_draw_live_raffle_winners", {"p_raffle_id": uid}),
            ("buyer", "batata_award_live_raffle_tickets", {
                "p_live_id": uid, "p_user_id": self.buyer, "p_source": "x", "p_qty": 5, "p_note": "x"
            }),
            ("buyer", "batata_live_reconcile_stripe_order", {"p_order_id": uid}),
            ("buyer", "batata_live_reservation_stripe_convert", {"p_order_id": uid}),
            ("seller", "batata_admin_list_profiles", {"p_limit": 5}),
            ("seller", "staging_nuke_user_data", {"p_user_id": self.buyer}),
            ("buyer", "batata_generate_auto_feedback", {}),
            ("buyer", "batata_lab_clear_all_fm_pending", {}),
            ("buyer", "batata_assert_wallet_rpc_grants", {}),
        ]
        toks = {"buyer": self.bj, "seller": self.sj, "anon": self.anon}
        for ident, fn, params in calls:
            r = self.rpc(fn, toks[ident], params)
            interesting = r["http"] == 200 and r.get("body") not in (None, False, 0, [], {})
            self.rec(
                "rpc",
                ident=ident,
                fn=fn,
                http=r["http"],
                body=r.get("body") if r["http"] < 500 else None,
                err=str(err(r))[:180],
                interesting=interesting,
            )

    def stock_sessions(self):
        prod = self.rest(
            "POST",
            "products",
            self.svc,
            {
                "seller_id": self.seller,
                "title": f"{TAG} s1",
                "price": 8.0,
                "quantity": 1,
                "list_on_marketplace": True,
                "is_sold": False,
                "ref_code": f"{TAG}-s1",
            },
        )
        pid = (row(prod) or {}).get("id")

        def mk():
            return self.rest(
                "POST",
                "orders",
                self.bj,
                {
                    "buyer_id": self.buyer,
                    "seller_id": self.seller,
                    "product_id": pid,
                    "quantity": 1,
                    "price_total": 8,
                    "status": "reserva_pendente",
                    "payment_method": "Seguro Fleaber",
                    "shipping_method": "hand",
                },
            )

        seq = [mk(), mk()]
        orders = [row(r) for r in seq if row(r)]
        self.rec(
            "two_orders_stock1",
            pid=pid,
            https=[r["http"] for r in seq],
            n=len(orders),
            errs=[str(err(r))[:100] for r in seq],
            ids=[o.get("id") for o in orders],
            qty=[o.get("quantity") for o in orders],
            unit=[o.get("contract_unit_cents") for o in orders],
        )
        if len(orders) >= 2:
            def ck(oid):
                return self.edge(
                    "create-payment-intent",
                    self.bj,
                    {"buyer_id": self.buyer, "order_id": oid, "shipping_method": "hand"},
                )
            with ThreadPoolExecutor(max_workers=2) as ex:
                futs = [ex.submit(ck, orders[0]["id"]), ex.submit(ck, orders[1]["id"])]
                ss = [f.result() for f in as_completed(futs)]
            urls = []
            for s in ss:
                b = s.get("body") if isinstance(s.get("body"), dict) else {}
                urls.append(b.get("checkoutUrl") or b.get("url"))
            self.rec(
                "two_sessions_stock1",
                https=[s["http"] for s in ss],
                amounts=[
                    (s.get("body") or {}).get("amount_total") if isinstance(s.get("body"), dict) else None
                    for s in ss
                ],
                n_ok=sum(1 for s in ss if s["http"] in (200, 201)),
                urls=urls,
                errs=[str(err(s))[:120] for s in ss],
            )
        conc = []
        prod2 = self.rest(
            "POST",
            "products",
            self.svc,
            {
                "seller_id": self.seller,
                "title": f"{TAG} s1c",
                "price": 8.0,
                "quantity": 1,
                "list_on_marketplace": True,
                "is_sold": False,
                "ref_code": f"{TAG}-s1c",
            },
        )
        pid2 = (row(prod2) or {}).get("id")

        def mk2():
            return self.rest(
                "POST",
                "orders",
                self.bj,
                {
                    "buyer_id": self.buyer,
                    "seller_id": self.seller,
                    "product_id": pid2,
                    "quantity": 1,
                    "price_total": 8,
                    "status": "reserva_pendente",
                    "payment_method": "Seguro Fleaber",
                    "shipping_method": "hand",
                },
            )

        with ThreadPoolExecutor(max_workers=8) as ex:
            conc = [f.result() for f in as_completed([ex.submit(mk2) for _ in range(8)])]
        created = [row(r) for r in conc if row(r)]
        self.rec(
            "eight_concurrent_orders_stock1",
            created=len(created),
            https=[r["http"] for r in conc],
            errs=sorted({str(err(r))[:120] for r in conc}),
        )

        # MB WAY dual pago
        prod3 = self.rest(
            "POST",
            "products",
            self.svc,
            {
                "seller_id": self.seller,
                "title": f"{TAG} mb",
                "price": 8.0,
                "quantity": 1,
                "list_on_marketplace": True,
                "is_sold": False,
                "ref_code": f"{TAG}-mb",
            },
        )
        pid3 = (row(prod3) or {}).get("id")
        oA = row(self.rest("POST", "orders", self.bj, {
            "buyer_id": self.buyer, "seller_id": self.seller, "product_id": pid3,
            "quantity": 1, "price_total": 8, "status": "reserva_pendente",
            "payment_method": "MB WAY", "shipping_method": "hand",
        }))
        oB = row(self.rest("POST", "orders", self.bj, {
            "buyer_id": self.buyer, "seller_id": self.seller, "product_id": pid3,
            "quantity": 1, "price_total": 8, "status": "reserva_pendente",
            "payment_method": "MB WAY", "shipping_method": "hand",
        }))
        if oA and oB:
            def pay(oid):
                return self.rest("PATCH", f"orders?id=eq.{oid}", self.sj, {"status": "pago"})
            with ThreadPoolExecutor(max_workers=2) as ex:
                pr = [f.result() for f in as_completed([ex.submit(pay, oA["id"]), ex.submit(pay, oB["id"])])]
            after = self.rest(
                "GET",
                f"orders?id=in.({oA['id']},{oB['id']})&select=id,status,stock_units_applied",
                self.svc,
            )
            prod_after = row(self.rest("GET", f"products?id=eq.{pid3}&select=id,quantity", self.svc))
            paid = [x for x in (after.get("body") or []) if isinstance(x, dict) and str(x.get("status")).lower() == "pago"]
            self.rec(
                "mbway_dual_pago_stock1",
                paid_n=len(paid),
                product=prod_after,
                orders=after.get("body"),
                https=[p["http"] for p in pr],
                errs=[str(err(p))[:100] for p in pr],
            )

    def live_cap(self):
        live = self.rest("POST", "lives", self.svc, {
            "seller_id": self.seller, "vendedor_id": self.seller,
            "title": f"{TAG} lv", "status": "ended", "is_active": False,
        })
        lid = (row(live) or {}).get("id")
        item = self.rest("POST", "live_items", self.svc, {
            "live_id": lid, "seller_id": self.seller, "title": f"{TAG} li",
            "price": 4.0, "quantity": 1, "ref_code": f"{TAG}-li",
        })
        iid = (row(item) or {}).get("id")
        if not iid:
            self.rec("live_item_fail", err=str(err(item))[:200], body=item.get("body"))
            return

        def acc(name, status="converted"):
            return self.rest("POST", "live_reservation_requests", self.sj, {
                "live_id": lid, "live_item_id": iid, "buyer_id": self.buyer,
                "seller_id": self.seller, "requested_qty": 1, "status": status,
                "external_display_name": name,
            })

        a = acc(f"{TAG}-a")
        b = acc(f"{TAG}-b")
        self.rec(
            "two_converted_qty1",
            a={"http": a["http"], "status": (row(a) or {}).get("status"), "err": str(err(a))[:120]},
            b={"http": b["http"], "status": (row(b) or {}).get("status"), "err": str(err(b))[:120]},
        )
        buy = self.rest("POST", "live_reservation_requests", self.bj, {
            "live_id": lid, "live_item_id": iid, "buyer_id": self.buyer,
            "seller_id": self.seller, "requested_qty": 1, "status": "converted",
        })
        self.rec("buyer_converted", http=buy["http"], status=(row(buy) or {}).get("status"), err=str(err(buy))[:120])
        rs = []
        with ThreadPoolExecutor(max_workers=10) as ex:
            futs = [ex.submit(acc, f"{TAG}-r{i}-{uuid.uuid4().hex[:4]}") for i in range(10)]
            rs = [f.result() for f in as_completed(futs)]
        ok = [
            row(r) for r in rs
            if row(r) and str((row(r) or {}).get("status", "")).lower() in {"accepted", "converted"}
        ]
        self.rec("race10_converted", ok=len(ok), https=[r["http"] for r in rs], errs=sorted({str(err(r))[:80] for r in rs}))

    def bag(self):
        p1 = row(self.rest("POST", "products", self.svc, {
            "seller_id": self.seller, "title": f"{TAG} A", "price": 5, "quantity": 2,
            "list_on_marketplace": True, "is_sold": False, "ref_code": f"{TAG}-A",
        }))
        p2 = row(self.rest("POST", "products", self.svc, {
            "seller_id": self.seller, "title": f"{TAG} B", "price": 7, "quantity": 2,
            "list_on_marketplace": True, "is_sold": False, "ref_code": f"{TAG}-B",
        }))
        o1 = row(self.rest("POST", "orders", self.bj, {
            "buyer_id": self.buyer, "seller_id": self.seller, "product_id": p1["id"],
            "quantity": 1, "price_total": 5, "status": "reserva_pendente",
            "payment_method": "Seguro Fleaber", "shipping_method": "hand",
        }))
        o2 = row(self.rest("POST", "orders", self.bj, {
            "buyer_id": self.buyer, "seller_id": self.seller, "product_id": p2["id"],
            "quantity": 1, "price_total": 7, "status": "reserva_pendente",
            "payment_method": "Seguro Fleaber", "shipping_method": "hand",
        }))
        bag = self.edge("create-payment-intent", self.bj, {
            "buyer_id": self.buyer, "bag_checkout": True, "shipping_method": "hand",
            "amount": 50,
            "bag_lines": [
                {"order_id": o1["id"] if o1 else None, "line_total_cents": 1, "quantity": 9},
                {"order_id": o2["id"] if o2 else None, "line_total_cents": 1, "quantity": 9},
            ],
        })
        b = bag.get("body") if isinstance(bag.get("body"), dict) else {}
        # expected: 5+7=12 EUR + prot 0.65+0.60=1.25 => 1325 cents
        self.rec(
            "bag_hostile_line_totals",
            http=bag["http"],
            amount=b.get("amount_total") or b.get("server_amount_cents"),
            err=str(err(bag))[:160],
            url=b.get("checkoutUrl"),
        )

    def stripe_session_note(self):
        prod = row(self.rest("POST", "products", self.svc, {
            "seller_id": self.seller, "title": f"{TAG} pay", "price": 5.5, "quantity": 1,
            "list_on_marketplace": True, "is_sold": False, "ref_code": f"{TAG}-pay",
        }))
        o = row(self.rest("POST", "orders", self.bj, {
            "buyer_id": self.buyer, "seller_id": self.seller, "product_id": prod["id"],
            "quantity": 1, "price_total": 1, "status": "reserva_pendente",
            "payment_method": "Seguro Fleaber", "shipping_method": "hand",
        }))
        ck = self.edge("create-payment-intent", self.bj, {
            "buyer_id": self.buyer, "order_id": o["id"] if o else None,
            "shipping_method": "hand", "amount": 1, "item_price": 0.01, "quantity": 99,
        })
        b = ck.get("body") if isinstance(ck.get("body"), dict) else {}
        self.rec(
            "stripe_session_created_not_captured",
            order=o,
            http=ck["http"],
            amount=b.get("amount_total") or b.get("server_amount_cents"),
            session=b.get("checkoutSessionId"),
            url=b.get("checkoutUrl"),
            contract= (o or {}).get("contract_unit_cents"),
        )


def main():
    c = C(load_env())
    c.rpcs()
    c.stock_sessions()
    c.live_cap()
    c.bag()
    c.stripe_session_note()
    c.out["frozen_at"] = datetime.now(timezone.utc).isoformat()
    OUT.write_text(json.dumps(c.out, indent=2, default=str), encoding="utf-8")
    print("WROTE", OUT)


if __name__ == "__main__":
    main()
