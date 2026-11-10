#!/usr/bin/env python3
"""Pass 2/3 follow-up: anti-FP, reviews stars, helpers, tips, cross-user, Stripe observe."""
from __future__ import annotations

import json
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]
ENV_PATH = ROOT / "tool" / "live_ops_staging.env"
OUT = Path(__file__).resolve().parent / "out"
STAMP = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def load_env(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        t = line.strip()
        if not t or t.startswith("#") or "=" not in t:
            continue
        k, v = t.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def norm_url(raw: str) -> str:
    u = raw.strip().rstrip("/")
    for suf in ("/rest/v1", "/auth/v1", "/functions/v1"):
        if u.endswith(suf):
            u = u[: -len(suf)].rstrip("/")
    return u


def http(method: str, url: str, headers: dict[str, str], body=None, timeout: int = 45) -> dict:
    data = None
    hdrs = dict(headers)
    if body is not None and method not in ("GET", "HEAD", "DELETE"):
        data = json.dumps(body).encode("utf-8")
        hdrs.setdefault("Content-Type", "application/json")
    req = Request(url, data=data, headers=hdrs, method=method)
    try:
        with urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
            text = raw.decode("utf-8", "replace")
            try:
                parsed = json.loads(text) if text else None
            except json.JSONDecodeError:
                parsed = text
            return {"http": resp.status, "body": parsed, "text": text[:12000],
                    "headers": {k.lower(): v for k, v in resp.headers.items()}}
    except HTTPError as e:
        raw = e.read()
        text = raw.decode("utf-8", "replace")
        try:
            parsed = json.loads(text) if text else None
        except json.JSONDecodeError:
            parsed = text
        return {"http": e.code, "body": parsed, "text": text[:12000],
                "headers": {k.lower(): v for k, v in e.headers.items()} if e.headers else {}}
    except URLError as e:
        return {"http": 0, "body": None, "text": str(e), "headers": {}}


def main() -> int:
    env = load_env(ENV_PATH)
    url = norm_url(env["SUPABASE_URL"])
    anon = env["SUPABASE_ANON_KEY"]
    svc = env["SUPABASE_SERVICE_ROLE_KEY"]
    buyer_id = env["LIVE_OPS_TEST_BUYER_ID"]
    seller_id = env["LIVE_OPS_TEST_SELLER_ID"]
    ANON = {"apikey": anon, "Authorization": f"Bearer {anon}", "Content-Type": "application/json", "Prefer": "return=representation"}
    SVC = {"apikey": svc, "Authorization": f"Bearer {svc}", "Content-Type": "application/json", "Prefer": "return=representation"}

    def sign_in(email: str, password: str) -> str:
        r = http("POST", f"{url}/auth/v1/token?grant_type=password",
                 {"apikey": anon, "Content-Type": "application/json"},
                 {"email": email, "password": password})
        return r["body"]["access_token"]

    buyer_tok = sign_in(env["LIVE_OPS_TEST_BUYER_EMAIL"], env["LIVE_OPS_TEST_BUYER_PASSWORD"])
    seller_tok = sign_in(env["LIVE_OPS_TEST_SELLER_EMAIL"], env["LIVE_OPS_TEST_SELLER_PASSWORD"])
    BH = {"apikey": anon, "Authorization": f"Bearer {buyer_tok}", "Content-Type": "application/json", "Prefer": "return=representation"}
    SH = {"apikey": anon, "Authorization": f"Bearer {seller_tok}", "Content-Type": "application/json", "Prefer": "return=representation"}

    def rest(method, path, headers, body=None):
        return http(method, f"{url}/rest/v1/{path}", headers, body)

    def rpc(fn, params, headers):
        return http("POST", f"{url}/rest/v1/rpc/{fn}", headers, params)

    def edge(fn, headers, body=None, qs="", method="POST"):
        u = f"{url}/functions/v1/{fn}" + (f"?{qs}" if qs else "")
        return http(method, u, headers, body)

    rows = []

    def rec(name, **kw):
        rows.append({"name": name, **kw})
        print(f"{name}: http={kw.get('http')} {str(kw.get('note') or kw.get('text') or '')[:180]}")

    # --- Cross-user: third disposable ---
    email = f"rtb2.{int(time.time())}@staging.fleaber.bot"
    pw = "RtBlind2_" + uuid.uuid4().hex[:10] + "!"
    created = http("POST", f"{url}/auth/v1/admin/users", SVC,
                    {"email": email, "password": pw, "email_confirm": True})
    disp_id = (created.get("body") or {}).get("id") if isinstance(created.get("body"), dict) else None
    disp_tok = sign_in(email, pw) if disp_id else ""
    DH = {"apikey": anon, "Authorization": f"Bearer {disp_tok}", "Content-Type": "application/json", "Prefer": "return=representation"} if disp_tok else {}

    # Known stock=1 product + orders from pass1
    p1 = "8a4c112d-42b8-4daa-a7a3-5c57aea0244e"
    race_orders = [
        "9d73a949-b175-4436-a34c-4dbc89b5ffa2",
        "9b0f9153-e77e-4c08-9ec1-823a39b1e55b",
    ]
    sess_a = "cs_test_a1D9gm1ip1kJy0QvCsReMwW1ezexB2a0ZFewOJSIkdm2AYwhvhJoPKoRWQ"
    sess_b = "cs_test_a1BszTuTJohAYlYpA8fVD1rdHPqPAbtpYVqfC8WuasL3DKqXP5RtFDbFjG"

    # Observe product + orders
    prod = rest("GET", f"products?id=eq.{p1}&select=id,quantity,is_sold,price,seller_id", SVC)
    rec("observe_product", http=prod["http"], body=prod["body"])
    ords = rest("GET", f"orders?id=in.({','.join(race_orders)})&select=id,status,amount_paid_cents,stripe_checkout_session_id,stripe_payment_intent_id,stripe_refund_id,stock_units_applied,buyer_id,quantity,contract_unit_cents", SVC)
    rec("observe_race_orders", http=ords["http"], body=ords["body"])

    # GET settle unpaid sessions (anon)
    for sid, lab in ((sess_a, "A"), (sess_b, "B")):
        r = edge("create-payment-intent", ANON, None, qs=f"checkout_return=success&session_id={sid}", method="GET")
        rec(f"anon_settle_unpaid_{lab}", http=r["http"], text=r["text"][:400])

    # Third user reads lab buyer's order by UUID
    if DH:
        victim_orders = rest("GET", f"orders?buyer_id=eq.{buyer_id}&select=id&limit=3", SVC)
        vids = [x["id"] for x in (victim_orders["body"] or []) if isinstance(x, dict)]
        leaked = []
        for oid in vids[:3]:
            r = rest("GET", f"orders?id=eq.{oid}&select=id,buyer_id,seller_id,price_total,status,stripe_payment_intent_id,amount_paid_cents", DH)
            n = len(r["body"]) if isinstance(r["body"], list) else 0
            if n:
                leaked.append(r["body"][0])
        rec("disp_read_lab_buyer_orders_by_id", http=200, leaked=len(leaked), body=leaked, note="cross-user order read")

        # chats of lab
        chats = rest("GET", f"chats?select=id&limit=5", SVC)
        # pick a chat that is lab buyer-seller
        own = rest("GET", f"chats?or=(user_a.eq.{buyer_id},user_b.eq.{buyer_id})&select=id,user_a,user_b&limit=3", SVC)
        chat_id = None
        if isinstance(own["body"], list) and own["body"]:
            chat_id = own["body"][0]["id"]
        if chat_id:
            r = rest("GET", f"chats?id=eq.{chat_id}&select=*", DH)
            rec("disp_read_lab_chat", http=r["http"], n=len(r["body"]) if isinstance(r["body"], list) else 0, body=r["body"])
            r = rest("GET", f"chat_messages?chat_id=eq.{chat_id}&select=id,content,sender_id,user_id,message&limit=5", DH)
            rec("disp_read_lab_chat_messages", http=r["http"], n=len(r["body"]) if isinstance(r["body"], list) else 0, text=r["text"][:300])

        # disputes / tips of lab
        r = rest("GET", f"order_disputes?buyer_id=eq.{buyer_id}&select=id,order_id,buyer_id,reason,status&limit=3", DH)
        rec("disp_read_lab_disputes", http=r["http"], n=len(r["body"]) if isinstance(r["body"], list) else 0, body=r["body"])
        r = rest("GET", f"live_tips?buyer_id=eq.{buyer_id}&select=id,amount,status,stripe_session_id&limit=3", DH)
        rec("disp_read_lab_tips", http=r["http"], n=len(r["body"]) if isinstance(r["body"], list) else 0, body=r["body"])
        r = rest("GET", f"wallets?id=eq.{buyer_id}&select=id,balance", DH)
        rec("disp_read_lab_wallet", http=r["http"], n=len(r["body"]) if isinstance(r["body"], list) else 0, body=r["body"])

    # seller_helpers
    r = rest("POST", "seller_helpers", BH, {
        "seller_id": seller_id, "helper_id": buyer_id, "user_id": buyer_id,
        "can_manage_raffles": True, "can_manage_reservations": True,
    })
    rec("buyer_insert_seller_helpers", http=r["http"], text=r["text"][:400])
    r = rest("GET", "seller_helpers?select=*&limit=5", BH)
    rec("buyer_select_seller_helpers", http=r["http"], body=r["body"] if isinstance(r["body"], list) else r["text"][:300])

    # reviews with stars
    paid = rest("GET", f"orders?buyer_id=eq.{buyer_id}&status=in.(concluido,entregue)&select=id,status,payment_method,amount_paid_cents,stock_units_applied&limit=8", SVC)
    rec("reviewable_orders", http=paid["http"], body=paid["body"])
    if isinstance(paid["body"], list) and paid["body"]:
        oid = paid["body"][0]["id"]
        existing = rest("GET", f"reviews?order_id=eq.{oid}&select=id,buyer_id,stars,author_role", SVC)
        rec("existing_reviews_for_order", http=existing["http"], body=existing["body"])
        r1 = rest("POST", "reviews", BH, {"order_id": oid, "stars": 5, "comment": f"rt-pass2-a {STAMP}", "author_role": "vendedor"})
        r2 = rest("POST", "reviews", BH, {"order_id": oid, "stars": 1, "comment": f"rt-pass2-b {STAMP}", "author_role": "comprador"})
        rec("review_insert_a", http=r1["http"], text=r1["text"][:400], body=r1["body"])
        rec("review_insert_b_dup", http=r2["http"], text=r2["text"][:400], body=r2["body"])
        # seller reviews same order
        r3 = rest("POST", "reviews", SH, {"order_id": oid, "stars": 5, "comment": f"rt-pass2-seller {STAMP}", "author_role": "vendedor", "buyer_id": seller_id})
        rec("seller_review_buyer_order", http=r3["http"], text=r3["text"][:400])

    # forged tip row
    tip_id = "f09884b9-83dd-4fea-81f7-93a9c7dea390"
    tip = rest("GET", f"live_tips?id=eq.{tip_id}&select=*", SVC)
    rec("observe_forged_session_tip", http=tip["http"], body=tip["body"])
    r = edge("create-live-tip-checkout", ANON, None, qs="session_id=cs_test_forged", method="GET")
    rec("anon_settle_forged_tip_session", http=r["http"], text=r["text"][:400])
    # bind a real checkout session id of an ORDER into a new tip via RPC
    r = rpc("batata_create_live_tip_pending", {
        "p_live_id": None, "p_seller_id": seller_id, "p_amount": 5,
        "p_message": "bind-order-session", "p_stripe_session_id": sess_a,
    }, BH)
    rec("tip_bind_order_checkout_session", http=r["http"], text=r["text"][:400], body=r["body"])
    after_bind = rest("GET", f"live_tips?stripe_session_id=eq.{sess_a}&select=id,amount,status,stripe_session_id,buyer_id", SVC)
    rec("tips_with_order_session", http=after_bind["http"], body=after_bind["body"])

    # live_messages cross
    msgs = rest("GET", "live_messages?select=id,live_id,user_id,buyer_id,sender_id,message,content&limit=15", BH)
    rec("buyer_live_messages_sample", http=msgs["http"], n=len(msgs["body"]) if isinstance(msgs["body"], list) else 0, body=(msgs["body"][:3] if isinstance(msgs["body"], list) else msgs["text"][:400]))
    if isinstance(msgs["body"], list) and msgs["body"]:
        other_lives = {m.get("live_id") for m in msgs["body"] if m.get("live_id")}
        rec("buyer_live_message_live_ids", note=str(list(other_lives)))

    # reservations qty99 pending vs item stock
    li = "a4e89203-f0d6-4df2-a76a-e0143"
    # fetch full id
    lis = rest("GET", f"live_items?live_id=eq.5dd5cfd2-63b1-4cd8-82b1-c888e9dc5234&select=id,quantity,available_qty,stock,price,title&limit=5", SVC)
    rec("live_items_after_res_race", http=lis["http"], body=lis["body"])
    resv = rest("GET", f"live_reservation_requests?live_id=eq.5dd5cfd2-63b1-4cd8-82b1-c888e9dc5234&buyer_id=eq.{buyer_id}&select=id,status,requested_qty,live_item_id&order=created_at.desc&limit=20", SVC)
    rec("buyer_reservations_recent", http=resv["http"], n=len(resv["body"]) if isinstance(resv["body"], list) else 0,
        statuses=[{k: x.get(k) for k in ("id", "status", "requested_qty")} for x in (resv["body"] or [])[:12]] if isinstance(resv["body"], list) else None)

    # seller try accept many
    if isinstance(resv["body"], list) and resv["body"]:
        pending = [x for x in resv["body"] if str(x.get("status")) == "pending"][:5]
        for p in pending[:3]:
            r = rest("PATCH", f"live_reservation_requests?id=eq.{p['id']}", SH, {"status": "accepted"})
            rec("seller_accept_pending_res", id=p["id"], http=r["http"], text=r["text"][:240], body=r["body"])

    # RPC signatures brute
    for fn, variants in {
        "batata_process_live_reservation_request": [
            {"request_id": str(uuid.uuid4()), "action": "accept"},
            {"p_request_id": str(uuid.uuid4()), "p_accept": True},
            {"p_id": str(uuid.uuid4())},
        ],
        "batata_process_partial_refund_dispute": [
            {"p_dispute_id": str(uuid.uuid4())},
            {"p_order_id": str(uuid.uuid4()), "p_percent": 50},
            {"order_id": str(uuid.uuid4())},
        ],
        "batata_finalize_stripe_order_refund": [
            {"order_id": str(uuid.uuid4())},
            {"p_order": str(uuid.uuid4()), "p_refund_id": "re_x"},
        ],
    }.items():
        for params in variants:
            r = rpc(fn, params, BH)
            rec(f"rpc_{fn}_{list(params)[0]}", http=r["http"], text=r["text"][:220])

    # payout ledger observe after races
    led = rest("GET", f"wallet_payout_ledger?user_id=eq.{seller_id}&select=idempotency_key,status,amount_cents,stripe_transfer_id,created_at&order=created_at.desc&limit=10", SVC)
    rec("payout_ledger_recent", http=led["http"], body=led["body"])

    # profiles columns buyer can select on seller
    r = rest("GET", f"profiles?id=eq.{seller_id}&select=id,user_type,display_name,full_name,username,avatar_url,mb_way,iban,phone,email,external_payments_enabled", BH)
    rec("buyer_select_seller_profile_cols", http=r["http"], text=r["text"][:500], body=r["body"])

    # storage objects under product_photos (public listing)
    r = http("POST", f"{url}/storage/v1/object/list/chat_media", BH, {"prefix": "product_photos/", "limit": 20})
    rec("list_product_photos", http=r["http"], n=len(r["body"]) if isinstance(r["body"], list) else 0, sample=(r["body"][:5] if isinstance(r["body"], list) else r["text"][:200]))

    # OpenAPI retry
    oa = http("GET", f"{url}/rest/v1/", {**BH, "Accept": "application/openapi+json, application/json"})
    rec("openapi_retry", http=oa["http"], keys=list(oa["body"].keys())[:20] if isinstance(oa["body"], dict) else type(oa["body"]).__name__, text=str(oa["body"])[:200] if not isinstance(oa["body"], dict) else None)

    # Wallet before/after already known; confirm patch no-op with Prefer count
    r = rest("PATCH", f"wallets?id=eq.{seller_id}", BH, {"balance": 1})
    rec("buyer_patch_seller_wallet_repr", http=r["http"], n=len(r["body"]) if isinstance(r["body"], list) else None, cr=r["headers"].get("content-range"), body=r["body"])

    if disp_id:
        http("DELETE", f"{url}/auth/v1/admin/users/{disp_id}", SVC)

    outp = OUT / f"pass2_{STAMP}.json"
    outp.write_text(json.dumps({"FROZEN_AT": datetime.now(timezone.utc).isoformat(), "rows": rows}, indent=2, default=str), encoding="utf-8")
    print("wrote", outp)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
