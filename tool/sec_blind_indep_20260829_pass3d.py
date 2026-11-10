#!/usr/bin/env python3
"""Pass 3d residuals: bag+order_id, PII RPC, live accept PATCH, tip wallet, profiles columns."""
from __future__ import annotations

import json
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
ENV = ROOT / "tool" / "live_ops_staging.env"
PROJECT = "fxdknzrqjenzqcvnwqqq"
OUT = ROOT / "tool" / "reports" / "RT_BLIND_INDEP_20260829_PASS3D.json"
TAG = f"rtb29d-{int(time.time())}"


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
            return {"http": resp.status, "body": parsed}
    except HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            parsed = raw[:2000]
        return {"http": e.code, "body": parsed}
    except URLError as e:
        return {"http": 0, "body": str(e)}


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
        return b.get("message") or b.get("error") or b
    return b


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
        print("TEST", name, json.dumps(k, default=str)[:450], flush=True)

    def run(self):
        # PII columns
        p = self.rest("GET", f"profiles?id=eq.{self.seller}&select=id,iban,mb_way,phone,user_type", self.bj)
        pown = self.rest("GET", f"profiles?id=eq.{self.buyer}&select=id,iban,mb_way", self.bj)
        self.rec("profiles_select_iban", seller_as_buyer={"http": p["http"], "body": p.get("body")}, own={"http": pown["http"], "body": pown.get("body")})

        rnd = str(uuid.uuid4())
        d1 = self.rpc("batata_seller_direct_payment_details", self.bj, {"p_seller_id": rnd})
        d2 = self.rpc("batata_seller_direct_payment_details", self.bj, {"p_seller_id": self.seller})
        self.rec("payment_details_scope", random={"http": d1["http"], "body": d1.get("body")}, counterparty={"http": d2["http"], "body": d2.get("body")})

        # bag with order_id
        pa = row(self.rest("POST", "products", self.svc, {
            "seller_id": self.seller, "title": f"{TAG} A", "price": 5, "quantity": 2,
            "list_on_marketplace": True, "is_sold": False, "ref_code": f"{TAG}-A",
        }))
        pb = row(self.rest("POST", "products", self.svc, {
            "seller_id": self.seller, "title": f"{TAG} B", "price": 7, "quantity": 2,
            "list_on_marketplace": True, "is_sold": False, "ref_code": f"{TAG}-B",
        }))
        o1 = row(self.rest("POST", "orders", self.bj, {
            "buyer_id": self.buyer, "seller_id": self.seller, "product_id": pa["id"],
            "quantity": 1, "price_total": 5, "status": "reserva_pendente",
            "payment_method": "Seguro Fleaber", "shipping_method": "hand",
        }))
        o2 = row(self.rest("POST", "orders", self.bj, {
            "buyer_id": self.buyer, "seller_id": self.seller, "product_id": pb["id"],
            "quantity": 1, "price_total": 7, "status": "reserva_pendente",
            "payment_method": "Seguro Fleaber", "shipping_method": "hand",
        }))
        bag = self.edge("create-payment-intent", self.bj, {
            "buyer_id": self.buyer,
            "order_id": o1["id"] if o1 else None,
            "bag_checkout": True,
            "shipping_method": "hand",
            "amount": 50,
            "bag_lines": [
                {"order_id": o1["id"] if o1 else None, "line_total_cents": 1, "quantity": 9},
                {"order_id": o2["id"] if o2 else None, "line_total_cents": 1, "quantity": 9},
            ],
        })
        b = bag.get("body") if isinstance(bag.get("body"), dict) else {}
        self.rec("bag_with_order_id", http=bag["http"], amount=b.get("amount_total") or b.get("server_amount_cents"), err=err(bag) if bag["http"] >= 400 else None)

        # live accept via PATCH
        live = row(self.rest("POST", "lives", self.svc, {
            "seller_id": self.seller, "vendedor_id": self.seller,
            "title": f"{TAG} lv", "status": "live", "is_active": True,
        }))
        item = row(self.rest("POST", "live_items", self.svc, {
            "live_id": live["id"] if live else None, "seller_id": self.seller,
            "title": f"{TAG} li", "price": 4.0, "quantity": 1, "ref_code": f"{TAG}-li",
        }))
        pend = row(self.rest("POST", "live_reservation_requests", self.bj, {
            "live_id": live["id"] if live else None,
            "live_item_id": item["id"] if item else None,
            "buyer_id": self.buyer, "seller_id": self.seller,
            "requested_qty": 1, "status": "pending",
        }))
        acc1 = self.rest("PATCH", f"live_reservation_requests?id=eq.{pend['id']}", self.sj, {"status": "accepted"}) if pend else {"http": 0, "body": None}
        pend2 = row(self.rest("POST", "live_reservation_requests", self.bj, {
            "live_id": live["id"] if live else None,
            "live_item_id": item["id"] if item else None,
            "buyer_id": self.buyer, "seller_id": self.seller,
            "requested_qty": 1, "status": "pending",
        }))
        acc2 = self.rest("PATCH", f"live_reservation_requests?id=eq.{pend2['id']}", self.sj, {"status": "accepted"}) if pend2 else {"http": 0, "body": None}
        conv = self.rest("PATCH", f"live_reservation_requests?id=eq.{pend['id']}", self.bj, {"status": "converted"}) if pend else {"http": 0}
        after = self.rest(
            "GET",
            f"live_reservation_requests?live_item_id=eq.{item['id']}&select=id,status,requested_qty,buyer_id" if item else "live_reservation_requests?limit=0",
            self.svc,
        )
        # end live to not leave it running (workspace rule)
        if live:
            self.rest("PATCH", f"lives?id=eq.{live['id']}", self.svc, {"status": "ended", "is_active": False})
        self.rec(
            "live_accept_patch",
            item=item["id"] if item else None,
            pend=pend,
            acc1={"http": acc1["http"], "row": row(acc1), "err": err(acc1)},
            acc2={"http": acc2["http"], "row": row(acc2), "err": err(acc2)},
            buyer_convert={"http": conv["http"], "row": row(conv), "err": err(conv)},
            rows=after.get("body"),
        )

        tip = self.rpc("batata_send_live_tip_from_wallet", self.bj, {
            "p_amount": 1, "p_live_id": str(uuid.uuid4()), "p_message": "x", "p_seller_id": self.seller,
        })
        prize = self.rpc("batata_create_raffle_prize_order", self.bj, {
            "p_raffle_id": str(uuid.uuid4()), "p_rank": 1, "p_winner_uid": self.buyer,
        })
        refund_led = self.rpc("batata_record_buyer_refund_ledger", self.bj, {"p_order_id": str(uuid.uuid4())})
        self.rec("rpc_correct_params", tip={"http": tip["http"], "body": tip.get("body")}, prize={"http": prize["http"], "body": prize.get("body")}, refund_led={"http": refund_led["http"], "body": refund_led.get("body")})


def main():
    c = C(load_env())
    c.run()
    c.out["frozen_at"] = datetime.now(timezone.utc).isoformat()
    OUT.write_text(json.dumps(c.out, indent=2, default=str), encoding="utf-8")
    print("WROTE", OUT)


if __name__ == "__main__":
    main()
