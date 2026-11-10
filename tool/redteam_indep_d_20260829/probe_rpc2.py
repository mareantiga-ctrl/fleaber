#!/usr/bin/env python3
"""Prove or refute JWT-callable wallet_apply_tip_once / raffle draw / mark sold."""
from __future__ import annotations

import json
import time
import urllib.error
import urllib.request
from pathlib import Path

ENV = Path(__file__).resolve().parents[1] / "live_ops_staging.env"
BASE = "https://fxdknzrqjenzqcvnwqqq.supabase.co"
REST, AUTH, FN = BASE + "/rest/v1/", BASE + "/auth/v1/", BASE + "/functions/v1/"
OUT = Path(__file__).resolve().parent / "probe_rpc2.json"


def load():
    e = {}
    for line in ENV.read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.strip().startswith("#"):
            k, v = line.split("=", 1)
            e[k.strip()] = v.strip()
    return e


def http(method, url, token, key, body=None, prefer=None):
    headers = {"Accept": "application/json", "apikey": key, "Authorization": f"Bearer {token}"}
    if prefer:
        headers["Prefer"] = prefer
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
            return {"ok": True, "status": resp.status, "body": parsed, "raw": raw[:1500]}
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            parsed = raw
        return {"ok": False, "status": e.code, "body": parsed, "raw": raw[:1500]}


def main():
    env = load()
    anon, svc = env["SUPABASE_ANON_KEY"], env["SUPABASE_SERVICE_ROLE_KEY"]
    b = http("POST", AUTH + "token?grant_type=password", anon, anon, {"email": env["LIVE_OPS_TEST_BUYER_EMAIL"], "password": env["LIVE_OPS_TEST_BUYER_PASSWORD"]})
    s = http("POST", AUTH + "token?grant_type=password", anon, anon, {"email": env["LIVE_OPS_TEST_SELLER_EMAIL"], "password": env["LIVE_OPS_TEST_SELLER_PASSWORD"]})
    bj, bid = b["body"]["access_token"], b["body"]["user"]["id"]
    sj, sid = s["body"]["access_token"], s["body"]["user"]["id"]

    def obs(path):
        return http("GET", REST + path, svc, svc)

    def rpc(tok, name, params):
        return http("POST", REST + "rpc/" + name, tok, anon, params)

    out = []

    w0b = obs(f"wallets?id=eq.{bid}&select=*")
    w0s = obs(f"wallets?id=eq.{sid}&select=*")
    print("wallets", w0b["body"], w0s["body"], flush=True)

    # create pending tip via edge
    tip_ck = http("POST", FN + "create-live-tip-checkout", bj, anon, {"seller_id": sid, "amount_eur": 2})
    print("tip checkout", tip_ck["status"], json.dumps(tip_ck.get("body"), default=str)[:300], flush=True)
    tips = obs(f"live_tips?buyer_id=eq.{bid}&order=created_at.desc&limit=3")
    print("tips", tips["body"], flush=True)
    tip_id = None
    if isinstance(tips.get("body"), list) and tips["body"]:
        tip_id = tips["body"][0]["id"]

    if tip_id:
        r = rpc(bj, "batata_wallet_apply_tip_once", {
            "p_wallet_id": bid,
            "p_tip_id": tip_id,
            "p_amount": 50,
            "p_type": "venda",
            "p_description": "rt-d mint via tip",
        })
        w1b = obs(f"wallets?id=eq.{bid}&select=balance,updated_at")
        out.append({"name": "apply_tip_once_self_50", "http": r["status"], "body": r.get("body"), "bal_before": w0b.get("body"), "bal_after": w1b.get("body")})
        print("apply self", r["status"], r.get("body"), "bal", w1b.get("body"), flush=True)

        r = rpc(bj, "batata_wallet_apply_tip_once", {
            "p_wallet_id": sid,
            "p_tip_id": tip_id,
            "p_amount": 50,
            "p_type": "venda",
            "p_description": "rt-d mint seller",
        })
        w1s = obs(f"wallets?id=eq.{sid}&select=balance,updated_at")
        out.append({"name": "apply_tip_once_seller_50", "http": r["status"], "body": r.get("body"), "bal_after": w1s.get("body")})
        print("apply seller", r["status"], r.get("body"), "bal", w1s.get("body"), flush=True)

        r = rpc(bj, "batata_settle_live_tip_from_stripe", {
            "p_tip_id": tip_id, "p_stripe_session_id": "cs_test_fake", "p_paid_amount_cents": 200,
        })
        out.append({"name": "settle_tip_fake_session", "http": r["status"], "body": r.get("body")})

    # live items
    items = obs("live_items?select=id,live_id,seller_id,status,price&limit=5")
    print("items", items.get("body"), flush=True)
    if isinstance(items.get("body"), list) and items["body"]:
        iid = items["body"][0]["id"]
        r = rpc(bj, "batata_mark_live_item_sold", {"p_live_item_id": iid})
        after = obs(f"live_items?id=eq.{iid}&select=id,status")
        out.append({"name": "buyer_mark_sold", "item": iid, "http": r["status"], "body": r.get("body"), "after": after.get("body")})
        print("mark sold", r["status"], r.get("body"), after.get("body"), flush=True)

    raffles = obs("live_raffles?select=id,live_id,status,seller_id&limit=5")
    print("raffles", raffles.get("body"), flush=True)
    if isinstance(raffles.get("body"), list) and raffles["body"]:
        rid = raffles["body"][0]["id"]
        r = rpc(bj, "batata_draw_live_raffle_winners", {"p_raffle_id": rid})
        out.append({"name": "buyer_draw_winners", "raffle": rid, "http": r["status"], "body": r.get("body")})
        print("draw", r["status"], r.get("body"), flush=True)
        r = rpc(bj, "batata_activate_live_raffle", {"p_raffle_id": rid})
        out.append({"name": "buyer_activate_raffle", "http": r["status"], "body": r.get("body")})
        r = rpc(bj, "batata_create_raffle_prize_order", {"p_raffle_id": rid, "p_winner_uid": bid, "p_rank": 1})
        out.append({"name": "buyer_prize_order", "http": r["status"], "body": r.get("body")})
        print("prize", r["status"], r.get("body"), flush=True)

    # review on MB WAY pago
    mb = obs("orders?payment_method=eq.MB WAY&status=eq.pago&buyer_id=eq." + bid + "&select=id,status,product_id&limit=1")
    print("mb pago", mb.get("body"), flush=True)
    if isinstance(mb.get("body"), list) and mb["body"]:
        oid = mb["body"][0]["id"]
        r = http("POST", REST + "reviews", bj, anon, {
            "target_id": sid, "buyer_id": bid, "stars": 5, "comment": "rt-d mbway",
            "target_type": "seller", "order_id": oid, "author_role": "buyer",
        }, prefer="return=representation")
        out.append({"name": "review_on_mbway_pago", "http": r["status"], "body": r.get("body")})
        print("review", r["status"], r.get("body"), flush=True)

    OUT.write_text(json.dumps({"tests": out, "w0b": w0b.get("body"), "w0s": w0s.get("body")}, indent=2, default=str), encoding="utf-8")
    print("WROTE", OUT)


if __name__ == "__main__":
    main()
