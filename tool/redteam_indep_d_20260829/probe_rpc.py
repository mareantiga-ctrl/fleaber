#!/usr/bin/env python3
"""Hostile RPC calls with buyer/seller JWT + OpenAPI as authenticated."""
from __future__ import annotations

import json
import time
import urllib.error
import urllib.request
from pathlib import Path

ENV_PATH = Path(__file__).resolve().parents[1] / "live_ops_staging.env"
BASE = "https://fxdknzrqjenzqcvnwqqq.supabase.co"
REST = BASE + "/rest/v1/"
AUTH = BASE + "/auth/v1/"
OUT = Path(__file__).resolve().parent / "probe_rpc.json"


def load_env():
    e = {}
    for line in ENV_PATH.read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.strip().startswith("#"):
            k, v = line.split("=", 1)
            e[k.strip()] = v.strip()
    return e


def http(method, url, token, apikey, body=None):
    headers = {"Accept": "application/json", "apikey": apikey, "Authorization": f"Bearer {token}"}
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            try:
                parsed = json.loads(raw) if raw else None
            except json.JSONDecodeError:
                parsed = raw
            return {"ok": 200 <= resp.status < 300, "status": resp.status, "body": parsed}
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            parsed = raw
        return {"ok": False, "status": e.code, "body": parsed}


def main():
    env = load_env()
    anon, svc = env["SUPABASE_ANON_KEY"], env["SUPABASE_SERVICE_ROLE_KEY"]
    r = http("POST", AUTH + "token?grant_type=password", anon, anon, {"email": env["LIVE_OPS_TEST_BUYER_EMAIL"], "password": env["LIVE_OPS_TEST_BUYER_PASSWORD"]})
    buyer_jwt, buyer_id = r["body"]["access_token"], r["body"]["user"]["id"]
    r = http("POST", AUTH + "token?grant_type=password", anon, anon, {"email": env["LIVE_OPS_TEST_SELLER_EMAIL"], "password": env["LIVE_OPS_TEST_SELLER_PASSWORD"]})
    seller_jwt, seller_id = r["body"]["access_token"], r["body"]["user"]["id"]

    # OpenAPI as buyer vs anon vs seller
    inv = {}
    for name, tok in [("anon", anon), ("buyer", buyer_jwt), ("seller", seller_jwt)]:
        spec = http("GET", REST, tok, anon)
        # default accept might not be openapi
        req = urllib.request.Request(REST, headers={"apikey": anon, "Authorization": f"Bearer {tok}", "Accept": "application/openapi+json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                specb = json.loads(resp.read().decode())
            rpcs = sorted({p.split("/")[-1] for p in specb.get("paths", {}) if p.startswith("/rpc/")})
        except urllib.error.HTTPError as e:
            rpcs = [f"http_{e.code}"]
        inv[name] = {"n": len(rpcs), "sensitive": [x for x in rpcs if any(k in x.lower() for k in ("wallet", "payout", "credit", "refund", "admin", "nuke", "prize", "settle", "clawback", "tip", "winner", "draw"))]}
        print(name, "rpcs", len(rpcs), "sens", inv[name]["sensitive"][:30], flush=True)

    fake_oid = "9ff35b32-915b-418e-a916-f91ec76cc535"
    fake_uuid = "00000000-0000-0000-0000-000000000001"
    calls = [
        ("buyer", "batata_create_raffle_prize_order", {"p_raffle_id": fake_uuid, "p_winner_uid": buyer_id, "p_rank": 1}),
        ("buyer", "batata_settle_live_tip_from_stripe", {"p_tip_id": fake_uuid, "p_stripe_session_id": "cs_test_x", "p_paid_amount_cents": 10000}),
        ("buyer", "batata_finalize_stripe_order_refund", {"p_order_id": fake_oid, "p_refund_id": "re_fake", "p_amount_cents": 100000, "p_payment_intent_id": "pi_x"}),
        ("buyer", "batata_clawback_seller_wallet_for_order", {"p_order_id": fake_oid}),
        ("seller", "batata_clawback_seller_wallet_for_order", {"p_order_id": fake_oid}),
        ("buyer", "batata_award_live_raffle_tickets", {"p_raffle_id": fake_uuid, "p_user_id": buyer_id, "p_action_type": "share", "p_tickets_delta": 99, "p_source_id": "rt-d"}),
        ("buyer", "batata_draw_live_raffle_winners", {"p_raffle_id": fake_uuid}),
        ("buyer", "staging_nuke_user_data", {"p_user_id": seller_id}),
        ("buyer", "batata_wallet_apply_tip_once", {"p_wallet_id": buyer_id, "p_tip_id": fake_uuid, "p_amount": 50, "p_type": "venda", "p_description": "rt"}),
        ("buyer", "batata_record_buyer_refund_ledger", {"p_order_id": fake_oid}),
        ("buyer", "batata_wallet_payout_finish", {"p_idempotency_key": "rt_d_seq_a_" + str(int(time.time())), "p_stripe_transfer_id": "tr_fake", "p_failed": False}),
        ("seller", "batata_wallet_payout_finish", {"p_idempotency_key": "x"*12, "p_stripe_transfer_id": "tr_fake"}),
        ("buyer", "batata_activate_live_raffle", {"p_raffle_id": fake_uuid}),
        ("buyer", "batata_create_live_raffle", {"p_live_id": fake_uuid}),
        ("buyer", "batata_send_live_tip_from_wallet", {"p_seller_id": seller_id, "p_amount": 1, "p_live_id": fake_uuid}),
        ("buyer", "batata_process_partial_refund_dispute", {"p_order_id": "22415e09-ec30-4c02-8697-0159d6db9454"}),
        ("seller", "batata_process_partial_refund_dispute", {"p_order_id": "22415e09-ec30-4c02-8697-0159d6db9454"}),
        ("buyer", "batata_release_seller_wallet_for_order", {"p_order_id": "22415e09-ec30-4c02-8697-0159d6db9454"}),
        ("buyer", "batata_refund_buyer_wallet_for_order", {"p_order_id": "22415e09-ec30-4c02-8697-0159d6db9454"}),
        ("seller", "batata_mark_live_item_sold", {"p_live_item_id": fake_uuid}),
        ("buyer", "batata_mark_live_item_sold", {"p_live_item_id": fake_uuid}),
        ("buyer", "batata_update_live_item", {"p_id": fake_uuid, "p_price": 0.01, "p_qty": 99}),
        ("seller", "batata_create_raffle_prize_order", {"p_raffle_id": fake_uuid, "p_winner_uid": buyer_id}),
    ]
    tok = {"buyer": buyer_jwt, "seller": seller_jwt}
    results = []
    for ident, name, params in calls:
        rr = http("POST", REST + "rpc/" + name, tok[ident], anon, params)
        results.append({"ident": ident, "rpc": name, "http": rr["status"], "ok": rr["ok"], "body": rr.get("body")})
        print(ident, name, rr["status"], json.dumps(rr.get("body"), ensure_ascii=False, default=str)[:180], flush=True)

    payload = {
        "inventory_authenticated": inv,
        "rpc_calls": results,
        "buyer_id": buyer_id,
        "seller_id": seller_id,
    }
    OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2, default=str), encoding="utf-8")
    print("WROTE", OUT)


if __name__ == "__main__":
    main()
