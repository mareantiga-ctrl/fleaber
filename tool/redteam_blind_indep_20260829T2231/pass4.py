#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import json, sys, urllib.error, urllib.parse, urllib.request
from pathlib import Path
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

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
    print(k, json.dumps(kw, default=str, ensure_ascii=True)[:600])


def req(method, path, token=None, service=False, body=None, query=None):
    tok = SVC if service else (token or ANON)
    h = {
        "apikey": SVC if service else ANON,
        "Authorization": f"Bearer {tok}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
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

# nested private lists
for prefix in ("chat_uploads", "order_disputes", "order_proofs", f"chat_uploads/{buyer}", f"chat_uploads/{seller}"):
    c, b = req("POST", "/storage/v1/object/list/fleaber_private", token=bj, body={"prefix": prefix, "limit": 10})
    note(f"buyer_list_priv_{prefix.replace('/', '_')}", http=c, n=len(b) if isinstance(b, list) else None, sample=b[:6] if isinstance(b, list) else b)
    c, b = req("POST", "/storage/v1/object/list/fleaber_private", body={"prefix": prefix, "limit": 10})
    note(f"anon_list_priv_{prefix.replace('/', '_')}", http=c, n=len(b) if isinstance(b, list) else None, sample=b[:4] if isinstance(b, list) else b)

c, svc = req("POST", "/storage/v1/object/list/fleaber_private", service=True, body={"prefix": "chat_uploads", "limit": 15})
note("service_chat_uploads", http=c, sample=svc[:10] if isinstance(svc, list) else svc)

# try download first real object as buyer/anon if service found files
if isinstance(svc, list):
    for obj in svc:
        name = obj.get("name")
        if not name or obj.get("id") is None:
            # folder
            c2, inner = req(
                "POST",
                "/storage/v1/object/list/fleaber_private",
                service=True,
                body={"prefix": f"chat_uploads/{name}", "limit": 5},
            )
            note("service_nested", prefix=name, inner=inner[:3] if isinstance(inner, list) else inner)
            if isinstance(inner, list):
                for o2 in inner:
                    if o2.get("id"):
                        path = f"chat_uploads/{name}/{o2['name']}"
                        c, raw = req("GET", f"/storage/v1/object/fleaber_private/{path}")
                        note("anon_dl_private_file", path=path, http=c, raw=str(raw)[:120])
                        c, raw = req("GET", f"/storage/v1/object/fleaber_private/{path}", token=bj)
                        note("buyer_dl_private_file", path=path, http=c, raw=str(raw)[:120])
                        break

# confirm chat foreign
c, msgs = req("GET", "/rest/v1/chat_messages", token=bj, query={"select": "id,chat_id,sender_id", "limit": "10"})
if isinstance(msgs, list):
    for m in msgs[:8]:
        cid = m["chat_id"]
        c2, ch = req("GET", "/rest/v1/chats", token=bj, query={"id": f"eq.{cid}", "select": "id,user_a,user_b"})
        note("msg_chat_visible", msg=m["id"], chat=ch)

# PATCH shipping carrier -> hand directly (same class variant)
import time
ref = str(int(time.time()))
c, p = req(
    "POST",
    "/rest/v1/products",
    token=sj,
    body={
        "seller_id": seller,
        "title": f"RT-SH2 {ref}",
        "price": 15.0,
        "quantity": 2,
        "list_on_marketplace": True,
        "is_sold": False,
        "ref_code": f"RSH2-{ref}",
    },
)
# prefer
c, p = req(
    "POST",
    "/rest/v1/products",
    token=sj,
    body={
        "seller_id": seller,
        "title": f"RT-SH2 {ref}",
        "price": 15.0,
        "quantity": 2,
        "list_on_marketplace": True,
        "is_sold": False,
        "ref_code": f"RSH2-{ref}b",
    },
)
# use Prefer via extra... skip, parse
# redo with header by hacking req - add Prefer in a one-off

def reqp(method, path, token=None, body=None, query=None):
    tok = token or ANON
    h = {
        "apikey": ANON,
        "Authorization": f"Bearer {tok}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }
    q = "?" + urllib.parse.urlencode(query, doseq=True) if query else ""
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(URL + path + q, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            raw = resp.read().decode()
            code = resp.status
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        code = e.code
    try:
        return code, json.loads(raw) if raw else None
    except Exception:
        return code, raw

c, p = reqp(
    "POST",
    "/rest/v1/products",
    token=sj,
    body={
        "seller_id": seller,
        "title": f"RT-SH2 {ref}",
        "price": 15.0,
        "quantity": 2,
        "list_on_marketplace": True,
        "is_sold": False,
        "ref_code": f"RSH2-{ref}c",
    },
)
pid = p[0]["id"] if isinstance(p, list) else None
c, o = reqp(
    "POST",
    "/rest/v1/orders",
    token=bj,
    body={
        "buyer_id": buyer,
        "seller_id": seller,
        "product_id": pid,
        "quantity": 1,
        "status": "reserva_pendente",
        "payment_method": "seguro fleaber",
        "shipping_method": "carrier",
        "price_total": 15,
    },
)
oid = o[0]["id"]
c1, s1 = reqp(
    "POST",
    "/functions/v1/create-payment-intent",
    token=bj,
    body={"buyer_id": buyer, "order_id": oid, "shipping_method": "hand"},
)
note("direct_variant_sealed", amount=(s1 or {}).get("server_amount_cents") if isinstance(s1, dict) else None)
c, o2 = reqp("PATCH", "/rest/v1/orders", token=bj, body={"shipping_method": "hand"}, query={"id": f"eq.{oid}"})
note("patch_carrier_to_hand", http=c, row=o2)
c2, s2 = reqp(
    "POST",
    "/functions/v1/create-payment-intent",
    token=bj,
    body={"buyer_id": buyer, "order_id": oid, "shipping_method": "carrier"},
)
note(
    "direct_variant_after_patch_hand",
    amount=(s2 or {}).get("server_amount_cents") if isinstance(s2, dict) else None,
    ship=(o2[0].get("shipping_method") if isinstance(o2, list) and o2 else None),
)

# bag shipping: two orders hand+carrier
c, oB = reqp(
    "POST",
    "/rest/v1/orders",
    token=bj,
    body={
        "buyer_id": buyer,
        "seller_id": seller,
        "product_id": pid,
        "quantity": 1,
        "status": "reserva_pendente",
        "payment_method": "seguro fleaber",
        "shipping_method": "carrier",
        "price_total": 15,
    },
)
oidb = oB[0]["id"]
c3, s3 = reqp(
    "POST",
    "/functions/v1/create-payment-intent",
    token=bj,
    body={
        "buyer_id": buyer,
        "bag_checkout": True,
        "shipping_method": "hand",
        "bag_lines": [{"order_id": oid}, {"order_id": oidb}],
    },
)
note(
    "bag_two_lines_body_hand",
    http=c3,
    amount=(s3 or {}).get("server_amount_cents") if isinstance(s3, dict) else None,
    body=s3 if isinstance(s3, dict) and not s3.get("checkoutUrl") else {k: (s3 or {}).get(k) for k in ("server_amount_cents", "amount_total", "error")},
)

out = Path("tool/redteam_blind_indep_20260829T2231/out/pass4.json")
out.write_text(json.dumps(LOG, indent=2, default=str), encoding="utf-8")
print("WROTE", out)
