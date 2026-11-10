#!/usr/bin/env python3
"""ZIP 149.1 — prazo pagamento 48h + webhook replay idempotente + anti-delta."""
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
OUT = ROOT / "tool/reports/149.1-pay48-webhook-idempotent"
OUT.mkdir(parents=True, exist_ok=True)
TAG = "TESTE-ZIP1491"

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
    rec("AUTH", "PASS", {"buyer": buyer_id})

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
            """
          select key, enabled from public.fleaber_feature_flags
          where key like 'bundle_%' order by 1
        """
        )
        rec("FLAGS", "PASS", [dict(r) for r in cur.fetchall()])

        # cleanup
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

        def mk(title: str, price: float, qty: int = 3) -> str:
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
                raise RuntimeError(f"bundle insert {code} {rows}")
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
                    "p_delivery_point_ref": "PUDO-1491",
                },
            )
            if code >= 300 or not isinstance(q, dict) or not q.get("ok"):
                raise RuntimeError(f"confirm {code} {q}")
            return q

        # --- P1: pay_expires_at ≈ +48h ---
        p1, p2 = mk(f"{TAG} A", 5.0), mk(f"{TAG} B", 3.5)
        bid = mk_bundle([p1, p2])
        q = confirm(bid)
        cur.execute(
            """
          select status, pay_expires_at, quoted_at,
            extract(epoch from (pay_expires_at - quoted_at))/3600.0 as hours
          from public.product_bundles where id=%s::uuid
        """,
            (bid,),
        )
        row = dict(cur.fetchone())
        hours = float(row["hours"] or 0)
        ok_h = 47.0 <= hours <= 49.0 and row["status"] == "awaiting_payment"
        rec(
            "P1-pay-deadline-48h",
            "PASS" if ok_h else "FAIL",
            {
                "hours": hours,
                "pay_expires_at": str(row["pay_expires_at"]),
                "quote": {
                    k: q.get(k)
                    for k in (
                        "grand_total_cents",
                        "pay_expires_at",
                        "pay_deadline_hours",
                    )
                },
            },
        )
        if not ok_h:
            return 1

        # --- P2: expire payment window → begin blocked ---
        p3, p4 = mk(f"{TAG} C", 4.0), mk(f"{TAG} D", 4.0)
        bid2 = mk_bundle([p3, p4])
        confirm(bid2)
        cur.execute(
            """
          update public.product_bundles
          set pay_expires_at = timezone('utc', now()) - interval '1 minute'
          where id=%s::uuid
        """,
            (bid2,),
        )
        conn.commit()
        code, ex = rpc(buyer_jwt, "batata_bundle_touch_expiry", {"p_bundle_id": bid2})
        cur.execute(
            "select status, quote_invalidation_reason from public.product_bundles where id=%s::uuid",
            (bid2,),
        )
        st2 = dict(cur.fetchone())
        code_b, begin_b = rpc(
            buyer_jwt,
            "batata_bundle_checkout_begin",
            {
                "p_bundle_id": bid2,
                "p_client_idempotency_key": f"exp-{bid2}",
                "p_delivery": {"point_ref": "PUDO-1491"},
            },
        )
        blocked = st2["status"] == "expired" and (
            not (isinstance(begin_b, dict) and begin_b.get("ok"))
        )
        rec(
            "P2-pay-expired-blocks-begin",
            "PASS" if blocked else "FAIL",
            {"status": st2, "touch": ex, "begin": begin_b, "http": code_b},
        )
        if not blocked:
            return 1

        # --- P3: pay + webhook replay HTTP ---
        code, begin = rpc(
            buyer_jwt,
            "batata_bundle_checkout_begin",
            {
                "p_bundle_id": bid,
                "p_client_idempotency_key": f"pay-{bid}",
                "p_delivery": {
                    "delivery_point_ref": "PUDO-1491",
                    "point_ref": "PUDO-1491",
                },
            },
        )
        if code >= 300 or not isinstance(begin, dict) or not begin.get("ok"):
            rec("P3-webhook-replay", "FAIL", {"begin": begin})
            return 1
        attempt_id = begin["checkout_attempt_id"]
        total = int(begin["total_cents"])
        cur.execute(
            """
          select id, product_id, seller_id, quantity, price_total
          from public.orders where checkout_attempt_id=%s::uuid
        """,
            (attempt_id,),
        )
        bag_lines = []
        for r in cur.fetchall():
            rr = dict(r)
            bag_lines.append(
                {
                    "order_id": rr["id"],
                    "product_id": rr["product_id"],
                    "seller_id": rr["seller_id"],
                    "quantity": rr["quantity"],
                    "line_total_cents": int(round(float(rr["price_total"]) * 100)),
                    "item_label": "ZIP1491",
                }
            )
        cpi_body = {
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
        }
        c_code, cpi = z.http(
            "POST",
            f"{url}/functions/v1/create-payment-intent",
            {
                "apikey": anon,
                "Authorization": f"Bearer {buyer_jwt}",
                "Content-Type": "application/json",
            },
            cpi_body,
        )
        cs_id = (cpi or {}).get("checkoutSessionId") if isinstance(cpi, dict) else None
        checkout_url = (cpi or {}).get("checkoutUrl") if isinstance(cpi, dict) else None
        if c_code >= 300 or not cs_id:
            rec("P3-webhook-replay", "FAIL", {"cpi": cpi})
            return 1

        z.pay_checkout_session_sandbox(sk, cs_id)
        sess = z.stripe_session_with_pi(sk, cs_id)
        if sess.get("payment_status") != "paid" and checkout_url:
            z.pay_hosted_checkout_playwright(checkout_url)
            sess = z.stripe_session_with_pi(sk, cs_id)

        # wait paid
        for _ in range(15):
            sess = z.stripe_session_with_pi(sk, cs_id)
            if sess.get("payment_status") == "paid":
                break
            time.sleep(2)

        wh_obj = {k: v for k, v in sess.items() if not str(k).startswith("_")}
        if isinstance(wh_obj.get("payment_intent"), dict):
            wh_obj["payment_intent"] = wh_obj["payment_intent"].get("id")
        event = {
            "id": f"evt_test_zip1491_{uuid.uuid4().hex[:10]}",
            "object": "event",
            "api_version": "2024-06-20",
            "created": int(time.time()),
            "type": "checkout.session.completed",
            "data": {"object": wh_obj},
            "livemode": False,
        }
        payload = json.dumps(event).encode()
        sig = z.sign_stripe_webhook(payload, whsec)
        wh1 = z.http(
            "POST",
            f"{url}/functions/v1/stripe-webhook",
            {"Content-Type": "application/json", "Stripe-Signature": sig},
            raw=payload,
        )
        # settle via GET too
        z.http(
            "GET",
            f"{url}/functions/v1/create-payment-intent?checkout_return=success&session_id={cs_id}",
            {"apikey": anon, "Authorization": f"Bearer {buyer_jwt}"},
        )
        time.sleep(1)
        # identical replay (new event id, same session)
        event2 = dict(event)
        event2["id"] = f"evt_test_zip1491_replay_{uuid.uuid4().hex[:8]}"
        payload2 = json.dumps(event2).encode()
        sig2 = z.sign_stripe_webhook(payload2, whsec)
        wh2 = z.http(
            "POST",
            f"{url}/functions/v1/stripe-webhook",
            {"Content-Type": "application/json", "Stripe-Signature": sig2},
            raw=payload2,
        )
        # third: exact same payload/signature path again
        wh3 = z.http(
            "POST",
            f"{url}/functions/v1/stripe-webhook",
            {"Content-Type": "application/json", "Stripe-Signature": sig2},
            raw=payload2,
        )

        cur.execute(
            """
          select status, amount_paid_cents from public.orders
          where checkout_attempt_id=%s::uuid
        """,
            (attempt_id,),
        )
        orows = [dict(r) for r in cur.fetchall()]
        paid_n = sum(1 for r in orows if r["status"] == "pago")
        cur.execute(
            "select status from public.product_bundles where id=%s::uuid", (bid,)
        )
        bst = dict(cur.fetchone())["status"]
        if bst != "purchased" and paid_n >= 2:
            cur.execute(
                "select public.batata_bundle_mark_purchased(%s::uuid) as j", (bid,)
            )
            cur.execute(
                "select status from public.product_bundles where id=%s::uuid", (bid,)
            )
            bst = dict(cur.fetchone())["status"]

        replay_ok = (
            wh1[0] in (200, 303)
            and wh2[0] in (200, 303)
            and wh3[0] in (200, 303)
            and paid_n == 2
            and len(orows) == 2
        )
        rec(
            "P3-webhook-replay",
            "PASS" if replay_ok else "FAIL",
            {
                "wh1": wh1[0],
                "wh2": {"http": wh2[0], "body": wh2[1]},
                "wh3": {"http": wh3[0], "body": wh3[1]},
                "paid_n": paid_n,
                "orders": orows,
                "bundle": bst,
                "session": cs_id,
            },
        )
        if not replay_ok:
            return 1

        # --- P4: shipping_delta blocked with flags ON ---
        cur.execute(
            """
          update public.fleaber_feature_flags set enabled=true
          where key in ('order_weight_confirm_enabled','order_shipping_delta_enabled')
        """
        )
        conn.commit()
        cur.execute(
            """
          select id from public.orders
          where checkout_attempt_id=%s::uuid limit 1
        """,
            (attempt_id,),
        )
        oid = dict(cur.fetchone())["id"]
        # ensure rule_version
        cur.execute(
            "select rule_version from public.product_bundles where id=%s::uuid",
            (bid,),
        )
        br = dict(cur.fetchone())
        cur.execute(
            "select bundle_id from public.orders where id=%s::uuid",
            (oid,),
        )
        ord_bundle = dict(cur.fetchone()).get("bundle_id")
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
        no_delta = isinstance(delta, dict) and delta.get("result") == "bundle_prequoted_no_delta"
        cur.execute(
            "select count(*) as n from public.order_shipping_adjustments where order_id=%s::uuid and status='pending'",
            (oid,),
        )
        pending_adj = dict(cur.fetchone())["n"]
        rec(
            "P4-no-shipping-delta-bundle",
            "PASS" if no_delta and pending_adj == 0 else "FAIL",
            {
                "delta": delta,
                "http": code_d,
                "pending_adj": pending_adj,
                "rule_version": br.get("rule_version"),
                "order_bundle_id": ord_bundle,
            },
        )
        if not (no_delta and pending_adj == 0):
            return 1

        # non-bundle still can request delta when flags ON (sanity)
        p5 = mk(f"{TAG} single-delta", 8.5, qty=2)
        code, sbegin = rpc(
            buyer_jwt,
            "batata_commerce_checkout_begin",
            {
                "p_lines": [{"product_id": p5, "quantity": 1}],
                "p_shipping_method": "Envio Transportadora (DPD)",
                "p_payment_rail": "stripe",
                "p_delivery": {
                    "point_ref": "PUDO-1491S",
                    "delivery_point_ref": "PUDO-1491S",
                    "shipping_modality": "shop_to_shop",
                    "shipping_weight_band": "0_3",
                    "shipping_weight_kg": 2.0,
                    "use_delivery_weight": True,
                },
                "p_client_idempotency_key": f"single-{uuid.uuid4().hex[:8]}",
                "p_confirm_remainder": True,
            },
        )
        # Mark order pago artificially for weight confirm path (isolated)
        if isinstance(sbegin, dict) and sbegin.get("ok"):
            oids = sbegin.get("order_ids") or []
            if isinstance(oids, str):
                oids = json.loads(oids)
            if oids:
                cur.execute(
                    """
                  update public.orders set
                    status='pago',
                    shipping_weight_charged_band='0_3',
                    shipping_weight_band='0_3',
                    shipping_modality='shop_to_shop',
                    shipping_cents_charged=299,
                    weight_confirm_status='pending'
                  where id=%s::uuid
                """,
                    (oids[0],),
                )
                conn.commit()
                code_nd, delta_nd = rpc(
                    seller_jwt,
                    "batata_seller_confirm_shipping_weight",
                    {
                        "p_order_id": oids[0],
                        "p_actual_kg": 5.0,
                        "p_actual_band": "3_6",
                        "p_action": "request_delta",
                    },
                )
                other_ok = isinstance(delta_nd, dict) and delta_nd.get("result") == "delta_requested"
                rec(
                    "P5-shipping-delta-non-bundle-ok",
                    "PASS" if other_ok else "FAIL",
                    {"delta": delta_nd, "http": code_nd},
                )
            else:
                rec("P5-shipping-delta-non-bundle-ok", "FAIL", {"begin": sbegin})
        else:
            rec("P5-shipping-delta-non-bundle-ok", "FAIL", {"begin": sbegin})

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
                'order_weight_confirm_enabled',
                'order_shipping_delta_enabled',
                'order_ship_deadline_enabled',
                'order_ship_deadline_autocancel_enabled'
              )
            """
            )
            conn.commit()
        except Exception:
            pass
        summary = {
            "PASS": sum(1 for r in results if r["status"] == "PASS"),
            "FAIL": sum(1 for r in results if r["status"] == "FAIL"),
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
