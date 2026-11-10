#!/usr/bin/env python3
"""P0 repro + variants for batata_wallet_apply_tip_once. Staging TEST only."""
from __future__ import annotations

import json
import time
import urllib.error
import urllib.request
from pathlib import Path

ENV = Path(__file__).resolve().parents[1] / "live_ops_staging.env"
BASE = "https://fxdknzrqjenzqcvnwqqq.supabase.co"
REST, AUTH, FN = BASE + "/rest/v1/", BASE + "/auth/v1/", BASE + "/functions/v1/"
OUT = Path(__file__).resolve().parent / "probe_p0_tip_mint.json"


def load():
    e = {}
    for line in ENV.read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.strip().startswith("#"):
            k, v = line.split("=", 1)
            e[k.strip()] = v.strip()
    return e


def http(method, url, token, key, body=None):
    headers = {"Accept": "application/json", "apikey": key, "Authorization": f"Bearer {token}"}
    data = None
    if body is not None and method != "GET":
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
            return {"ok": True, "status": resp.status, "body": parsed}
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            parsed = raw
        return {"ok": False, "status": e.code, "body": parsed}


def main():
    env = load()
    anon, svc = env["SUPABASE_ANON_KEY"], env["SUPABASE_SERVICE_ROLE_KEY"]
    b = http("POST", AUTH + "token?grant_type=password", anon, anon, {"email": env["LIVE_OPS_TEST_BUYER_EMAIL"], "password": env["LIVE_OPS_TEST_BUYER_PASSWORD"]})
    bj, bid = b["body"]["access_token"], b["body"]["user"]["id"]
    s = http("POST", AUTH + "token?grant_type=password", anon, anon, {"email": env["LIVE_OPS_TEST_SELLER_EMAIL"], "password": env["LIVE_OPS_TEST_SELLER_PASSWORD"]})
    sj, sid = s["body"]["access_token"], s["body"]["user"]["id"]

    def wallet(uid):
        r = http("GET", REST + f"wallets?id=eq.{uid}&select=id,balance,stripe_account_id,updated_at", svc, svc)
        return (r.get("body") or [{}])[0]

    def tx(uid, n=5):
        r = http("GET", REST + f"wallet_transactions?wallet_id=eq.{uid}&order=created_at.desc&limit={n}", svc, svc)
        return r.get("body")

    tests = []
    w0 = wallet(bid)
    print("START", w0, flush=True)

    # variant 2: new tip, credit 1.00
    ck = http("POST", FN + "create-live-tip-checkout", bj, anon, {"seller_id": sid, "amount_eur": 1})
    tips = http("GET", REST + f"live_tips?buyer_id=eq.{bid}&order=created_at.desc&limit=1", svc, svc)
    tip = (tips.get("body") or [{}])[0]
    tip_id = tip.get("id")
    r1 = http("POST", REST + "rpc/batata_wallet_apply_tip_once", bj, anon, {
        "p_wallet_id": bid, "p_tip_id": tip_id, "p_amount": 1.00, "p_type": "venda", "p_description": "rt-d repro 1eur",
    })
    w1 = wallet(bid)
    tests.append({"name": "repro_credit_1", "tip": tip, "rpc": r1, "w0": w0, "w1": w1})
    print("repro1", r1, w0.get("balance"), "->", w1.get("balance"), flush=True)

    # duplicate same tip
    r2 = http("POST", REST + "rpc/batata_wallet_apply_tip_once", bj, anon, {
        "p_wallet_id": bid, "p_tip_id": tip_id, "p_amount": 1.00, "p_type": "venda", "p_description": "rt-d repro 1eur",
    })
    w2 = wallet(bid)
    tests.append({"name": "duplicate_same_tip_desc", "rpc": r2, "w2": w2})
    print("dup", r2.get("body"), w2.get("balance"), flush=True)

    # different description = second credit?
    r3 = http("POST", REST + "rpc/batata_wallet_apply_tip_once", bj, anon, {
        "p_wallet_id": bid, "p_tip_id": tip_id, "p_amount": 3.00, "p_type": "reembolso", "p_description": "rt-d other desc",
    })
    w3 = wallet(bid)
    tests.append({"name": "second_credit_other_type_desc", "rpc": r3, "w3": w3})
    print("second", r3.get("body"), w3.get("balance"), flush=True)

    # payout minted funds (TEST transfer)
    w_before_pay = wallet(bid)
    pay = http("POST", FN + "create-connect-account", bj, anon, {
        "user_id": bid, "amount": 100, "idempotency_key": f"rt_d_p0_payout_{int(time.time())}_xxxx",
    })
    w_after_pay = wallet(bid)
    tests.append({"name": "payout_minted_100cents", "pay": pay, "before": w_before_pay, "after": w_after_pay})
    print("payout", pay.get("status"), pay.get("body"), w_before_pay.get("balance"), "->", w_after_pay.get("balance"), flush=True)

    tests.append({"recent_tx": tx(bid, 8)})

    OUT.write_text(json.dumps({"buyer": bid, "tests": tests}, indent=2, default=str), encoding="utf-8")
    print("WROTE", OUT)


if __name__ == "__main__":
    main()
