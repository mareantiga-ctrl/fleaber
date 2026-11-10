#!/usr/bin/env python3
"""Pass 2/3 verification — independent blind audit 2026-08-29. Staging only."""
from __future__ import annotations

import json
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
ENV = ROOT / "tool" / "live_ops_staging.env"
PROJECT = "fxdknzrqjenzqcvnwqqq"
OUT = ROOT / "tool" / "reports" / "RT_BLIND_INDEP_20260829_PASS23.json"
TAG = f"rtb29b-{int(time.time())}"


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
            return {"http": resp.status, "body": parsed, "text": raw[:3000]}
    except HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            parsed = raw[:2000]
        return {"http": e.code, "body": parsed, "text": raw[:3000]}
    except URLError as e:
        return {"http": 0, "body": None, "text": str(e)}


def row(r):
    b = r.get("body")
    if isinstance(b, list) and b and isinstance(b[0], dict):
        return b[0]
    if isinstance(b, dict) and ("id" in b or "balance" in b):
        return b
    return None


def err(r):
    b = r.get("body")
    if isinstance(b, dict):
        return b.get("message") or b.get("error") or b
    return (r.get("text") or "")[:240]


class C:
    def __init__(self, env):
        raw = env["SUPABASE_URL"].strip().rstrip("/")
        for s in ("/rest/v1", "/auth/v1", "/functions/v1"):
            if raw.endswith(s):
                raw = raw[: -len(s)].rstrip("/")
        self.base = raw
        assert PROJECT in self.base
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

    def edge(self, name, tok, body, qs=""):
        return req(
            "POST",
            f"{self.base}/functions/v1/{name}{qs}",
            {
                "apikey": self.anon,
                "Authorization": f"Bearer {tok}",
                "Content-Type": "application/json",
            },
            body,
        )

    def rec(self, name, **k):
        self.out["tests"].append({"name": name, **k})
        print("TEST", name, {x: k[x] for x in k if x != "raw"}, flush=True)

    def verify_old_p0_order(self):
        oid = "e5b75840-8a77-42b0-839d-27d61199d659"
        o = self.rest(
            "GET",
            f"orders?id=eq.{oid}&select=id,status,amount_paid_cents,wallet_release_processed_at,price_total,payment_method,stock_units_applied",
            self.svc,
        )
        txs = self.rest(
            "GET",
            f"wallet_transactions?order_id=eq.{oid}&select=id,wallet_id,amount,type,description,created_at",
            self.svc,
        )
        w = self.rest("GET", f"wallets?id=eq.{self.seller}&select=id,balance", self.svc)
        self.rec(
            "verify_RTB_WAL_OFF_order",
            order=row(o) or o.get("body"),
            txs=txs.get("body"),
            seller_wallet=row(w),
        )

    def reproduce_offplatform_wallet_twice(self):
        results = []
        for i in range(2):
            prod = self.rest(
                "POST",
                "products",
                self.svc,
                {
                    "seller_id": self.seller,
                    "title": f"{TAG} mb {i}",
                    "price": 6.0,
                    "quantity": 1,
                    "list_on_marketplace": True,
                    "is_sold": False,
                    "ref_code": f"{TAG}-mb-{i}",
                },
            )
            pid = (row(prod) or {}).get("id")
            w_before = row(self.rest("GET", f"wallets?id=eq.{self.seller}&select=id,balance", self.svc))
            ord_ = self.rest(
                "POST",
                "orders",
                self.bj,
                {
                    "buyer_id": self.buyer,
                    "seller_id": self.seller,
                    "product_id": pid,
                    "quantity": 1,
                    "status": "reserva_pendente",
                    "payment_method": "MB WAY",
                    "shipping_method": "hand",
                    "price_total": 99,
                },
            )
            oid = (row(ord_) or {}).get("id")
            p1 = self.rest("PATCH", f"orders?id=eq.{oid}", self.sj, {"status": "pago"})
            p2 = self.rest("PATCH", f"orders?id=eq.{oid}", self.sj, {"status": "enviado"})
            p3 = self.rest("PATCH", f"orders?id=eq.{oid}", self.bj, {"status": "concluido"})
            after_fsm = row(
                self.rest(
                    "GET",
                    f"orders?id=eq.{oid}&select=id,status,amount_paid_cents,price_total,wallet_release_processed_at,stock_units_applied,contract_unit_cents",
                    self.svc,
                )
            )
            rel = self.rpc("batata_release_seller_wallet_for_order", self.bj, {"p_order_id": oid})
            rel2 = self.rpc("batata_release_seller_wallet_for_order", self.bj, {"p_order_id": oid})
            after = row(
                self.rest(
                    "GET",
                    f"orders?id=eq.{oid}&select=id,status,amount_paid_cents,wallet_release_processed_at,price_total",
                    self.svc,
                )
            )
            w_after = row(self.rest("GET", f"wallets?id=eq.{self.seller}&select=id,balance", self.svc))
            txs = self.rest(
                "GET",
                f"wallet_transactions?order_id=eq.{oid}&select=id,amount,type,description",
                self.svc,
            )
            delta = None
            try:
                delta = float(w_after["balance"]) - float(w_before["balance"])
            except Exception:
                pass
            minted = bool(txs.get("body")) or (delta is not None and delta > 0.001)
            results.append(
                {
                    "i": i,
                    "oid": oid,
                    "insert_order": row(ord_),
                    "fsm": {"pago": err(p1), "enviado": err(p2), "concluido": err(p3)},
                    "after_fsm": after_fsm,
                    "release_http": rel["http"],
                    "release_body": rel.get("body"),
                    "release2_body": rel2.get("body"),
                    "after_release": after,
                    "wallet_before": w_before,
                    "wallet_after": w_after,
                    "delta": delta,
                    "txs": txs.get("body"),
                    "minted": minted,
                }
            )
        self.rec("offplatform_wallet_repro_x2", results=results)

    def chat_and_dispute_scope(self):
        chats_b = self.rest("GET", "chats?select=id,user_a,user_b&limit=50", self.bj)
        chats_s = self.rest("GET", "chats?select=id,user_a,user_b&limit=50", self.sj)
        chats_a = self.rest("GET", "chats?select=id,user_a,user_b&limit=5", self.anon)

        def foreign(rows, uid):
            out = []
            for r in rows or []:
                if uid not in {r.get("user_a"), r.get("user_b"), r.get("buyer_id"), r.get("seller_id")}:
                    out.append(r)
            return out

        fb = foreign(chats_b.get("body") if isinstance(chats_b.get("body"), list) else [], self.buyer)
        fs = foreign(chats_s.get("body") if isinstance(chats_s.get("body"), list) else [], self.seller)
        msgs = self.rest(
            "GET",
            "chat_messages?select=id,chat_id,sender_id,text&limit=30",
            self.sj,
        )
        third = []
        chat_ids = {c.get("id") for c in (chats_s.get("body") or []) if isinstance(c, dict)}
        for m in msgs.get("body") or []:
            if not isinstance(m, dict):
                continue
            if m.get("chat_id") not in chat_ids:
                third.append({"id": m.get("id"), "chat_id": m.get("chat_id"), "sender_id": m.get("sender_id")})
            elif m.get("sender_id") not in {self.seller, self.buyer} and m.get("chat_id") in chat_ids:
                # counterparty message in own chat — OK
                pass
        disp_s = self.rest(
            "GET",
            "order_disputes?select=id,order_id,buyer_id,seller_id,status,reason,description&limit=20",
            self.sj,
        )
        disp_b = self.rest(
            "GET",
            "order_disputes?select=id,order_id,buyer_id,seller_id,status&limit=20",
            self.bj,
        )
        disp_a = self.rest(
            "GET",
            "order_disputes?select=id,buyer_id,seller_id&limit=5",
            self.anon,
        )
        fd_s = [
            d
            for d in (disp_s.get("body") or [])
            if isinstance(d, dict) and self.seller not in {d.get("seller_id"), d.get("buyer_id")}
        ]
        fd_b = [
            d
            for d in (disp_b.get("body") or [])
            if isinstance(d, dict) and self.buyer not in {d.get("seller_id"), d.get("buyer_id")}
        ]
        # try read a specific foreign chat if we know any via service
        sample = self.rest("GET", "chats?select=id,user_a,user_b&limit=20", self.svc)
        foreign_chat = None
        for c in sample.get("body") or []:
            if self.buyer not in {c.get("user_a"), c.get("user_b")} and self.seller not in {
                c.get("user_a"),
                c.get("user_b"),
            }:
                foreign_chat = c
                break
        read_foreign = None
        if foreign_chat:
            read_foreign = {
                "chat": foreign_chat,
                "buyer_get": self.rest("GET", f"chats?id=eq.{foreign_chat['id']}&select=id,user_a,user_b", self.bj),
                "buyer_msgs": self.rest(
                    "GET",
                    f"chat_messages?chat_id=eq.{foreign_chat['id']}&select=id,sender_id,text&limit=3",
                    self.bj,
                ),
            }
        self.rec(
            "privacy_chat_dispute",
            anon_chats_n=len(chats_a.get("body") or []) if isinstance(chats_a.get("body"), list) else chats_a,
            buyer_foreign_chats=fb,
            seller_foreign_chats=fs,
            seller_messages_outside_own_chats=third[:10],
            seller_foreign_disputes=fd_s[:5],
            buyer_foreign_disputes=fd_b[:5],
            anon_disputes=disp_a.get("body"),
            targeted_foreign= {
                "found": bool(foreign_chat),
                "buyer_http": (read_foreign or {}).get("buyer_get", {}).get("http") if read_foreign else None,
                "buyer_chat_body": (read_foreign or {}).get("buyer_get", {}).get("body") if read_foreign else None,
                "buyer_msgs_n": len(((read_foreign or {}).get("buyer_msgs") or {}).get("body") or [])
                if read_foreign
                else None,
                "buyer_msgs_http": ((read_foreign or {}).get("buyer_msgs") or {}).get("http") if read_foreign else None,
            },
        )

    def price_total_authority(self):
        prod = self.rest(
            "POST",
            "products",
            self.svc,
            {
                "seller_id": self.seller,
                "title": f"{TAG} pt",
                "price": 10.0,
                "quantity": 2,
                "list_on_marketplace": True,
                "is_sold": False,
                "ref_code": f"{TAG}-pt",
            },
        )
        pid = (row(prod) or {}).get("id")
        ins = self.rest(
            "POST",
            "orders",
            self.bj,
            {
                "buyer_id": self.buyer,
                "seller_id": self.seller,
                "product_id": pid,
                "quantity": 1,
                "status": "reserva_pendente",
                "payment_method": "Seguro Fleaber",
                "shipping_method": "hand",
                "price_total": 0.01,
            },
        )
        oid = (row(ins) or {}).get("id")
        sealed = row(
            self.rest(
                "GET",
                f"orders?id=eq.{oid}&select=id,price_total,contract_unit_cents,contract_qty,quantity,status",
                self.svc,
            )
        )
        up = self.rest("PATCH", f"orders?id=eq.{oid}", self.bj, {"price_total": 999.0})
        after = row(
            self.rest(
                "GET",
                f"orders?id=eq.{oid}&select=id,price_total,contract_unit_cents",
                self.svc,
            )
        )
        ck = self.edge(
            "create-payment-intent",
            self.bj,
            {"buyer_id": self.buyer, "order_id": oid, "shipping_method": "hand", "amount": 50},
        )
        amt = None
        if isinstance(ck.get("body"), dict):
            amt = ck["body"].get("amount_total") or ck["body"].get("amount")
        self.rec(
            "price_total_vs_checkout",
            insert=sealed,
            patch_http=up["http"],
            after_patch=after,
            checkout_http=ck["http"],
            checkout_amount=amt,
            checkout_err=err(ck),
        )

    def payout_ledger_and_race(self):
        w0 = row(self.rest("GET", f"wallets?id=eq.{self.seller}&select=id,balance,stripe_account_id", self.svc))
        led0 = self.rest(
            "GET",
            f"wallet_payout_ledger?user_id=eq.{self.seller}&select=idempotency_key,status,amount_cents,stripe_transfer_id,created_at&order=created_at.desc&limit=15",
            self.svc,
        )
        keys = [f"{TAG}-payout-{i}-{uuid.uuid4().hex[:8]}" for i in range(2)]

        def po(k):
            return self.edge(
                "create-connect-account",
                self.sj,
                {"amount": 100, "idempotency_key": k},
            )

        # sequential distinct intentions of 1 EUR
        r1 = po(keys[0])
        r2 = po(keys[1])
        w1 = row(self.rest("GET", f"wallets?id=eq.{self.seller}&select=id,balance", self.svc))
        led1 = self.rest(
            "GET",
            f"wallet_payout_ledger?user_id=eq.{self.seller}&select=idempotency_key,status,amount_cents,stripe_transfer_id,created_at&order=created_at.desc&limit=10",
            self.svc,
        )
        self.rec(
            "payout_two_distinct_intentions",
            wallet_before=w0,
            r1={"http": r1["http"], "body": r1.get("body")},
            r2={"http": r2["http"], "body": r2.get("body")},
            wallet_after=w1,
            ledger_after=led1.get("body"),
            keys=keys,
        )
        # concurrent same amount new keys if balance remains
        keys2 = [f"{TAG}-race-{i}-{uuid.uuid4().hex[:8]}" for i in range(4)]
        rs = []
        with ThreadPoolExecutor(max_workers=4) as ex:
            futs = [ex.submit(po, k) for k in keys2]
            for f in as_completed(futs):
                rs.append(f.result())
        led2 = self.rest(
            "GET",
            f"wallet_payout_ledger?user_id=eq.{self.seller}&select=idempotency_key,status,amount_cents,stripe_transfer_id,created_at&order=created_at.desc&limit=12",
            self.svc,
        )
        transfers = []
        for r in rs:
            b = r.get("body")
            if isinstance(b, dict):
                transfers.append(b.get("transferId") or b.get("transfer_id"))
        self.rec(
            "payout_concurrent_distinct_keys",
            http=[r["http"] for r in rs],
            bodies=[r.get("body") for r in rs],
            unique_transfers=sorted({t for t in transfers if t}),
            ledger=led2.get("body"),
            wallet=row(self.rest("GET", f"wallets?id=eq.{self.seller}&select=balance", self.svc)),
        )

    def stock_and_sessions(self):
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

        def mk(i):
            return self.rest(
                "POST",
                "orders",
                self.bj,
                {
                    "buyer_id": self.buyer,
                    "seller_id": self.seller,
                    "product_id": pid,
                    "quantity": 1,
                    "status": "reserva_pendente",
                    "payment_method": "Seguro Fleaber",
                    "shipping_method": "hand",
                },
            )

        results = [mk(i) for i in range(2)]
        orders = [row(r) for r in results if row(r)]
        self.rec(
            "two_orders_stock1_sequential",
            pid=pid,
            https=[r["http"] for r in results],
            errs=[err(r) for r in results],
            n=len(orders),
            ids=[o.get("id") for o in orders],
        )
        sessions = []
        if len(orders) >= 2:

            def ck(oid):
                return self.edge(
                    "create-payment-intent",
                    self.bj,
                    {"buyer_id": self.buyer, "order_id": oid, "shipping_method": "hand"},
                )

            with ThreadPoolExecutor(max_workers=2) as ex:
                futs = [ex.submit(ck, orders[0]["id"]), ex.submit(ck, orders[1]["id"])]
                sessions = [f.result() for f in as_completed(futs)]
            self.rec(
                "two_checkout_sessions_stock1",
                https=[s["http"] for s in sessions],
                amounts=[
                    (s.get("body") or {}).get("amount_total") if isinstance(s.get("body"), dict) else None
                    for s in sessions
                ],
                urls=[
                    (s.get("body") or {}).get("checkoutUrl") or (s.get("body") or {}).get("url")
                    if isinstance(s.get("body"), dict)
                    else None
                    for s in sessions
                ],
                errs=[err(s) for s in sessions],
            )
        # concurrent inserts
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
        conc = []
        with ThreadPoolExecutor(max_workers=8) as ex:
            futs = [ex.submit(lambda i=i: mk_on(self, pid2, i)) for i in range(8)]
            conc = [f.result() for f in as_completed(futs)]
        created = [row(r) for r in conc if row(r)]
        self.rec(
            "eight_concurrent_orders_stock1",
            pid=pid2,
            created=len(created),
            https=[r["http"] for r in conc],
            errs=list({str(err(r))[:120] for r in conc}),
        )

    def live_capacity_repro(self):
        live = self.rest(
            "POST",
            "lives",
            self.svc,
            {
                "seller_id": self.seller,
                "vendedor_id": self.seller,
                "title": f"{TAG} lv",
                "status": "ended",
                "is_active": False,
            },
        )
        lid = (row(live) or {}).get("id")
        # discover live_items columns via empty insert error
        item = self.rest(
            "POST",
            "live_items",
            self.svc,
            {
                "live_id": lid,
                "seller_id": self.seller,
                "title": f"{TAG} li",
                "price": 4.0,
                "quantity": 1,
            },
        )
        iid = (row(item) or {}).get("id")
        if not iid:
            self.rec("live_item_insert_fail", http=item["http"], err=err(item), live=lid)
            return
        # seller two converted
        a = self.rest(
            "POST",
            "live_reservation_requests",
            self.sj,
            {
                "live_id": lid,
                "live_item_id": iid,
                "buyer_id": self.buyer,
                "seller_id": self.seller,
                "requested_qty": 1,
                "status": "converted",
                "external_display_name": f"{TAG}-a",
            },
        )
        b = self.rest(
            "POST",
            "live_reservation_requests",
            self.sj,
            {
                "live_id": lid,
                "live_item_id": iid,
                "buyer_id": self.buyer,
                "seller_id": self.seller,
                "requested_qty": 1,
                "status": "converted",
                "external_display_name": f"{TAG}-b",
            },
        )
        self.rec(
            "seller_two_converted_qty1",
            live_item=iid,
            a={"http": a["http"], "row": row(a), "err": err(a)},
            b={"http": b["http"], "row": row(b), "err": err(b)},
        )
        # buyer insert converted
        c = self.rest(
            "POST",
            "live_reservation_requests",
            self.bj,
            {
                "live_id": lid,
                "live_item_id": iid,
                "buyer_id": self.buyer,
                "seller_id": self.seller,
                "requested_qty": 1,
                "status": "converted",
            },
        )
        self.rec("buyer_insert_converted", http=c["http"], row=row(c), err=err(c))
        # race
        rs = []
        with ThreadPoolExecutor(max_workers=10) as ex:
            futs = [
                ex.submit(
                    self.rest,
                    "POST",
                    "live_reservation_requests",
                    self.sj,
                    {
                        "live_id": lid,
                        "live_item_id": iid,
                        "buyer_id": self.buyer,
                        "seller_id": self.seller,
                        "requested_qty": 1,
                        "status": "converted",
                        "external_display_name": f"{TAG}-r{i}-{uuid.uuid4().hex[:4]}",
                    },
                )
                for i in range(10)
            ]
            rs = [f.result() for f in as_completed(futs)]
        ok = [row(r) for r in rs if row(r) and str((row(r) or {}).get("status")).lower() in {"accepted", "converted"}]
        self.rec(
            "race_10_converted",
            ok=len(ok),
            https=[r["http"] for r in rs],
            errs=list({str(err(r))[:100] for r in rs}),
        )

    def rpc_inventory_service(self):
        spec = req(
            "GET",
            f"{self.base}/rest/v1/",
            {**self.H(self.svc), "Accept": "application/openapi+json"},
        )
        rpcs = []
        tables = []
        if isinstance(spec.get("body"), dict):
            for p in (spec["body"].get("paths") or {}):
                if p.startswith("/rpc/"):
                    rpcs.append(p[5:])
                elif p.startswith("/") and p.count("/") == 1:
                    tables.append(p[1:])
        sensitive = [n for n in rpcs if any(x in n for x in ("wallet", "payout", "refund", "credit", "debit", "admin", "raffle", "settle"))]
        self.rec(
            "openapi_service_role",
            http=spec["http"],
            n_tables=len(tables),
            n_rpcs=len(rpcs),
            sensitive_rpcs=sensitive,
            all_rpcs=rpcs,
        )
        # try execute a few extra
        extra = [
            "batata_debit_wallet_once",
            "batata_ensure_wallet",
            "batata_create_raffle_prize_order",
            "batata_award_live_raffle_tickets",
            "batata_ps_claim_pairing",
        ]
        for fn in extra:
            r = self.rpc(fn, self.bj, {})
            self.rec("rpc_extra_buyer", fn=fn, http=r["http"], err=str(err(r))[:160])

    def profiles_and_lives_keys(self):
        p = self.rest(
            "GET",
            f"profiles?id=eq.{self.buyer}&select=id,user_type,phone,email,phone_verified_at,nif,iban",
            self.bj,
        )
        p2 = self.rest(
            "PATCH",
            f"profiles?id=eq.{self.buyer}",
            self.bj,
            {"user_type": "administrador"},
        )
        after = row(self.rest("GET", f"profiles?id=eq.{self.buyer}&select=id,user_type", self.svc))
        lives = self.rest(
            "GET",
            "lives?select=id,seller_id,mux_stream_key,status&mux_stream_key=not.is.null&limit=5",
            self.bj,
        )
        lives_a = self.rest(
            "GET",
            "lives?select=id,mux_stream_key&mux_stream_key=not.is.null&limit=5",
            self.anon,
        )
        self.rec(
            "profiles_admin_and_stream_keys",
            buyer_profile_cols=list((row(p) or {}).keys()) if row(p) else p.get("body"),
            patch_admin_http=p2["http"],
            user_type_after=after,
            buyer_stream_keys=[
                {"id": x.get("id"), "has_key": bool(x.get("mux_stream_key"))}
                for x in (lives.get("body") or [])
                if isinstance(x, dict)
            ],
            anon_stream_keys_n=len(lives_a.get("body") or []) if isinstance(lives_a.get("body"), list) else lives_a,
            anon_any_key=any(
                isinstance(x, dict) and x.get("mux_stream_key") for x in (lives_a.get("body") or [])
            ),
        )

    def bag_and_qty(self):
        p1 = self.rest(
            "POST",
            "products",
            self.svc,
            {
                "seller_id": self.seller,
                "title": f"{TAG} bagA",
                "price": 5.0,
                "quantity": 3,
                "list_on_marketplace": True,
                "is_sold": False,
                "ref_code": f"{TAG}-ba",
            },
        )
        p2 = self.rest(
            "POST",
            "products",
            self.svc,
            {
                "seller_id": self.seller,
                "title": f"{TAG} bagB",
                "price": 7.0,
                "quantity": 3,
                "list_on_marketplace": True,
                "is_sold": False,
                "ref_code": f"{TAG}-bb",
            },
        )
        a = (row(p1) or {}).get("id")
        b = (row(p2) or {}).get("id")
        o1 = row(
            self.rest(
                "POST",
                "orders",
                self.bj,
                {
                    "buyer_id": self.buyer,
                    "seller_id": self.seller,
                    "product_id": a,
                    "quantity": 1,
                    "status": "reserva_pendente",
                    "payment_method": "Seguro Fleaber",
                    "shipping_method": "hand",
                },
            )
        )
        o2 = row(
            self.rest(
                "POST",
                "orders",
                self.bj,
                {
                    "buyer_id": self.buyer,
                    "seller_id": self.seller,
                    "product_id": b,
                    "quantity": 1,
                    "status": "reserva_pendente",
                    "payment_method": "Seguro Fleaber",
                    "shipping_method": "hand",
                },
            )
        )
        bag = self.edge(
            "create-payment-intent",
            self.bj,
            {
                "buyer_id": self.buyer,
                "bag_checkout": True,
                "shipping_method": "hand",
                "bag_lines": [
                    {
                        "order_id": o1["id"] if o1 else None,
                        "line_total_cents": 1,
                        "quantity": 9,
                        "seller_id": self.seller,
                    },
                    {
                        "order_id": o2["id"] if o2 else None,
                        "line_total_cents": 1,
                        "quantity": 9,
                    },
                ],
            },
        )
        amt = (bag.get("body") or {}).get("amount_total") if isinstance(bag.get("body"), dict) else None
        self.rec(
            "bag_client_line_totals_ignored",
            o1=o1,
            o2=o2,
            http=bag["http"],
            amount=amt,
            err=err(bag),
        )
        # qty 99 on insert
        q = self.rest(
            "POST",
            "orders",
            self.bj,
            {
                "buyer_id": self.buyer,
                "seller_id": self.seller,
                "product_id": a,
                "quantity": 99,
                "status": "reserva_pendente",
                "payment_method": "Seguro Fleaber",
                "shipping_method": "hand",
            },
        )
        self.rec("order_qty99_insert", http=q["http"], row=row(q), err=err(q))

    def refund_release_composition(self):
        # JWT refund + release on unpaid should no-op
        oid = None
        prod = self.rest(
            "POST",
            "products",
            self.svc,
            {
                "seller_id": self.seller,
                "title": f"{TAG} rr",
                "price": 9.0,
                "quantity": 1,
                "list_on_marketplace": True,
                "is_sold": False,
                "ref_code": f"{TAG}-rr",
            },
        )
        pid = (row(prod) or {}).get("id")
        o = row(
            self.rest(
                "POST",
                "orders",
                self.bj,
                {
                    "buyer_id": self.buyer,
                    "seller_id": self.seller,
                    "product_id": pid,
                    "quantity": 1,
                    "status": "reserva_pendente",
                    "payment_method": "Seguro Fleaber",
                    "shipping_method": "hand",
                },
            )
        )
        oid = (o or {}).get("id")
        ref = self.edge("refund-order", self.sj, {"order_id": oid})
        rel = self.rpc("batata_release_seller_wallet_for_order", self.bj, {"p_order_id": oid})
        rels = self.rpc("batata_release_seller_wallet_for_order", self.sj, {"p_order_id": oid})
        rfb = self.rpc("batata_refund_buyer_wallet_for_order", self.bj, {"p_order_id": oid})
        rfs = self.rpc("batata_refund_buyer_wallet_for_order", self.sj, {"p_order_id": oid})
        self.rec(
            "refund_release_unpaid",
            oid=oid,
            refund_edge=ref.get("body"),
            release_buyer=rel.get("body"),
            release_seller=rels.get("body"),
            refund_rpc_buyer=rfb.get("body"),
            refund_rpc_seller=rfs.get("body"),
        )

    def storage_and_tips_ps(self):
        buckets = req("GET", f"{self.base}/storage/v1/bucket", self.H(self.bj))
        names = []
        if isinstance(buckets.get("body"), list):
            names = [b.get("name") for b in buckets["body"] if isinstance(b, dict)]
        listed = {}
        for n in names[:10]:
            ls = req(
                "POST",
                f"{self.base}/storage/v1/object/list/{n}",
                self.H(self.bj),
                {"prefix": "", "limit": 5},
            )
            listed[n] = {"http": ls["http"], "n": len(ls.get("body") or []) if isinstance(ls.get("body"), list) else str(err(ls))[:80]}
        tip = self.edge(
            "create-live-tip-checkout",
            self.bj,
            {"seller_id": self.seller, "amount_eur": 5000, "live_id": str(uuid.uuid4())},
        )
        pair = self.edge("ps-pairing-claim", self.anon, {"code": "000000", "device_id": "x"})
        ingest = self.edge(
            "ingest-ocr-reservation",
            self.anon,
            {
                "live_id": str(uuid.uuid4()),
                "ocr_line_hash": "12345678xxxx",
                "detected_at": datetime.now(timezone.utc).isoformat(),
                "requested_qty": 9,
                "ref_slug": "A1",
            },
        )
        self.rec(
            "storage_tips_ps",
            buckets=names,
            listed=listed,
            tip_http=tip["http"],
            tip_err=err(tip),
            pair=pair.get("body"),
            ingest=ingest.get("body"),
        )


def mk_on(self, pid, i):
    return self.rest(
        "POST",
        "orders",
        self.bj,
        {
            "buyer_id": self.buyer,
            "seller_id": self.seller,
            "product_id": pid,
            "quantity": 1,
            "status": "reserva_pendente",
            "payment_method": "Seguro Fleaber",
            "shipping_method": "hand",
        },
    )


def main():
    c = C(load_env())
    c.verify_old_p0_order()
    c.reproduce_offplatform_wallet_twice()
    c.chat_and_dispute_scope()
    c.price_total_authority()
    c.payout_ledger_and_race()
    c.stock_and_sessions()
    c.live_capacity_repro()
    c.rpc_inventory_service()
    c.profiles_and_lives_keys()
    c.bag_and_qty()
    c.refund_release_composition()
    c.storage_and_tips_ps()
    c.out["frozen_at"] = datetime.now(timezone.utc).isoformat()
    OUT.write_text(json.dumps(c.out, indent=2, default=str), encoding="utf-8")
    print("WROTE", OUT)


if __name__ == "__main__":
    main()
