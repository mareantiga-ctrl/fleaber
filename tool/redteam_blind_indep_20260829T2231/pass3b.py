#!/usr/bin/env python3
"""Storage + chat cross-user + remaining tables."""
from __future__ import annotations

import json
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

E = {}
for line in Path("tool/live_ops_staging.env").read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    k, v = line.split("=", 1)
    E[k.strip()] = v.strip()
URL = E["SUPABASE_URL"].replace("/rest/v1/", "").replace("/rest/v1", "").rstrip("/")
ANON, SVC = E["SUPABASE_ANON_KEY"], E["SUPABASE_SERVICE_ROLE_KEY"]
LOG = []


def note(k, **kw):
    LOG.append({"k": k, **kw})
    print(k, str(kw)[:500])


def req(method, path, token=None, service=False, body=None, query=None, extra=None):
    tok = SVC if service else (token or ANON)
    h = {
        "apikey": SVC if service else ANON,
        "Authorization": f"Bearer {tok}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    if extra:
        h.update(extra)
    q = "?" + urllib.parse.urlencode(query, doseq=True) if query else ""
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(URL + path + q, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            raw = resp.read().decode("utf-8", "replace")
            code = resp.status
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        code = e.code
    try:
        parsed = json.loads(raw) if raw else None
    except json.JSONDecodeError:
        parsed = raw
    return code, parsed


def login(email, password):
    c, b = req("POST", "/auth/v1/token?grant_type=password", body={"email": email, "password": password})
    assert c == 200
    return b["access_token"], b["user"]["id"]


bj, buyer = login(E["LIVE_OPS_TEST_BUYER_EMAIL"], E["LIVE_OPS_TEST_BUYER_PASSWORD"])
sj, seller = login(E["LIVE_OPS_TEST_SELLER_EMAIL"], E["LIVE_OPS_TEST_SELLER_PASSWORD"])

# list objects in public chat_media as anon
c, b = req("POST", "/storage/v1/object/list/chat_media", body={"prefix": "", "limit": 20, "offset": 0})
note("anon_list_chat_media", http=c, n=len(b) if isinstance(b, list) else None, body=b if not isinstance(b, list) else b[:8])

c, b = req("POST", "/storage/v1/object/list/fleaber_private", body={"prefix": "", "limit": 20})
note("anon_list_private", http=c, body=b if not isinstance(b, list) else b[:8])

c, b = req("POST", "/storage/v1/object/list/chat_media", token=bj, body={"prefix": "", "limit": 20})
note("buyer_list_chat_media", http=c, n=len(b) if isinstance(b, list) else None, sample=b[:5] if isinstance(b, list) else b)

c, b = req("POST", "/storage/v1/object/list/fleaber_private", token=bj, body={"prefix": "", "limit": 20})
note("buyer_list_private", http=c, n=len(b) if isinstance(b, list) else None, sample=b[:5] if isinstance(b, list) else b)

# if we got a path, try download as anon
objs = None
c, listed = req("POST", "/storage/v1/object/list/chat_media", service=True, body={"prefix": "", "limit": 5})
note("service_list_chat_media", http=c, sample=listed[:5] if isinstance(listed, list) else listed)
if isinstance(listed, list) and listed:
    name = listed[0].get("name")
    c, raw = req("GET", f"/storage/v1/object/public/chat_media/{name}")
    note("anon_get_public_object", http=c, name=name, raw=str(raw)[:150])
    c, raw = req("GET", f"/storage/v1/object/chat_media/{name}")
    note("anon_get_authenticated_object", http=c, name=name, raw=str(raw)[:150])

c, listedp = req("POST", "/storage/v1/object/list/fleaber_private", service=True, body={"prefix": "", "limit": 5})
note("service_list_private", http=c, sample=listedp[:5] if isinstance(listedp, list) else listedp)
if isinstance(listedp, list) and listedp:
    name = listedp[0].get("name")
    # nested?
    path = name
    c, raw = req("GET", f"/storage/v1/object/fleaber_private/{path}")
    note("anon_get_private_object", http=c, name=path, raw=str(raw)[:200])
    c, raw = req("GET", f"/storage/v1/object/fleaber_private/{path}", token=bj)
    note("buyer_get_private_object", http=c, name=path, raw=str(raw)[:200])

# chat_messages: are they only own chats?
c, msgs = req("GET", "/rest/v1/chat_messages", token=bj, query={"select": "id,chat_id,sender_id,text", "limit": "30"})
c2, chats = req("GET", "/rest/v1/chats", token=bj, query={"select": "id,user_a,user_b", "limit": "50"})
own = set()
if isinstance(chats, list):
    own = {x["id"] for x in chats}
foreign_msg = []
if isinstance(msgs, list):
    for m in msgs:
        if m.get("chat_id") not in own:
            foreign_msg.append(m)
note("chat_messages_vs_own_chats", msgs=len(msgs) if isinstance(msgs, list) else msgs, own_chats=len(own), foreign=len(foreign_msg), sample=foreign_msg[:2])

# live_messages other users
c, lm = req("GET", "/rest/v1/live_messages", token=bj, query={"select": "id,live_id,user_id,kind,body", "limit": "10"})
note("live_messages_buyer", n=len(lm) if isinstance(lm, list) else lm, sample=(lm or [])[:2] if isinstance(lm, list) else lm)

c, lm_a = req("GET", "/rest/v1/live_messages", query={"select": "id,live_id,user_id,kind,body", "limit": "5"})
note("live_messages_anon", http=c, n=len(lm_a) if isinstance(lm_a, list) else lm_a, sample=str(lm_a)[:250])

# notifications
c, n = req("GET", "/rest/v1/notifications", token=bj, query={"select": "*", "limit": "5"})
note("notifications_buyer", http=c, n=len(n) if isinstance(n, list) else None, sample=str(n)[:200])
c, n = req("GET", "/rest/v1/notifications", token=sj, query={"select": "*", "limit": "5"})
cross = []
if isinstance(n, list):
    for row in n:
        if row.get("user_id") not in (None, seller) and row.get("recipient_id") not in (None, seller):
            cross.append(row.get("id"))
note("notifications_seller_cross", http=c, cross=cross[:5], sample=str(n)[:200] if not isinstance(n, list) else None)

# order_disputes columns
c, d = req("GET", "/rest/v1/order_disputes", token=bj, query={"select": "*", "limit": "3"})
note("disputes_star", http=c, sample=str(d)[:400])

# favorites / follows
for t in ("favorites", "follows", "user_follows", "product_favorites"):
    c, b = req("GET", f"/rest/v1/{t}", token=bj, query={"select": "*", "limit": "2"})
    note(f"get_{t}", http=c, sample=str(b)[:180])

# stripe_checkout_events as buyer
c, b = req("GET", "/rest/v1/stripe_checkout_events", token=bj, query={"select": "*", "limit": "3"})
note("stripe_events_buyer", http=c, sample=str(b)[:250])
c, b = req("GET", "/rest/v1/stripe_checkout_events")
note("stripe_events_anon", http=c, sample=str(b)[:250])

# wallets other user
c, b = req("GET", "/rest/v1/wallets", token=bj, query={"select": "id,balance", "id": f"eq.{seller}"})
note("buyer_read_seller_wallet", http=c, body=b)

# lives stream as service vs buyer columns
c, b = req("GET", "/rest/v1/lives", token=bj, query={"select": "id,status,mux_stream_key,stream_key,mux_playback_id", "limit": "3"})
note("lives_buyer_cols", http=c, body=b)

# cancel leftover probe orders? leave them; note
out = Path("tool/redteam_blind_indep_20260829T2231/out") / f"pass3b_{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.json"
out.write_text(json.dumps(LOG, indent=2, default=str), encoding="utf-8")
print("WROTE", out)
