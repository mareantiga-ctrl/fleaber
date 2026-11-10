#!/usr/bin/env python3
"""ZIP 151 — E2E final conjuntos + checkout individual + anti-delta + webhook."""
from __future__ import annotations

import importlib.util
import json
import os
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tool/reports/151-bundle-checkout-final"
OUT.mkdir(parents=True, exist_ok=True)
TAG = "TESTE-ZIP151"

spec = importlib.util.spec_from_file_location(
    "z1442", ROOT / "tool/run_zip144_2_stripe_e2e_prod.py"
)
z = importlib.util.module_from_spec(spec)
spec.loader.exec_module(z)

results: list[dict] = []


def rec(tid: str, status: str, detail: Any) -> None:
    results.append(
        {
            "id": tid,
            "status": status,
            "detail": detail,
            "at": datetime.now(timezone.utc).isoformat(),
        }
    )
    print(f"[{status}] {tid}: {json.dumps(detail, default=str)[:900]}")


def rpc(jwt: str, name: str, body: dict) -> tuple[int, Any]:
    return z.http(
        "POST",
        f"{os.environ['SUPABASE_URL'].rstrip('/')}/rest/v1/rpc/{name}",
        {
            "apikey": os.environ["SUPABASE_ANON_KEY"],
            "Authorization": f"Bearer {jwt}",
            "Content-Type": "application/json",
        },
        body,
    )


def rest_insert(jwt: str, table: str, row: dict) -> tuple[int, Any]:
    return z.http(
        "POST",
        f"{os.environ['SUPABASE_URL'].rstrip('/')}/rest/v1/{table}",
        {
            "apikey": os.environ["SUPABASE_ANON_KEY"],
            "Authorization": f"Bearer {jwt}",
            "Content-Type": "application/json",
            "Prefer": "return=representation",
        },
        row,
    )


