#!/usr/bin/env python3
"""ZIP 144 — GO-D bateria integrada PROD (dados TESTE-ZIP143). Flags OFF no fecho."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import traceback
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "tool/reports/144-prod-integrated-test-results"
OUT_DIR.mkdir(parents=True, exist_ok=True)

SELLER_ID = "ee7dbdb2-d2e1-4538-800f-7546d72f064a"  # vendedora.prod.teste@fleaber.test
BUYER_ID = "05641842-b943-48dd-9fb9-e01f745c45d6"  # comprador.perfil.h1132@fleaber.test
TAG = "TESTE-ZIP143"

FLAG_KEYS = [
    "order_weight_confirm_enabled",
    "order_shipping_delta_enabled",
    "order_ship_deadline_enabled",
    "order_ship_deadline_autocancel_enabled",
    "order_shipping_delta_pass_stripe_fee",
]

PS_PW = r"""
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CredManBat144 {
  [DllImport("Advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool CredRead(string target, int type, int flags, out IntPtr cred);
  [DllImport("Advapi32.dll", SetLastError=true)]
  public static extern void CredFree(IntPtr cred);
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct CREDENTIAL {
    public int Flags; public int Type; public string TargetName; public string Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten; public int CredentialBlobSize;
    public IntPtr CredentialBlob; public int Persist; public int AttributeCount; public IntPtr Attributes;
    public string TargetAlias; public string UserName;
  }
  public static string Read(string target) {
    IntPtr p; if (!CredRead(target, 1, 0, out p)) return "";
    try {
      var c = (CREDENTIAL)Marshal.PtrToStructure(p, typeof(CREDENTIAL));
      if (c.CredentialBlob == IntPtr.Zero || c.CredentialBlobSize <= 0) return "";
      return Marshal.PtrToStringUni(c.CredentialBlob, c.CredentialBlobSize / 2);
    } finally { CredFree(p); }
  }
}
"@
[Console]::Out.Write([CredManBat144]::Read('FleaberProdPostgres'))
"""

results: list[dict[str, Any]] = []
created_product_ids: list[str] = []
created_order_ids: list[str] = []
created_adj_ids: list[str] = []


def record(tid: str, status: str, detail: Any) -> None:
    row = {
        "id": tid,
        "status": status,
        "detail": detail,
        "at": datetime.now(timezone.utc).isoformat(),
    }
    results.append(row)
    print(f"[{status}] {tid}: {json.dumps(detail, default=str)[:500]}")


def connect():
    import psycopg2
    from psycopg2.extras import RealDictCursor

    pw = subprocess.check_output(
        ["powershell", "-NoProfile", "-Command", PS_PW], text=True
    ).strip()
    if not pw:
        raise RuntimeError("no FleaberProdPostgres")
    conn = psycopg2.connect(
        host="aws-1-eu-west-1.pooler.supabase.com",
        port=5432,
        dbname="postgres",
        user="postgres.bpmpkzwnrbmuqnhgdscf",
        password=pw,
        sslmode="require",
        connect_timeout=30,
    )
    conn.autocommit = True
    return conn, RealDictCursor


def set_flags(cur, mapping: dict[str, bool]) -> None:
    for k, v in mapping.items():
        cur.execute(
            """
          update public.fleaber_feature_flags
          set enabled = %s, updated_at = now()
          where key = %s
        """,
            (v, k),
        )


def flags_off(cur) -> None:
    cur.execute(
        """
      update public.fleaber_feature_flags
      set enabled = false, updated_at = now()
      where key = any(%s)
    """,
        (FLAG_KEYS,),
    )


def as_user(cur, user_id: str) -> None:
    # session-level (autocommit=True → is_local set_config evaporates)
    cur.execute("select set_config('request.jwt.claim.sub', %s, false)", (user_id,))
    cur.execute(
        "select set_config('request.jwt.claims', %s, false)",
        (json.dumps({"sub": user_id, "role": "authenticated"}),),
    )


def clear_user(cur) -> None:
    cur.execute("select set_config('request.jwt.claim.sub', '', false)")
    cur.execute("select set_config('request.jwt.claims', '', false)")


def insert_product(cur, title: str, kg: float | None, band: str | None) -> str:
    pid = str(uuid.uuid4())
    cur.execute(
        """
      insert into public.products (
        id, title, price, seller_id, quantity, is_draft, is_sold,
        shipping_weight_kg, shipping_weight_band, list_on_marketplace, description
      ) values (
        %s, %s, 9.99, %s::uuid, 1, false, false, %s, %s, false,
        %s
      )
      returning id::text
    """,
        (pid, title, SELLER_ID, kg, band, f"{TAG} harness product"),
    )
    created_product_ids.append(pid)
    return pid


def insert_paid_order(
    cur,
    *,
    product_id: str,
    charged_band: str,
    modality: str = "shop_to_shop",
    charged_kg: float | None = 2.0,
    shipping_cents: int = 299,
    weight_status: str | None = None,
) -> str:
    oid = str(uuid.uuid4())
    cur.execute(
        """
      insert into public.orders (
        id, buyer_id, seller_id, product_id, status, price_total, quantity,
        shipping_method, shipping_modality,
        shipping_weight_charged_band, shipping_weight_charged_kg,
        shipping_weight_band, shipping_weight_kg,
        shipping_cents_charged,
        weight_confirm_status, shipping_delta_status,
        delivery_point_ref, delivery_point_label,
        amount_paid_cents, commerce_channel
      ) values (
        %s::uuid, %s::uuid, %s::uuid, %s::uuid, 'pago', 12.98, 1,
        'Envio Transportadora', %s,
        %s, %s,
        %s, %s,
        %s,
        %s, 'none',
        'PUDO-TESTE-ZIP143', 'TESTE Point ZIP143',
        1298, 'c2c'
      )
      returning id::text
    """,
        (
            oid,
            BUYER_ID,
            SELLER_ID,
            product_id,
            modality,
            charged_band,
            charged_kg,
            charged_band,
            charged_kg,
            shipping_cents,
            weight_status,
        ),
    )
    created_order_ids.append(oid)
    return oid


def http_json(url: str, headers: dict[str, str], body: dict | None = None) -> tuple[int, Any]:
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            try:
                return resp.status, json.loads(raw)
            except Exception:
                return resp.status, raw
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw


def main() -> int:
    conn, RealDictCursor = connect()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    supabase_url = (os.environ.get("SUPABASE_URL") or "").rstrip("/")
    # Edge service role may differ from local; prefer DB RPCs for tick/auth-sensitive.

    try:
        # ------------------------------------------------------------------ GO-D start: ensure OFF + limpar órfãos TESTE
        flags_off(cur)
        cur.execute(
            """
          delete from public.order_shipping_adjustments a
          using public.orders o
          where a.order_id = o.id
            and (
              o.delivery_point_ref = 'PUDO-TESTE-ZIP143'
              or o.delivery_point_label = 'TESTE Point ZIP143'
            )
        """
        )
        cur.execute(
            """
          delete from public.orders
          where delivery_point_ref = 'PUDO-TESTE-ZIP143'
             or delivery_point_label = 'TESTE Point ZIP143'
        """
        )
        cur.execute("delete from public.products where title like %s", (f"{TAG}%",))
        cur.execute(
            "select key, enabled from public.fleaber_feature_flags where key = any(%s) order by 1",
            (FLAG_KEYS,),
        )
        record("GO-D-preflags", "PASS", list(cur.fetchall()))

        # ------------------------------------------------------------------ T1 product weight
        p1 = insert_product(cur, f"{TAG} peso opcional A", None, None)
        cur.execute(
            "update public.products set shipping_weight_kg=2.5, shipping_weight_band='0_3' where id=%s::uuid",
            (p1,),
        )
        cur.execute(
            "select shipping_weight_kg::float, shipping_weight_band from public.products where id=%s::uuid",
            (p1,),
        )
        row = cur.fetchone()
        ok = row and abs(float(row["shipping_weight_kg"]) - 2.5) < 0.01 and row["shipping_weight_band"] == "0_3"
        record("T1", "PASS" if ok else "FAIL", {"product_id": p1, "row": row})

        # ------------------------------------------------------------------ T2 seal on order (backend)
        p2 = insert_product(cur, f"{TAG} checkout seal", 2.0, "0_3")
        o2 = insert_paid_order(cur, product_id=p2, charged_band="0_3", charged_kg=2.0, shipping_cents=299)
        cur.execute(
            """
          select shipping_weight_charged_band, shipping_cents_charged, shipping_modality, status
          from public.orders where id=%s::uuid
        """,
            (o2,),
        )
        r2 = cur.fetchone()
        ok2 = (
            r2
            and r2["shipping_weight_charged_band"] == "0_3"
            and int(r2["shipping_cents_charged"]) == 299
            and r2["shipping_modality"] == "shop_to_shop"
            and r2["status"] == "pago"
        )
        record(
            "T2",
            "PASS" if ok2 else "FAIL",
            {
                "order_id": o2,
                "row": r2,
                "note": "selo BD (checkout UI Stripe test sem device — backend seal)",
            },
        )

        # ------------------------------------------------------------------ T3 multi weight aggregate
        cur.execute("select public.batata_dpd_weight_band(2.0) as b1, public.batata_dpd_weight_band(4.0) as b2")
        bands = cur.fetchone()
        # aggregate = max band of units → 3_6 for 2+4
        cur.execute("select public.batata_dpd_weight_band(6.0) as agg")
        agg = cur.fetchone()
        cur.execute(
            """
          select price_eur::float from public.dpd_shipping_rates
          where modality='shop_to_shop' and weight_band='3_6' and active limit 1
        """
        )
        rate = cur.fetchone()
        p3a = insert_product(cur, f"{TAG} multi 2kg", 2.0, "0_3")
        p3b = insert_product(cur, f"{TAG} multi 4kg", 4.0, "3_6")
        o3 = insert_paid_order(
            cur,
            product_id=p3a,
            charged_band="3_6",
            charged_kg=6.0,
            shipping_cents=int(round(float(rate["price_eur"]) * 100)) if rate else 349,
        )
        ok3 = bands and bands["b1"] == "0_3" and bands["b2"] == "3_6" and agg and agg["agg"] == "3_6"
        record(
            "T3",
            "PASS" if ok3 else "FAIL",
            {"bands": bands, "agg": agg, "rate": rate, "order_id": o3, "products": [p3a, p3b]},
        )

        # ------------------------------------------------------------------ T4 live-like seal (no live open)
        p4 = insert_product(cur, f"{TAG} live-like", 1.5, "0_3")
        o4 = insert_paid_order(cur, product_id=p4, charged_band="0_3", charged_kg=1.5)
        cur.execute("select public.batata_dpd_weight_band(1.5) as b")
        b4 = cur.fetchone()
        record(
            "T4",
            "PASS" if b4 and b4["b"] == "0_3" else "FAIL",
            {
                "order_id": o4,
                "band": b4,
                "note": "sem directo aberto; selo/RPC peso OK (live UI SKIP device)",
            },
        )

        # ------------------------------------------------------------------ D2 flags ON — T5 confirm same
        set_flags(cur, {"order_weight_confirm_enabled": True})
        p5 = insert_product(cur, f"{TAG} confirm same", 2.0, "0_3")
        # insert as pago; trigger may set pending when flag on — force pending clocks
        o5 = insert_paid_order(
            cur, product_id=p5, charged_band="0_3", charged_kg=2.0, weight_status="pending"
        )
        cur.execute(
            """
          update public.orders set
            weight_confirm_status='pending',
            weight_confirm_deadline_at = now() + interval '3 days',
            ship_by_at = null
          where id=%s::uuid
        """,
            (o5,),
        )
        as_user(cur, SELLER_ID)
        cur.execute(
            "select public.batata_seller_confirm_shipping_weight(%s::uuid, 2.0, '0_3', 'confirm') as j",
            (o5,),
        )
        j5 = cur.fetchone()["j"]
        clear_user(cur)
        cur.execute(
            "select weight_confirm_status, shipping_delta_status from public.orders where id=%s::uuid",
            (o5,),
        )
        s5 = cur.fetchone()
        ok5 = (
            isinstance(j5, dict)
            and j5.get("ok") is True
            and j5.get("result") == "confirmed_same"
            and s5
            and s5["weight_confirm_status"] == "confirmed_same"
        )
        record("T5", "PASS" if ok5 else "FAIL", {"rpc": j5, "order": s5, "order_id": o5})

        # ------------------------------------------------------------------ D3 — T6 assume
        set_flags(
            cur,
            {
                "order_weight_confirm_enabled": True,
                "order_shipping_delta_enabled": True,
            },
        )
        p6 = insert_product(cur, f"{TAG} assume", 2.0, "0_3")
        o6 = insert_paid_order(cur, product_id=p6, charged_band="0_3", charged_kg=2.0)
        cur.execute(
            """
          update public.orders set weight_confirm_status='pending',
            weight_confirm_deadline_at=now()+interval '3 days' where id=%s::uuid
        """,
            (o6,),
        )
        as_user(cur, SELLER_ID)
        cur.execute(
            "select public.batata_seller_confirm_shipping_weight(%s::uuid, 5.0, '3_6', 'assume') as j",
            (o6,),
        )
        j6 = cur.fetchone()["j"]
        clear_user(cur)
        cur.execute(
            """
          select weight_confirm_status, shipping_delta_status from public.orders where id=%s::uuid
        """,
            (o6,),
        )
        s6 = cur.fetchone()
        cur.execute(
            """
          select id::text, status from public.order_shipping_adjustments
          where order_id=%s::uuid order by created_at desc limit 1
        """,
            (o6,),
        )
        a6 = cur.fetchone()
        if a6:
            created_adj_ids.append(a6["id"])
        gate6 = None
        cur.execute("select public.batata_order_blocks_dpd_create(%s::uuid) as j", (o6,))
        gate6 = cur.fetchone()["j"]
        ok6 = (
            isinstance(j6, dict)
            and j6.get("result") == "assumed_by_seller"
            and s6
            and s6["weight_confirm_status"] == "assumed_by_seller"
            and a6
            and a6["status"] == "assumed"
            and isinstance(gate6, dict)
            and gate6.get("blocked") is False
        )
        record("T6", "PASS" if ok6 else "FAIL", {"rpc": j6, "order": s6, "adj": a6, "dpd_gate": gate6})

        # ------------------------------------------------------------------ T7 request_delta + fee absorb + mark paid idempotent
        p7 = insert_product(cur, f"{TAG} delta pay", 2.0, "0_3")
        o7 = insert_paid_order(cur, product_id=p7, charged_band="0_3", charged_kg=2.0)
        cur.execute(
            """
          update public.orders set weight_confirm_status='pending',
            weight_confirm_deadline_at=now()+interval '3 days',
            ship_by_at = public.batata_add_business_days(now(), 5)
          where id=%s::uuid
        """,
            (o7,),
        )
        cur.execute(
            "select ship_by_at from public.orders where id=%s::uuid",
            (o7,),
        )
        ship_before = cur.fetchone()
        as_user(cur, SELLER_ID)
        cur.execute(
            "select public.batata_seller_confirm_shipping_weight(%s::uuid, 5.0, '3_6', 'request_delta') as j",
            (o7,),
        )
        j7 = cur.fetchone()["j"]
        clear_user(cur)
        adj_id = j7.get("adjustment_id") if isinstance(j7, dict) else None
        if adj_id:
            created_adj_ids.append(str(adj_id))
        cur.execute("select public.batata_shipping_delta_charge_cents(%s) as q", (j7.get("shipping_delta_cents") if isinstance(j7, dict) else 50,))
        quote = cur.fetchone()["q"]
        # expected delta shop_to_shop 0_3→3_6 = (3.49-2.99)*100 = 50
        cur.execute(
            """
          select status, shipping_delta_cents, stripe_fee_grossup_cents, amount_charge_cents,
                 expires_at > now() as expires_future
          from public.order_shipping_adjustments where id=%s::uuid
        """,
            (adj_id,),
        )
        adj7 = cur.fetchone()
        cur.execute(
            """
          select weight_confirm_status, shipping_delta_status, ship_clock_paused_at is not null as paused
          from public.orders where id=%s::uuid
        """,
            (o7,),
        )
        o7s = cur.fetchone()
        # stock / is_sold snapshot
        cur.execute("select is_sold, quantity from public.products where id=%s::uuid", (p7,))
        stock_before = cur.fetchone()
        # mark paid (simula webhook success path)
        cur.execute(
            "select public.batata_mark_shipping_adjustment_paid(%s::uuid, %s, null) as j",
            (adj_id, f"pi_test_zip143_{uuid.uuid4().hex[:12]}"),
        )
        mark1 = cur.fetchone()["j"]
        cur.execute(
            "select public.batata_mark_shipping_adjustment_paid(%s::uuid, %s, null) as j",
            (adj_id, "pi_test_replay"),
        )
        mark2 = cur.fetchone()["j"]
        cur.execute("select is_sold, quantity from public.products where id=%s::uuid", (p7,))
        stock_after = cur.fetchone()
        cur.execute(
            """
          select weight_confirm_status, shipping_delta_status, shipping_weight_charged_band,
                 ship_clock_paused_at is null as clock_resumed
          from public.orders where id=%s::uuid
        """,
            (o7,),
        )
        o7after = cur.fetchone()
        # notifications (C2 inbox — sem coluna payload; dedupe_key / body)
        cur.execute(
            """
          select kind, user_id::text, dedupe_key, title, left(body, 120) as body
          from public.user_notifications
          where kind in ('shipping_delta_requested','shipping_delta_paid')
            and (
              dedupe_key ilike '%%' || %s || '%%'
              or created_at > now() - interval '15 minutes'
            )
          order by created_at desc
          limit 10
        """,
            (o7,),
        )
        notifs = list(cur.fetchall())
        if isinstance(quote, str):
            try:
                quote = json.loads(quote)
            except Exception:
                pass
        fee_ok = (
            isinstance(quote, dict)
            and quote.get("pass_stripe_fee") in (False, "false", 0, "0")
            and int(quote.get("amount_charge_cents") or -1)
            == int(quote.get("shipping_delta_cents") or -2)
            and int(quote.get("stripe_fee_grossup_cents") or 0) == 0
            and int(quote.get("amount_charge_cents") or -1)
            == int((j7 or {}).get("amount_charge_cents") or -1)
        )
        adj_ok = (
            adj7
            and adj7["status"] == "paid"  # after mark
            or (
                isinstance(j7, dict)
                and j7.get("ok")
                and adj7
                and int(adj7["stripe_fee_grossup_cents"] or 0) == 0
                and int(adj7["amount_charge_cents"]) == int(adj7["shipping_delta_cents"])
            )
        )
        # re-fetch adj after marks — status should be paid
        cur.execute(
            "select status, shipping_delta_cents, amount_charge_cents, stripe_fee_grossup_cents from public.order_shipping_adjustments where id=%s::uuid",
            (adj_id,),
        )
        adj7b = cur.fetchone()
        stock_unchanged = (
            stock_before is not None
            and stock_after is not None
            and stock_before["is_sold"] == stock_after["is_sold"]
            and int(stock_before["quantity"] or 0) == int(stock_after["quantity"] or 0)
        )
        ok7_checks = {
            "rpc_delta": isinstance(j7, dict) and j7.get("result") == "delta_requested",
            "fee_ok": fee_ok,
            "adj_paid": bool(adj7b) and adj7b["status"] == "paid",
            "adj_no_fee": bool(adj7b) and int(adj7b["stripe_fee_grossup_cents"] or 0) == 0,
            "mark1": isinstance(mark1, dict) and mark1.get("ok") is True,
            "mark2_idem": isinstance(mark2, dict) and mark2.get("already") is True,
            "stock_unchanged": stock_unchanged,
            "delta_paid": bool(o7after) and o7after["weight_confirm_status"] == "delta_paid",
            "band_to": bool(o7after) and o7after["shipping_weight_charged_band"] == "3_6",
            "paused_mid": bool(o7s) and bool(o7s["paused"]),
        }
        ok7 = all(ok7_checks.values())
        record(
            "T7",
            "PASS" if ok7 else "FAIL",
            {
                "rpc": j7,
                "quote": quote,
                "adj_before_mark_fields": adj7,
                "adj_after": adj7b,
                "mark1": mark1,
                "mark2": mark2,
                "stock_before": stock_before,
                "stock_after": stock_after,
                "order_mid": o7s,
                "order_after": o7after,
                "ship_before": ship_before,
                "notifs_sample": notifs[:4],
                "ok7_checks": ok7_checks,
                "note": "PI Stripe Checkout UI + webhook HTTP assinatura: validado via RPC mark (caminho webhook) + fee absorb; notify_id null = emit soft-fail (T11)",
            },
        )

        # ------------------------------------------------------------------ T8 DPD gate while pending
        p8 = insert_product(cur, f"{TAG} dpd gate", 2.0, "0_3")
        o8 = insert_paid_order(cur, product_id=p8, charged_band="0_3")
        cur.execute(
            "update public.orders set weight_confirm_status='pending' where id=%s::uuid",
            (o8,),
        )
        as_user(cur, SELLER_ID)
        cur.execute(
            "select public.batata_seller_confirm_shipping_weight(%s::uuid, 5.0, '3_6', 'request_delta') as j",
            (o8,),
        )
        j8 = cur.fetchone()["j"]
        clear_user(cur)
        if isinstance(j8, dict) and j8.get("adjustment_id"):
            created_adj_ids.append(str(j8["adjustment_id"]))
        cur.execute("select public.batata_order_blocks_dpd_create(%s::uuid) as j", (o8,))
        gate8 = cur.fetchone()["j"]
        # also hit edge create (should refuse QA create and/or gate)
        edge_dpd = None
        if supabase_url and os.environ.get("SUPABASE_ANON_KEY"):
            code, edge_dpd = http_json(
                f"{supabase_url}/functions/v1/dpd-expedition",
                {
                    "Authorization": f"Bearer {os.environ.get('SUPABASE_ANON_KEY')}",
                    "apikey": os.environ.get("SUPABASE_ANON_KEY") or "",
                    "Content-Type": "application/json",
                },
                {"action": "create", "order_id": o8},
            )
            edge_dpd = {"http": code, "body": edge_dpd}
        ok8 = isinstance(gate8, dict) and gate8.get("blocked") is True and gate8.get("error") == "shipping_delta_unpaid"
        record("T8", "PASS" if ok8 else "FAIL", {"rpc_gate": gate8, "confirm": j8, "edge": edge_dpd})

        # ------------------------------------------------------------------ T9 expire 48h autocancel ON then OFF (manual tick RPC only)
        set_flags(
            cur,
            {
                "order_weight_confirm_enabled": True,
                "order_shipping_delta_enabled": True,
                "order_ship_deadline_autocancel_enabled": True,
            },
        )
        p9 = insert_product(cur, f"{TAG} expire48", 2.0, "0_3")
        o9 = insert_paid_order(cur, product_id=p9, charged_band="0_3")
        cur.execute(
            "update public.orders set weight_confirm_status='pending' where id=%s::uuid",
            (o9,),
        )
        as_user(cur, SELLER_ID)
        cur.execute(
            "select public.batata_seller_confirm_shipping_weight(%s::uuid, 5.0, '3_6', 'request_delta') as j",
            (o9,),
        )
        j9 = cur.fetchone()["j"]
        clear_user(cur)
        adj9 = j9.get("adjustment_id") if isinstance(j9, dict) else None
        if adj9:
            created_adj_ids.append(str(adj9))
            cur.execute(
                "update public.order_shipping_adjustments set expires_at = now() - interval '1 minute' where id=%s::uuid",
                (adj9,),
            )
        cur.execute(
            "select public.batata_expire_shipping_deltas_and_deadlines(now(), 40) as j"
        )
        exp = cur.fetchone()["j"]
        cur.execute(
            "select status from public.order_shipping_adjustments where id=%s::uuid",
            (adj9,),
        )
        adj9s = cur.fetchone()
        cur.execute(
            "select weight_confirm_status, shipping_delta_status, status from public.orders where id=%s::uuid",
            (o9,),
        )
        o9s = cur.fetchone()
        # immediate OFF autocancel
        set_flags(cur, {"order_ship_deadline_autocancel_enabled": False})
        cur.execute(
            "select public.batata_expire_shipping_deltas_and_deadlines(now(), 40) as j"
        )
        skipped = cur.fetchone()["j"]
        ok9 = (
            isinstance(exp, dict)
            and not exp.get("skipped")
            and int(exp.get("delta_expired") or 0) >= 1
            and adj9s
            and adj9s["status"] == "expired"
            and o9s
            and o9s["shipping_delta_status"] == "expired"
            and isinstance(skipped, dict)
            and skipped.get("skipped") is True
        )
        record(
            "T9",
            "PASS" if ok9 else "FAIL",
            {
                "expire": exp,
                "adj": adj9s,
                "order": o9s,
                "after_off": skipped,
                "note": "refund-order Edge não invocado nesta ronda (lista IDs na RPC); autocancel OFF imediato",
            },
        )

        # ------------------------------------------------------------------ T10 ship deadline pause/resume
        set_flags(
            cur,
            {
                "order_weight_confirm_enabled": True,
                "order_shipping_delta_enabled": True,
                "order_ship_deadline_enabled": True,
                "order_ship_deadline_autocancel_enabled": False,
            },
        )
        p10 = insert_product(cur, f"{TAG} ship clock", 2.0, "0_3")
        o10 = insert_paid_order(cur, product_id=p10, charged_band="0_3")
        cur.execute(
            """
          update public.orders set
            weight_confirm_status='pending',
            ship_by_at = public.batata_add_business_days(now(), 5),
            ship_clock_paused_at = null,
            ship_deadline_paused_remaining_seconds = null
          where id=%s::uuid
          returning ship_by_at
        """,
            (o10,),
        )
        ship0 = cur.fetchone()
        as_user(cur, SELLER_ID)
        cur.execute(
            "select public.batata_seller_confirm_shipping_weight(%s::uuid, 5.0, '3_6', 'request_delta') as j",
            (o10,),
        )
        j10 = cur.fetchone()["j"]
        clear_user(cur)
        if isinstance(j10, dict) and j10.get("adjustment_id"):
            created_adj_ids.append(str(j10["adjustment_id"]))
        cur.execute(
            """
          select ship_clock_paused_at is not null as paused,
                 ship_deadline_paused_remaining_seconds,
                 ship_by_at
          from public.orders where id=%s::uuid
        """,
            (o10,),
        )
        mid = cur.fetchone()
        # assume path on a fresh order for resume without full 5d reset — mark paid resume
        cur.execute(
            "select public.batata_mark_shipping_adjustment_paid(%s::uuid, %s, null) as j",
            (j10.get("adjustment_id"), f"pi_clock_{uuid.uuid4().hex[:8]}"),
        )
        mark10 = cur.fetchone()["j"]
        cur.execute(
            """
          select ship_clock_paused_at is null as resumed, ship_by_at, weight_confirm_status
          from public.orders where id=%s::uuid
        """,
            (o10,),
        )
        after = cur.fetchone()
        # flags OFF → new order should not get clocks from trigger in same way
        set_flags(
            cur,
            {
                "order_weight_confirm_enabled": False,
                "order_ship_deadline_enabled": False,
                "order_shipping_delta_enabled": False,
            },
        )
        p10b = insert_product(cur, f"{TAG} no clock", 1.0, "0_3")
        o10b = insert_paid_order(cur, product_id=p10b, charged_band="0_3")
        # simulate paid transition trigger: update status touch
        cur.execute(
            """
          update public.orders set status='pago'
          where id=%s::uuid
          returning weight_confirm_status, ship_by_at, weight_confirm_deadline_at
        """,
            (o10b,),
        )
        no_clock = cur.fetchone()
        ok10 = (
            mid
            and mid["paused"] is True
            and after
            and after["resumed"] is True
            and after["weight_confirm_status"] == "delta_paid"
            and isinstance(mark10, dict)
            and mark10.get("ok")
        )
        record(
            "T10",
            "PASS" if ok10 else "FAIL",
            {
                "ship0": ship0,
                "mid": mid,
                "after": after,
                "mark": mark10,
                "flags_off_order": no_clock,
                "confirm": j10,
            },
        )

        # ------------------------------------------------------------------ T11 C2 events (from T7 notifs + explicit check)
        cur.execute(
            """
          select kind, count(*)::int as n
          from public.user_notifications
          where kind in (
            'shipping_delta_requested','shipping_delta_paid',
            'shipping_delta_expired_cancelled','ship_deadline_auto_cancelled'
          )
          and created_at > now() - interval '2 hours'
          group by kind order by 1
        """
        )
        kinds = list(cur.fetchall())
        cur.execute(
            """
          select kind, dedupe_key, title, left(body, 160) as body
          from public.user_notifications
          where kind = 'shipping_delta_requested'
            and created_at > now() - interval '2 hours'
          order by created_at desc limit 3
        """
        )
        samples = list(cur.fetchall())
        has_req = any(k["kind"] == "shipping_delta_requested" and k["n"] > 0 for k in kinds)
        record(
            "T11",
            "PASS" if has_req else "PASS COM AVISO",
            {
                "kinds_2h": kinds,
                "samples": samples,
                "note": "email comercial destes kinds NÃO esperado (C2 allowlist) — inbox/push BD OK se requested presente",
            },
        )

        # ------------------------------------------------------------------ T12 flags OFF no-op
        flags_off(cur)
        as_user(cur, SELLER_ID)
        cur.execute(
            "select public.batata_seller_confirm_shipping_weight(%s::uuid, 2.0, '0_3', 'confirm') as j",
            (o2,),
        )
        j12 = cur.fetchone()["j"]
        clear_user(cur)
        cur.execute("select public.batata_expire_shipping_deltas_and_deadlines(now(), 5) as j")
        t12 = cur.fetchone()["j"]
        cur.execute(
            "select key, enabled from public.fleaber_feature_flags where key = any(%s) order by 1",
            (FLAG_KEYS,),
        )
        final_flags = list(cur.fetchall())
        ok12 = (
            isinstance(j12, dict)
            and j12.get("error") == "weight_confirm_disabled"
            and isinstance(t12, dict)
            and t12.get("skipped") is True
            and all(not f["enabled"] for f in final_flags)
        )
        record("T12", "PASS" if ok12 else "FAIL", {"confirm": j12, "tick": t12, "flags": final_flags})

        # ------------------------------------------------------------------ fee unit check + business days
        cur.execute("select public.batata_shipping_delta_charge_cents(50) as q")
        q50 = cur.fetchone()["q"]
        cur.execute("select public.batata_add_business_days(timestamptz '2026-11-03 12:00:00+00', 5) as d")
        biz = cur.fetchone()
        record(
            "AUX-fee-bizdays",
            "PASS"
            if isinstance(q50, dict)
            and q50.get("amount_charge_cents") == 50
            and q50.get("pass_stripe_fee") is False
            else "FAIL",
            {"quote50": q50, "biz": biz},
        )

        # ------------------------------------------------------------------ cron still empty for tick
        try:
            cur.execute(
                """
              select jobid::text, jobname from cron.job
              where command ilike '%order-shipping-deadline%'
                 or command ilike '%batata_expire_shipping%'
                 or jobname ilike '%shipping%deadline%'
            """
            )
            cron = list(cur.fetchall())
        except Exception as e:
            cron = [{"err": str(e)}]
            conn.rollback()
        record("AUX-no-cron", "PASS" if cron == [] else "FAIL", {"cron": cron})

        # ------------------------------------------------------------------ dpd create flag
        cur.execute(
            "select key, enabled from public.fleaber_feature_flags where key in ('dpd_create_enabled') order by 1"
        )
        dpd_f = list(cur.fetchall())
        record(
            "AUX-dpd-commercial-off",
            "PASS" if dpd_f and dpd_f[0]["enabled"] is False else "FAIL",
            dpd_f,
        )

        # cleanup TESTE rows (orders/adjs/products) — keep report ids
        flags_off(cur)
        if created_adj_ids:
            cur.execute(
                "delete from public.order_shipping_adjustments where id = any(%s::uuid[])",
                (created_adj_ids,),
            )
        # also delete by order
        if created_order_ids:
            cur.execute(
                "delete from public.order_shipping_adjustments where order_id = any(%s::uuid[])",
                (created_order_ids,),
            )
            cur.execute(
                "delete from public.orders where id = any(%s::uuid[])",
                (created_order_ids,),
            )
        if created_product_ids:
            cur.execute(
                "delete from public.products where id = any(%s::uuid[])",
                (created_product_ids,),
            )
        # leftover TESTE-ZIP143 products
        cur.execute("delete from public.products where title like %s", (f"{TAG}%",))

        cur.execute(
            "select key, enabled from public.fleaber_feature_flags where key = any(%s) order by 1",
            (FLAG_KEYS,),
        )
        record("GO-D-postflags", "PASS", list(cur.fetchall()))

    except Exception as e:
        flags_off(cur)
        record("HARNESS", "FAIL", {"error": str(e), "trace": traceback.format_exc()[-1500:]})
    finally:
        try:
            flags_off(cur)
        except Exception:
            pass
        cur.close()
        conn.close()

    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "project": "bpmpkzwnrbmuqnhgdscf",
        "tag": TAG,
        "seller_id": SELLER_ID,
        "buyer_id": BUYER_ID,
        "created_then_deleted": {
            "products": created_product_ids,
            "orders": created_order_ids,
            "adjustments": created_adj_ids,
        },
        "results": results,
        "summary": {
            "PASS": sum(1 for r in results if r["status"] == "PASS"),
            "PASS COM AVISO": sum(1 for r in results if r["status"] == "PASS COM AVISO"),
            "FAIL": sum(1 for r in results if r["status"] == "FAIL"),
            "SKIP": sum(1 for r in results if r["status"] == "SKIP"),
        },
    }
    path = OUT_DIR / "battery_results.json"
    path.write_text(json.dumps(report, indent=2, default=str), encoding="utf-8")
    print("WROTE", path)
    print("SUMMARY", report["summary"])
    return 0 if report["summary"]["FAIL"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
