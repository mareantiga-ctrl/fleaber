#!/usr/bin/env python3
"""Pass 3 remainder: helpers, messages, tips status, profiles *, leftover checkout session."""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]
ENV_PATH = ROOT / "tool" / "live_ops_staging.env"
OUT = Path(__file__).resolve().parent / "out"


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


def http(method, url, headers, body=None, timeout=45):
    data = None
    hdrs = dict(headers)
    if body is not None and method not in ("GET", "HEAD", "DELETE"):
        data = json.dumps(body).encode()
        hdrs.setdefault("Content-Type", "application/json")
    req = Request(url, data=data, headers=hdrs, method=method)
    try:
        with urlopen(req, timeout=timeout) as resp:
            text = resp.read().decode("utf-8", "replace")
            try:
                parsed = json.loads(text) if text else None
            except json.JSONDecodeError:
                parsed = text
            return {"http": resp.status, "body": parsed, "text": text[:8000]}
    except HTTPError as e:
        text = e.read().decode("utf-8", "replace")
        try:
            parsed = json.loads(text) if text else None
        except json.JSONDecodeError:
            parsed = text
        return {"http": e.code, "body": parsed, "text": text[:8000]}
    except URLError as e:
        return {"http": 0, "body": None, "text": str(e)}


def main():
    env = load_env(ENV_PATH)
    url = norm_url(env["SUPABASE_URL"])
    anon = env["SUPABASE_ANON_KEY"]
    svc = env["SUPABASE_SERVICE_ROLE_KEY"]
    buyer_id = env["LIVE_OPS_TEST_BUYER_ID"]
    seller_id = env["LIVE_OPS_TEST_SELLER_ID"]
    SVC = {"apikey": svc, "Authorization": f"Bearer {svc}", "Content-Type": "application/json", "Prefer": "return=representation"}

    def sign_in(email, password):
        r = http("POST", f"{url}/auth/v1/token?grant_type=password",
                 {"apikey": anon, "Content-Type": "application/json"},
                 {"email": email, "password": password})
        return r["body"]["access_token"]

    BH = {"apikey": anon, "Authorization": f"Bearer {sign_in(env['LIVE_OPS_TEST_BUYER_EMAIL'], env['LIVE_OPS_TEST_BUYER_PASSWORD'])}", "Content-Type": "application/json", "Prefer": "return=representation"}
    SH = {"apikey": anon, "Authorization": f"Bearer {sign_in(env['LIVE_OPS_TEST_SELLER_EMAIL'], env['LIVE_OPS_TEST_SELLER_PASSWORD'])}", "Content-Type": "application/json", "Prefer": "return=representation"}
    rows = []

    def rec(name, r=None, **kw):
        item = {"name": name, **kw}
        if r is not None:
            item["http"] = r["http"]
            item["text"] = (r.get("text") or "")[:400]
            item["body"] = r.get("body")
        rows.append(item)
        print(name, item.get("http"), str(item.get("note") or item.get("text") or "")[:160])

    def rest(method, path, headers, body=None):
        return http(method, f"{url}/rest/v1/{path}", headers, body)

    def rpc(fn, params, headers):
        return http("POST", f"{url}/rest/v1/rpc/{fn}", headers, params)

    def edge(fn, headers, body=None, qs="", method="POST"):
        u = f"{url}/functions/v1/{fn}" + (f"?{qs}" if qs else "")
        return http(method, u, headers, body)

    # profiles * seller as buyer
    r = rest("GET", f"profiles?id=eq.{seller_id}&select=*", BH)
    rec("buyer_select_seller_profile_star", r, note="keys" if isinstance(r["body"], list) and r["body"] else None)
    if isinstance(r["body"], list) and r["body"]:
        rec("seller_profile_keys", note=sorted(r["body"][0].keys()))
        rec("seller_profile_sensitive", note={k: r["body"][0].get(k) for k in r["body"][0] if k in ("mb_way", "iban", "phone", "email", "nif", "stripe_account_id", "user_type")})

    # helpers insert
    r = rest("POST", "seller_helpers", BH, {
        "seller_id": seller_id,
        "helper_user_id": buyer_id,
        "display_name": "rt-blind",
        "invitation_status": "accepted",
        "active": True,
        "permissions": {"can_manage_raffles": True, "can_manage_reservations": True},
    })
    rec("buyer_insert_helper_on_seller", r)
    r = rest("POST", "seller_helpers", SH, {
        "seller_id": seller_id,
        "helper_user_id": buyer_id,
        "display_name": "rt-blind-invite",
        "invitation_status": "pending",
        "permissions": {},
    })
    rec("seller_invite_helper", r)

    # live_messages
    r = rest("GET", "live_messages?select=id,live_id,user_id,message,created_at&limit=15", BH)
    rec("buyer_live_messages", r, n=len(r["body"]) if isinstance(r["body"], list) else None)

    # chat_messages schema
    chats = rest("GET", f"chats?or=(user_a.eq.{buyer_id},user_b.eq.{buyer_id})&select=id&limit=1", BH)
    cid = (chats["body"][0]["id"] if isinstance(chats["body"], list) and chats["body"] else None)
    if cid:
        r = rest("GET", f"chat_messages?chat_id=eq.{cid}&select=*&limit=2", BH)
        rec("chat_messages_sample", r, keys=sorted((r["body"][0].keys() if isinstance(r["body"], list) and r["body"] else [])))

    # tip status patch
    r = rest("PATCH", "live_tips?id=eq.6963304f-abcb-4736-be7d-ba093886dfa2", BH, {"status": "completed", "completed_at": datetime.now(timezone.utc).isoformat()})
    after = rest("GET", "live_tips?id=eq.6963304f-abcb-4736-be7d-ba093886dfa2&select=id,status,stripe_session_id,amount", SVC)
    rec("buyer_patch_tip_completed", r, after=after["body"])

    # leftover paid session from other tab
    sid = "cs_test_a1XKZ38IARekmVOMlG01klhh5s3dBM4HcXRu62Obcs58MOiTSVTr2nKclT"
    r = rest("GET", f"orders?stripe_checkout_session_id=eq.{sid}&select=id,status,amount_paid_cents,stock_units_applied,product_id,quantity", SVC)
    rec("observe_other_tab_session_order", r)
    ev = rest("GET", f"stripe_checkout_events?session_id=eq.{sid}&select=event,created_at&order=created_at.desc&limit=8", SVC)
    rec("observe_other_tab_events", r=ev)

    # stock1 product + all pending orders count
    p1 = "8a4c112d-42b8-4daa-a7a3-5c57aea0244e"
    r = rest("GET", f"orders?product_id=eq.{p1}&status=eq.reserva_pendente&select=id", SVC)
    rec("pending_orders_stock1_product", r, n=len(r["body"]) if isinstance(r["body"], list) else None)
    prod = rest("GET", f"products?id=eq.{p1}&select=id,quantity,is_sold,price", SVC)
    rec("product_stock1_now", prod)

    # wallets after payouts
    rec("wallets_now", rest("GET", f"wallets?id=in.({buyer_id},{seller_id})&select=id,balance", SVC))

    # waitlist / queue tables
    for t in ("live_waitlist", "waitlist", "live_queue", "raffle_entries", "live_raffle_entries"):
        r = rest("GET", f"{t}?select=*&limit=1", BH)
        rec(f"table_{t}", r)

    # anon GET mux playback real live
    lives = rest("GET", "lives?select=id,status,title&limit=3", SVC)
    rec("observe_lives", lives)
    if isinstance(lives["body"], list) and lives["body"]:
        lid = lives["body"][0]["id"]
        r = edge("resolve-mux-playback", {"apikey": anon, "Authorization": f"Bearer {anon}", "Content-Type": "application/json"}, {"live_id": lid})
        rec("anon_resolve_real_live", r)

    # JWT delete other user's order
    r = rest("DELETE", f"orders?id=eq.9d73a949-b175-4436-a34c-4dbc89b5ffa2", BH)
    rec("buyer_delete_own_pending_order", r)
    still = rest("GET", f"orders?id=eq.9d73a949-b175-4436-a34c-4dbc89b5ffa2&select=id,status", SVC)
    rec("order_after_buyer_delete", still)

    outp = OUT / "pass3_remainder.json"
    outp.write_text(json.dumps({"ts": datetime.now(timezone.utc).isoformat(), "rows": rows}, indent=2, default=str), encoding="utf-8")
    print("wrote", outp)


if __name__ == "__main__":
    main()