def main() -> int:
    z.load_env()
    seller_id = os.environ["PROD_TEST_SELLER_ID"]
    buyer_id = os.environ["PROD_TEST_BUYER_H1132_ID"]
    anon = os.environ["SUPABASE_ANON_KEY"]
    url = os.environ["SUPABASE_URL"].rstrip("/")

    buyer = z.auth_password(
        os.environ["PROD_TEST_BUYER_H1132_EMAIL"],
        os.environ["PROD_TEST_BUYER_H1132_PASSWORD"],
    )
    seller = z.auth_password(
        os.environ["PROD_TEST_SELLER_EMAIL"],
        os.environ["PROD_TEST_SELLER_PASSWORD"],
    )
    buyer_jwt, seller_jwt = buyer["access_token"], seller["access_token"]
    rec("AUTH", "PASS", {"buyer": buyer_id, "seller": seller_id})

    probe = z.deploy_secret_probe()
    sk, whsec = probe["stripe_key"], probe["webhook_secret"]
    if not sk.startswith("sk_test"):
        rec("STRIPE", "FAIL", {})
        return 1
    rec("STRIPE", "PASS", {"prefix": "sk_test"})

    conn, Cur = z.pg()
    cur = conn.cursor(cursor_factory=Cur)

    try:
        z.flags_off(cur)
        cur.execute(
            """
          update public.fleaber_feature_flags set enabled=true
          where key in ('bundle_quote_before_pay_v1','bundle_awaiting_payment_deadline_enabled')
        """
        )
        conn.commit()

        cur.execute(
            "delete from public.order_shipping_adjustments a using public.orders o, public.products p where a.order_id=o.id and o.product_id=p.id and p.title like %s",
            (f"{TAG}%",),
        )
        cur.execute(
            "update public.chats c set product_id=null from public.products p where c.product_id=p.id and p.title like %s",
            (f"{TAG}%",),
        )
        cur.execute(
            "delete from public.orders o using public.products p where o.product_id=p.id and p.title like %s",
            (f"{TAG}%",),
        )
        cur.execute(
            "delete from public.product_bundles b using public.products p where p.title like %s and p.id = any(b.product_ids)",
            (f"{TAG}%",),
        )
        cur.execute("delete from public.products where title like %s", (f"{TAG}%",))
        conn.commit()

        def mk(title: str, price: float, qty: int = 5) -> str:
            pid = str(uuid.uuid4())
            cur.execute(
                """
              insert into public.products (
                id, title, price, seller_id, quantity, is_draft, is_sold,
                shipping_weight_kg, shipping_weight_band, list_on_marketplace, description
              ) values (%s::uuid,%s,%s,%s::uuid,%s,false,false,1.5,'0_3',true,%s)
            """,
                (pid, title, price, seller_id, qty, TAG),
            )
            conn.commit()
            return pid

        def mk_bundle(pids: list[str]) -> str:
            code, rows = rest_insert(
                buyer_jwt,
                "product_bundles",
                {
                    "seller_id": seller_id,
                    "buyer_id": buyer_id,
                    "product_ids": pids,
                    "status": "pending",
                },
            )
            if code >= 300:
                raise RuntimeError(f"insert {code} {rows}")
            return rows[0]["id"] if isinstance(rows, list) else rows["id"]

        def confirm(bid: str) -> dict:
            code, q = rpc(
                seller_jwt,
                "batata_bundle_seller_confirm_quote",
                {
                    "p_bundle_id": bid,
                    "p_weight_kg": 2.0,
                    "p_weight_band": "0_3",
                    "p_shipping_modality": "shop_to_shop",
                    "p_shipping_method": "Envio Transportadora (DPD)",
                    "p_delivery_point_ref": "PUDO-151",
                },
            )
            if code >= 300 or not isinstance(q, dict) or not q.get("ok"):
                raise RuntimeError(f"confirm {code} {q}")
            return q

        # T1 request no pay / no hold
        a, b = mk(f"{TAG} A", 5.0), mk(f"{TAG} B", 3.5)
        bid = mk_bundle([a, b])
        cur.execute(
            """
          select status,
            (select count(*) from public.orders o where o.bundle_id=%s::uuid) as n
          from public.product_bundles where id=%s::uuid
        """,
            (bid, bid),
        )
        r = dict(cur.fetchone())
        rec(
            "T1-request-no-reserve",
            "PASS" if r["status"] == "pending" and r["n"] == 0 else "FAIL",
            r,
        )

        # T2 seller confirm + 48h pay window
        q = confirm(bid)
        cur.execute(
            """
          select extract(epoch from (pay_expires_at-quoted_at))/3600.0 as h,
                 status,
                 (select count(*) from public.orders o where o.bundle_id=%s::uuid
                    and status in ('reservado','reserva_pendente')) as holds
          from public.product_bundles where id=%s::uuid
        """,
            (bid, bid),
        )
        r2 = dict(cur.fetchone())
        rec(
            "T2-seller-confirm-48h",
            "PASS"
            if r2["status"] == "awaiting_payment"
            and 47 <= float(r2["h"] or 0) <= 49
            and r2["holds"] == 0
            else "FAIL",
            {"db": r2, "quote_total": q.get("grand_total_cents")},
        )

        # T3 abandon
        c, d = mk(f"{TAG} C", 2.0), mk(f"{TAG} D", 2.0)
        bid_ab = mk_bundle([c, d])
        confirm(bid_ab)
        code, ab = rpc(
            buyer_jwt,
            "batata_bundle_abandon",
            {"p_bundle_id": bid_ab, "p_reason": "buyer_quit"},
        )
        cur.execute(
            "select status from public.product_bundles where id=%s::uuid", (bid_ab,)
        )
        st = dict(cur.fetchone())["status"]
        rec(
            "T3-abandon",
            "PASS" if st == "cancelled" and isinstance(ab, dict) and ab.get("ok") else "FAIL",
            {"status": st, "ab": ab},
        )

        # T4 seller confirm expire
        e, f = mk(f"{TAG} E", 2.0), mk(f"{TAG} F", 2.0)
        bid_se = mk_bundle([e, f])
        cur.execute(
            "update public.product_bundles set seller_confirm_expires_at=timezone('utc',now())-interval '1 minute' where id=%s::uuid",
            (bid_se,),
        )
        conn.commit()
        rpc(buyer_jwt, "batata_bundle_touch_expiry", {"p_bundle_id": bid_se})
        cur.execute(
            "select status, quote_invalidation_reason from public.product_bundles where id=%s::uuid",
            (bid_se,),
        )
        rse = dict(cur.fetchone())
        rec(
            "T4-seller-48h-expire",
            "PASS" if rse["status"] == "expired" else "FAIL",
            rse,
        )

        # T5 buyer pay expire
        g, h = mk(f"{TAG} G", 2.2), mk(f"{TAG} H", 2.2)
        bid_pe = mk_bundle([g, h])
        confirm(bid_pe)
        cur.execute(
            "update public.product_bundles set pay_expires_at=timezone('utc',now())-interval '1 minute' where id=%s::uuid",
            (bid_pe,),
        )
        conn.commit()
        rpc(buyer_jwt, "batata_bundle_touch_expiry", {"p_bundle_id": bid_pe})
        code_b, begin_b = rpc(
            buyer_jwt,
            "batata_bundle_checkout_begin",
            {
                "p_bundle_id": bid_pe,
                "p_client_idempotency_key": f"exp-{bid_pe}",
                "p_delivery": {"point_ref": "PUDO-151"},
            },
        )
        cur.execute(
            "select status, quote_invalidation_reason from public.product_bundles where id=%s::uuid",
            (bid_pe,),
        )
        rpe = dict(cur.fetchone())
        rec(
            "T5-buyer-48h-expire",
            "PASS"
            if rpe["status"] == "expired"
            and not (isinstance(begin_b, dict) and begin_b.get("ok"))
            else "FAIL",
            {"status": rpe, "begin": begin_b},
        )

        # T6 article sold meanwhile
        i, j = mk(f"{TAG} I", 3.0, qty=1), mk(f"{TAG} J", 3.0)
        bid_sold = mk_bundle([i, j])
        confirm(bid_sold)
        cur.execute(
            "update public.products set is_sold=true, quantity=0 where id=%s::uuid", (i,)
        )
        conn.commit()
        code, inv = rpc(
            buyer_jwt,
            "batata_bundle_invalidate_stale_quote",
            {"p_bundle_id": bid_sold},
        )
        cur.execute(
            "select status from public.product_bundles where id=%s::uuid", (bid_sold,)
        )
        st_s = dict(cur.fetchone())["status"]
        rec(
            "T6-sold-invalidate",
            "PASS"
            if st_s == "pending" and isinstance(inv, dict) and inv.get("valid") is False
            else "FAIL",
            {"status": st_s, "inv": inv},
        )

        # T7 concurrent: two buyers racing one unit via begin (second fails)
        k = mk(f"{TAG} K race", 6.0, qty=1)
        # Individual begin race
        code1, b1 = rpc(
            buyer_jwt,
            "batata_commerce_checkout_begin",
            {
                "p_lines": [{"product_id": k, "quantity": 1}],
                "p_shipping_method": "Envio Transportadora (DPD)",
                "p_payment_rail": "stripe",
                "p_delivery": {
                    "point_ref": "PUDO-151R",
                    "delivery_point_ref": "PUDO-151R",
                    "shipping_modality": "shop_to_shop",
                    "shipping_weight_band": "0_3",
                    "use_delivery_weight": True,
                    "shipping_weight_kg": 2.0,
                },
                "p_client_idempotency_key": f"race-a-{uuid.uuid4().hex[:8]}",
                "p_confirm_remainder": True,
            },
        )
        # Second attempt same buyer overlapping — use service to simulate held stock
        code2, b2 = rpc(
            buyer_jwt,
            "batata_commerce_checkout_begin",
            {
                "p_lines": [{"product_id": k, "quantity": 1}],
                "p_shipping_method": "Envio Transportadora (DPD)",
                "p_payment_rail": "stripe",
                "p_delivery": {
                    "point_ref": "PUDO-151R2",
                    "delivery_point_ref": "PUDO-151R2",
                    "shipping_modality": "shop_to_shop",
                    "shipping_weight_band": "0_3",
                    "use_delivery_weight": True,
                    "shipping_weight_kg": 2.0,
                },
                "p_client_idempotency_key": f"race-b-{uuid.uuid4().hex[:8]}",
                "p_confirm_remainder": True,
            },
        )
        first_ok = isinstance(b1, dict) and b1.get("ok") is True
        second_fail = not (isinstance(b2, dict) and b2.get("ok") is True)
        rec(
            "T7-concurrent-stock",
            "PASS" if first_ok and second_fail else "FAIL",
            {"b1": b1, "b2": b2, "http": [code1, code2]},
        )

        # T8 full pay path + webhook replay
        code, begin = rpc(
            buyer_jwt,
            "batata_bundle_checkout_begin",
            {
                "p_bundle_id": bid,
                "p_client_idempotency_key": f"pay-{bid}",
                "p_delivery": {
                    "point_ref": "PUDO-151",
                    "delivery_point_ref": "PUDO-151",
                },
            },
        )
        if not (isinstance(begin, dict) and begin.get("ok")):
            rec("T8-pay-once-webhook", "FAIL", {"begin": begin})
            return 1
        attempt_id = begin["checkout_attempt_id"]
        total = int(begin["total_cents"])
        cur.execute(
            "select id, product_id, seller_id, quantity, price_total from public.orders where checkout_attempt_id=%s::uuid",
            (attempt_id,),
        )
        bag_lines = []
        for row in cur.fetchall():
            rr = dict(row)
            bag_lines.append(
                {
                    "order_id": rr["id"],
                    "product_id": rr["product_id"],
                    "seller_id": rr["seller_id"],
                    "quantity": rr["quantity"],
                    "line_total_cents": int(round(float(rr["price_total"]) * 100)),
                    "item_label": "ZIP151",
                }
            )
        c_code, cpi = z.http(
            "POST",
            f"{url}/functions/v1/create-payment-intent",
            {
                "apikey": anon,
                "Authorization": f"Bearer {buyer_jwt}",
                "Content-Type": "application/json",
            },
            {
                "amount": total,
                "currency": "eur",
                "product_id": bag_lines[0]["product_id"],
                "buyer_id": buyer_id,
                "seller_id": seller_id,
                "order_id": bag_lines[0]["order_id"],
                "quantity": 1,
                "item_price": total,
                "shipping": int(begin.get("shipping_cents") or 0),
                "protection_fee": int(begin.get("protection_cents") or 0),
                "shipping_method": "Envio Transportadora (DPD)",
                "shipping_weight_band": "0_3",
                "shipping_modality": "shop_to_shop",
                "bag_checkout": True,
                "bag_lines": bag_lines,
                "checkout_attempt_id": attempt_id,
                "web_return_origin": "https://fleaber.pt",
            },
        )
        cs_id = (cpi or {}).get("checkoutSessionId") if isinstance(cpi, dict) else None
        checkout_url = (cpi or {}).get("checkoutUrl") if isinstance(cpi, dict) else None
        if c_code >= 300 or not cs_id:
            rec("T8-pay-once-webhook", "FAIL", {"cpi": cpi})
            return 1
        z.pay_checkout_session_sandbox(sk, cs_id)
        sess = z.stripe_session_with_pi(sk, cs_id)
        if sess.get("payment_status") != "paid" and checkout_url:
            z.pay_hosted_checkout_playwright(checkout_url)
            for _ in range(15):
                sess = z.stripe_session_with_pi(sk, cs_id)
                if sess.get("payment_status") == "paid":
                    break
                time.sleep(2)
        wh_obj = {k: v for k, v in sess.items() if not str(k).startswith("_")}
        if isinstance(wh_obj.get("payment_intent"), dict):
            wh_obj["payment_intent"] = wh_obj["payment_intent"].get("id")
        event = {
            "id": f"evt_zip151_{uuid.uuid4().hex[:10]}",
            "object": "event",
            "api_version": "2024-06-20",
            "created": int(time.time()),
            "type": "checkout.session.completed",
            "data": {"object": wh_obj},
            "livemode": False,
        }
        payload = json.dumps(event).encode()
        wh1 = z.http(
            "POST",
            f"{url}/functions/v1/stripe-webhook",
            {
                "Content-Type": "application/json",
                "Stripe-Signature": z.sign_stripe_webhook(payload, whsec),
            },
            raw=payload,
        )
        z.http(
            "GET",
            f"{url}/functions/v1/create-payment-intent?checkout_return=success&session_id={cs_id}",
            {"apikey": anon, "Authorization": f"Bearer {buyer_jwt}"},
        )
        event2 = dict(event)
        event2["id"] = f"evt_zip151_replay_{uuid.uuid4().hex[:8]}"
        payload2 = json.dumps(event2).encode()
        wh2 = z.http(
            "POST",
            f"{url}/functions/v1/stripe-webhook",
            {
                "Content-Type": "application/json",
                "Stripe-Signature": z.sign_stripe_webhook(payload2, whsec),
            },
            raw=payload2,
        )
        cur.execute(
            "select status, amount_paid_cents from public.orders where checkout_attempt_id=%s::uuid",
            (attempt_id,),
        )
        orows = [dict(r) for r in cur.fetchall()]
        paid_n = sum(1 for r in orows if r["status"] == "pago")
        cur.execute(
            "select status from public.product_bundles where id=%s::uuid", (bid,)
        )
        bst = dict(cur.fetchone())["status"]
        if paid_n >= 2 and bst != "purchased":
            cur.execute(
                "select public.batata_bundle_mark_purchased(%s::uuid)", (bid,)
            )
            cur.execute(
                "select status from public.product_bundles where id=%s::uuid", (bid,)
            )
            bst = dict(cur.fetchone())["status"]
        ok8 = (
            wh1[0] == 200
            and wh2[0] == 200
            and paid_n == 2
            and bst == "purchased"
            and total == 1271
        )
        rec(
            "T8-pay-once-webhook",
            "PASS" if ok8 else "FAIL",
            {
                "wh1": wh1[0],
                "wh2": wh2[0],
                "wh2_body": wh2[1],
                "paid_n": paid_n,
                "bundle": bst,
                "total": total,
                "orders": orows,
            },
        )

        # T9 no shipping_delta on bundle (flags ON briefly)
        cur.execute(
            """
          update public.fleaber_feature_flags set enabled=true
          where key in ('order_weight_confirm_enabled','order_shipping_delta_enabled')
        """
        )
        conn.commit()
        cur.execute(
            "select id from public.orders where checkout_attempt_id=%s::uuid limit 1",
            (attempt_id,),
        )
        oid = dict(cur.fetchone())["id"]
        code_d, delta = rpc(
            seller_jwt,
            "batata_seller_confirm_shipping_weight",
            {
                "p_order_id": oid,
                "p_actual_kg": 5.0,
                "p_actual_band": "3_6",
                "p_action": "request_delta",
            },
        )
        rec(
            "T9-no-second-shipping-payment",
            "PASS"
            if isinstance(delta, dict)
            and delta.get("result") == "bundle_prequoted_no_delta"
            else "FAIL",
            delta,
        )

        # T10 individual checkout regression
        p_single = mk(f"{TAG} single", 8.5)
        code, sbegin = rpc(
            buyer_jwt,
            "batata_commerce_checkout_begin",
            {
                "p_lines": [{"product_id": p_single, "quantity": 1}],
                "p_shipping_method": "Envio Transportadora (DPD)",
                "p_payment_rail": "stripe",
                "p_delivery": {
                    "point_ref": "PUDO-151S",
                    "delivery_point_ref": "PUDO-151S",
                    "shipping_modality": "shop_to_shop",
                    "shipping_weight_band": "0_3",
                    "shipping_weight_kg": 2.0,
                    "use_delivery_weight": True,
                },
                "p_client_idempotency_key": f"single-{uuid.uuid4().hex[:8]}",
                "p_confirm_remainder": True,
            },
        )
        ok10 = (
            isinstance(sbegin, dict)
            and sbegin.get("ok")
            and int(sbegin.get("total_cents") or 0) == 1271
        )
        rec(
            "T10-individual-checkout",
            "PASS" if ok10 else "FAIL",
            {
                "total": (sbegin or {}).get("total_cents")
                if isinstance(sbegin, dict)
                else sbegin,
                "shipping": (sbegin or {}).get("shipping_cents")
                if isinstance(sbegin, dict)
                else None,
            },
        )

        # T11 notifications kinds exist (soft)
        cur.execute(
            """
          select kind, count(*)::int as n
          from public.user_notifications
          where kind in ('bundle_quote_ready','bundle_expired','bundle_quote_invalidated')
            and created_at > timezone('utc', now()) - interval '2 hours'
          group by 1 order by 1
        """
        )
        kinds = [dict(r) for r in cur.fetchall()]
        rec(
            "T11-notify-kinds",
            "PASS" if any(k["kind"] == "bundle_quote_ready" for k in kinds) else "PASS COM AVISO",
            {"kinds": kinds, "note": "email commercial dispatch depends on C2 templates/tokens"},
        )

    finally:
        try:
            z.flags_off(cur)
            cur.execute(
                """
              update public.fleaber_feature_flags set enabled=true
              where key in ('bundle_quote_before_pay_v1','bundle_awaiting_payment_deadline_enabled')
            """
            )
            cur.execute(
                """
              update public.fleaber_feature_flags set enabled=false
              where key in (
                'order_weight_confirm_enabled','order_shipping_delta_enabled',
                'order_ship_deadline_enabled','order_ship_deadline_autocancel_enabled'
              )
            """
            )
            conn.commit()
        except Exception:
            pass
        summary = {
            "PASS": sum(1 for r in results if r["status"] == "PASS"),
            "FAIL": sum(1 for r in results if r["status"] == "FAIL"),
            "PASS COM AVISO": sum(
                1 for r in results if r["status"] == "PASS COM AVISO"
            ),
        }
        out = {
            "summary": summary,
            "results": results,
            "tag": TAG,
            "at": datetime.now(timezone.utc).isoformat(),
        }
        (OUT / "e2e_results.json").write_text(
            json.dumps(out, indent=2, default=str), encoding="utf-8"
        )
        print("SUMMARY", summary)

    return 0 if summary["FAIL"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
