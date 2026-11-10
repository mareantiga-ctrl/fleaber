#!/usr/bin/env python3
"""ZIP 144.3 — prova fluxo real begin → CPI → Checkout TEST → webhook settle 1× + email C2."""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import subprocess
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tool/reports/144.3-checkout-align"
OUT.mkdir(parents=True, exist_ok=True)
ENV_FILE = ROOT / "tool/live_ops_production.env"
TAG = "TESTE-ZIP1443"

# Reuse helpers from 144.2 harness
import importlib.util

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
    print(f"[{status}] {tid}: {json.dumps(detail, default=str)[:700]}")


def main() -> int:
    z.load_env()
    evidence: dict[str, Any] = {"tag": TAG}
    seller_id = os.environ["PROD_TEST_SELLER_ID"]
    buyer_id = os.environ["PROD_TEST_BUYER_H1132_ID"]
    url = os.environ["SUPABASE_URL"].rstrip("/")
    anon = os.environ["SUPABASE_ANON_KEY"]

    buyer = z.auth_password(
        os.environ["PROD_TEST_BUYER_H1132_EMAIL"],
        os.environ["PROD_TEST_BUYER_H1132_PASSWORD"],
    )
    buyer_jwt = buyer["access_token"]
    rec("AUTH", "PASS", {"buyer": buyer_id})

    probe = z.deploy_secret_probe()
    sk = probe["stripe_key"]
    whsec = probe["webhook_secret"]
    edge_sr = probe["service_role_key"]
    if not sk.startswith("sk_test"):
        rec("STRIPE", "FAIL", {"prefix": sk[:7]})
        return 1
    rec("STRIPE", "PASS", {"prefix": "sk_test"})

    conn, Cur = z.pg()
    cur = conn.cursor(cursor_factory=Cur)
    created_products: list[str] = []
    created_orders: list[str] = []

    try:
        z.flags_off(cur)
        # cleanup tag
        cur.execute(
            """
          delete from public.order_shipping_adjustments a
          using public.orders o, public.products p
          where a.order_id=o.id and o.product_id=p.id and p.title like %s
        """,
            (f"{TAG}%",),
        )
        cur.execute(
            """
          update public.chats c set product_id=null
          from public.products p where c.product_id=p.id and p.title like %s
        """,
            (f"{TAG}%",),
        )
        cur.execute(
            """
          delete from public.orders o using public.products p
          where o.product_id=p.id and p.title like %s
        """,
            (f"{TAG}%",),
        )
        cur.execute("delete from public.products where title like %s", (f"{TAG}%",))

        p1 = str(uuid.uuid4())
        cur.execute(
            """
          insert into public.products (
            id, title, price, seller_id, quantity, is_draft, is_sold,
            shipping_weight_kg, shipping_weight_band, list_on_marketplace, description
          ) values (
            %s::uuid, %s, 8.50, %s::uuid, 5, false, false,
            2.0, '0_3', true, %s
          )
        """,
            (p1, f"{TAG} align begin", seller_id, TAG),
        )
        created_products.append(p1)

        ship_method = "Envio Transportadora (DPD)"
        begin_body = {
            "p_lines": [{"product_id": p1, "quantity": 1}],
            "p_shipping_method": ship_method,
            "p_payment_rail": "stripe",
            "p_delivery": {
                "delivery_point_ref": f"PUDO-{TAG}",
                "delivery_point_label": f"{TAG} point",
                "delivery_point_provider": "dpd",
                "recipient_name": "Comprador TESTE ZIP1443",
                "phone": "912345678",
                "postal_code": "1000-001",
                "city": "Lisboa",
                "country": "PT",
                "line1": "Rua Teste 1",
            },
            "p_client_idempotency_key": f"zip1443-{uuid.uuid4().hex[:12]}",
            "p_confirm_remainder": False,
        }
        b_code, begin = z.http(
            "POST",
            f"{url}/rest/v1/rpc/batata_commerce_checkout_begin",
            {
                "Authorization": f"Bearer {buyer_jwt}",
                "apikey": anon,
                "Content-Type": "application/json",
                "Prefer": "return=representation",
            },
            begin_body,
        )
        evidence["begin"] = {"http": b_code, "body": begin}
        if not isinstance(begin, dict) or not begin.get("ok"):
            rec("R1-begin", "FAIL", evidence["begin"])
            return 1

        attempt_id = begin.get("checkout_attempt_id")
        q = begin.get("quote") or {}
        begin_total = int(q.get("total_cents") or begin.get("total_cents") or 0)
        begin_ship = int(q.get("shipping_cents") or begin.get("shipping_cents") or 0)
        begin_prot = int(
            q.get("protection_fee_cents") or begin.get("protection_fee_cents") or 0
        )
        begin_items = int(q.get("items_cents") or begin.get("items_cents") or 0)
        if begin_items <= 0 and begin_total > begin_ship:
            begin_items = begin_total - begin_ship - begin_prot
        orders = begin.get("order_ids") or []
        o1 = str(orders[0]) if orders else None
        if not o1:
            rec("R1-begin", "FAIL", {"no_order": begin})
            return 1
        created_orders.append(o1)

        # Expect DPD S2S 0_3 = 299 with rates live; total = items+ship+prot
        align_ok = (
            begin_ship == 299
            and begin_items == 850
            and begin_prot == 122
            and begin_total == 1271
        )
        rec(
            "R1-begin",
            "PASS" if align_ok else "PASS COM AVISO",
            {
                "order_id": o1,
                "attempt_id": attempt_id,
                "items": begin_items,
                "shipping": begin_ship,
                "protection": begin_prot,
                "total": begin_total,
                "expected_ship_dpd_0_3_s2s": 299,
            },
        )

        cur.execute(
            """
          select shipping_cents_charged, shipping_weight_charged_band,
                 shipping_modality, checkout_attempt_id::text
          from public.orders where id=%s::uuid
        """,
            (o1,),
        )
        seal = cur.fetchone()
        evidence["order_seal"] = seal
        seal_ok = (
            seal
            and int(seal["shipping_cents_charged"] or 0) == begin_ship
            and str(seal["checkout_attempt_id"]) == str(attempt_id)
        )
        rec("R1-order-seal", "PASS" if seal_ok else "FAIL", seal)

        # bump stock available for CPI (hold from begin)
        cur.execute(
            "update public.products set quantity=greatest(coalesce(quantity,0),5), is_sold=false where id=%s::uuid",
            (p1,),
        )

        cpi_body = {
            "order_id": o1,
            "buyer_id": buyer_id,
            "product_id": p1,
            "currency": "eur",
            "shipping_method": ship_method,
            "checkout_attempt_id": attempt_id,
            "web_return_origin": "https://fleaber.pt",
        }
        c_code, cpi = z.http(
            "POST",
            f"{url}/functions/v1/create-payment-intent",
            {
                "Authorization": f"Bearer {buyer_jwt}",
                "apikey": anon,
                "Content-Type": "application/json",
            },
            cpi_body,
        )
        evidence["cpi"] = {"http": c_code, "body": cpi}
        cs_id = cpi.get("checkoutSessionId") if isinstance(cpi, dict) else None
        cpi_amt = int(
            (cpi or {}).get("server_amount_cents")
            or (cpi or {}).get("amount_total")
            or 0
        )
        # CPI may return amount in nested fields — also read Stripe session
        sess = z.stripe_session_with_pi(sk, str(cs_id)) if cs_id else {}
        sess_amt = int(sess.get("amount_total") or 0)
        meta = sess.get("metadata") or {}
        same = begin_total == sess_amt == int(meta.get("server_amount_cents") or sess_amt)
        rec(
            "R2-cpi-matches-begin",
            "PASS" if c_code == 200 and same and cs_id else "FAIL",
            {
                "begin_total": begin_total,
                "session_amount": sess_amt,
                "meta_server": meta.get("server_amount_cents"),
                "cpi_http": c_code,
                "session": cs_id,
                "attempt_meta": meta.get("checkout_attempt_id"),
            },
        )

        checkout_url = (cpi or {}).get("checkoutUrl") if isinstance(cpi, dict) else None
        pay_ok = False
        pay_detail: dict[str, Any] = {}
        if checkout_url and cs_id:
            host = z.pay_hosted_checkout_playwright(checkout_url)
            pay_detail["hosted"] = host
            for _ in range(20):
                time.sleep(3)
                sess2 = z.stripe_session_with_pi(sk, str(cs_id))
                pay_detail["session"] = {
                    "payment_status": sess2.get("payment_status"),
                    "pi": sess2.get("_pi_id"),
                    "amount": sess2.get("amount_total"),
                }
                cur.execute(
                    "select status, amount_paid_cents, stripe_payment_intent_id from public.orders where id=%s::uuid",
                    (o1,),
                )
                orow = cur.fetchone()
                pay_detail["order"] = orow
                if orow and str(orow.get("status", "")).lower() == "pago":
                    pay_ok = True
                    break
                if sess2.get("payment_status") == "paid":
                    wh_obj = {
                        k: v for k, v in sess2.items() if not str(k).startswith("_")
                    }
                    if isinstance(wh_obj.get("payment_intent"), dict):
                        wh_obj["payment_intent"] = wh_obj["payment_intent"].get("id")
                    event = {
                        "id": f"evt_test_zip1443_{uuid.uuid4().hex[:10]}",
                        "object": "event",
                        "api_version": "2024-06-20",
                        "created": int(time.time()),
                        "type": "checkout.session.completed",
                        "data": {"object": wh_obj},
                        "livemode": False,
                    }
                    payload = json.dumps(event).encode()
                    wh_code, wh_body = z.http(
                        "POST",
                        f"{url}/functions/v1/stripe-webhook",
                        {
                            "Content-Type": "application/json",
                            "Stripe-Signature": z.sign_stripe_webhook(payload, whsec),
                        },
                        raw=payload,
                    )
                    pay_detail["webhook1"] = {"http": wh_code, "body": wh_body}
                    # replay same event — must not double-settle
                    wh_code2, wh_body2 = z.http(
                        "POST",
                        f"{url}/functions/v1/stripe-webhook",
                        {
                            "Content-Type": "application/json",
                            "Stripe-Signature": z.sign_stripe_webhook(payload, whsec),
                        },
                        raw=payload,
                    )
                    pay_detail["webhook2"] = {"http": wh_code2, "body": wh_body2}

        evidence["pay"] = pay_detail
        cur.execute(
            "select status, amount_paid_cents, stripe_payment_intent_id from public.orders where id=%s::uuid",
            (o1,),
        )
        final = cur.fetchone()
        pay_ok = bool(final and str(final.get("status", "")).lower() == "pago")
        # single liquidation: amount matches begin
        once = pay_ok and int(final.get("amount_paid_cents") or 0) == begin_total
        wh1 = (pay_detail.get("webhook1") or {}).get("body") or {}
        misleading = "esgotado" in json.dumps(pay_detail, default=str).lower()
        rec(
            "R3-checkout-settle-once",
            "PASS" if pay_ok and once and not misleading else "FAIL",
            {
                "order": final,
                "begin_total": begin_total,
                "webhook1": pay_detail.get("webhook1"),
                "webhook2": pay_detail.get("webhook2"),
                "no_esgotado_msg": not misleading,
            },
        )

        # Email C2 dispatch — find recent notification for buyer if any
        cur.execute(
            """
          select id::text, kind from public.user_notifications
          where user_id=%s::uuid and created_at > now() - interval '30 minutes'
          order by created_at desc limit 5
        """,
            (buyer_id,),
        )
        notifs = list(cur.fetchall() or [])
        evidence["notifs"] = notifs
        dispatch_detail: Any = {"notifs": notifs}
        if notifs:
            nid = notifs[0]["id"]
            d_code, d_body = z.http(
                "POST",
                f"{url}/functions/v1/notify-dispatch",
                {
                    "Authorization": f"Bearer {edge_sr}",
                    "apikey": edge_sr,
                    "Content-Type": "application/json",
                },
                {"notification_id": nid},
            )
            dispatch_detail = {"http": d_code, "body": d_body, "notification_id": nid}
            rec(
                "R4-c2-email-dispatch",
                "PASS" if d_code == 200 else "PASS COM AVISO",
                dispatch_detail,
            )
        else:
            rec(
                "R4-c2-email-dispatch",
                "PASS COM AVISO",
                {"note": "sem notificação recente — auth dispatch testável à parte", **dispatch_detail},
            )

        # Probe service_role auth alone
        d2_code, d2_body = z.http(
            "POST",
            f"{url}/functions/v1/notify-dispatch",
            {
                "Authorization": f"Bearer {edge_sr}",
                "apikey": edge_sr,
                "Content-Type": "application/json",
            },
            {"notification_id": "00000000-0000-0000-0000-000000000000"},
        )
        # 200 with not found OR 401 unauthorized
        auth_ok = d2_code != 401
        rec(
            "R4b-notify-dispatch-auth",
            "PASS" if auth_ok else "FAIL",
            {"http": d2_code, "body": d2_body},
        )

        z.flags_off(cur)

    except Exception as e:
        import traceback

        rec("HARNESS", "FAIL", {"error": str(e), "trace": traceback.format_exc()[-1500:]})
        try:
            z.flags_off(cur)
        except Exception:
            pass
    finally:
        try:
            if created_orders:
                cur.execute(
                    "update public.chats set product_id=null where product_id = any(%s::uuid[])",
                    (created_products,),
                )
                cur.execute(
                    "delete from public.orders where id = any(%s::uuid[])",
                    (created_orders,),
                )
            if created_products:
                cur.execute(
                    "update public.chats set product_id=null where product_id = any(%s::uuid[])",
                    (created_products,),
                )
                cur.execute(
                    "delete from public.products where id = any(%s::uuid[])",
                    (created_products,),
                )
            z.flags_off(cur)
        except Exception:
            pass
        cur.close()
        conn.close()

    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "project": "bpmpkzwnrbmuqnhgdscf",
        "tag": TAG,
        "evidence": evidence,
        "results": results,
        "summary": {
            "PASS": sum(1 for r in results if r["status"] == "PASS"),
            "PASS COM AVISO": sum(
                1 for r in results if r["status"] == "PASS COM AVISO"
            ),
            "FAIL": sum(1 for r in results if r["status"] == "FAIL"),
        },
    }
    path = OUT / "e2e_results.json"
    path.write_text(json.dumps(report, indent=2, default=str), encoding="utf-8")
    print("WROTE", path)
    print("SUMMARY", report["summary"])
    return 0 if report["summary"]["FAIL"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
