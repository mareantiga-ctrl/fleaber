# Follow-up: JWT debit/clawback grants, dispute-before-release partials, chat delete proof, payout edge.
import json, ssl, time, uuid, urllib.request, urllib.error
from pathlib import Path

ENV_PATH = Path(r"c:\Users\Casa\Desktop\Fleaber\fleaber\tool\live_ops_staging.env")
OUT_PATH = Path(r"c:\Users\Casa\Desktop\Fleaber\fleaber\tool\reports\REAUDITORIA_DC_FOLLOWUP_2026-08-27.json")
BASE = "https://fxdknzrqjenzqcvnwqqq.supabase.co"
ctx = ssl.create_default_context()
env = {}
for line in ENV_PATH.read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    k, v = line.split("=", 1)
    env[k.strip()] = v.strip()
ANON = env["SUPABASE_ANON_KEY"]
SVC = env["SUPABASE_SERVICE_ROLE_KEY"]
TAG = f"RAF-{int(time.time())}"

def http(method, url, token, body=None, prefer="return=representation"):
    data = None if body is None else json.dumps(body).encode()
    h = {"apikey": ANON, "Authorization": f"Bearer {token}"}
    if prefer:
        h["Prefer"] = prefer
    if data is not None:
        h["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=h, method=method)
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=90) as resp:
            return resp.status, resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:
        return 0, str(e)

def rest(method, path, token, qs="", body=None):
    url = f"{BASE}/rest/v1/{path}" + (f"?{qs}" if qs else "")
    return http(method, url, token, body)

def fn(name, token, args):
    return rest("POST", f"rpc/{name}", token, body=args)

def edge(name, token, body):
    return http("POST", f"{BASE}/functions/v1/{name}", token, body, prefer=None)

def auth(email, password):
    last = None
    for i in range(4):
        try:
            st, raw = http("POST", f"{BASE}/auth/v1/token?grant_type=password", ANON,
                           {"email": email, "password": password}, prefer=None)
            j = json.loads(raw)
            return j["access_token"], j["user"]["id"]
        except Exception as e:
            last = e
            time.sleep(2)
    raise last

def jload(raw):
    try:
        return json.loads(raw)
    except Exception:
        return raw

def first(raw):
    o = jload(raw)
    if isinstance(o, list) and o:
        return o[0]
    if isinstance(o, dict):
        return o
    return {}

def bal(token, uid):
    st, raw = rest("GET", "wallets", token, f"id=eq.{uid}&select=balance")
    try:
        return float(first(raw).get("balance"))
    except Exception:
        return None

def rec(i, **k):
    rows.append({"id": i, **k})
    print(f"[{i}] {k.get('verdict')} {str(k.get('detail',''))[:300]}")

def ledger(oid):
    st, raw = rest("GET", "wallet_transactions", SVC,
                   f"order_id=eq.{oid}&select=type,amount,wallet_id,description&order=created_at.asc")
    return jload(raw) if isinstance(jload(raw), list) else []

rows = []
BT, BID = auth(env["LIVE_OPS_TEST_BUYER_EMAIL"], env["LIVE_OPS_TEST_BUYER_PASSWORD"])
ST, SID = auth(env["LIVE_OPS_TEST_SELLER_EMAIL"], env["LIVE_OPS_TEST_SELLER_PASSWORD"])
W0B, W0S = bal(BT, BID), bal(ST, SID)
created = {"p": [], "o": [], "d": [], "r": [], "m": []}

def set_bal(uid, v):
    rest("PATCH", "wallets", SVC, f"id=eq.{uid}", {"balance": round(float(v), 2)})

st, raw = rest("POST", "products", ST, body={
    "seller_id": SID, "title": f"{TAG}", "price": 3, "quantity": 30,
    "list_on_marketplace": False, "available_for_live": True, "is_sold": False,
})
P = first(raw).get("id")
created["p"].append(P)

def nord(price=3.0):
    st, raw = rest("POST", "orders", BT, body={
        "buyer_id": BID, "seller_id": SID, "product_id": P, "quantity": 1,
        "price_total": price, "status": "reserva_pendente", "payment_method": "MB WAY",
        "shipping_method": "mao",
    })
    oid = first(raw).get("id")
    created["o"].append(oid)
    return oid

def capture(oid, cents=300):
    rest("PATCH", "orders", ST, f"id=eq.{oid}", {"status": "pago"})
    rest("PATCH", "orders", SVC, f"id=eq.{oid}", {"amount_paid_cents": cents})

rec("fu_setup", verdict="OK", detail=f"w0b={W0B} w0s={W0S} p={P}")

# ---- JWT debit any wallet? (stop after one proof) ----
s_before = bal(ST, SID)
st, raw = fn("batata_debit_wallet_once", BT, {
    "p_wallet_id": SID, "p_order_id": str(uuid.uuid4()), "p_amount": 1.00,
    "p_description": f"hostile-debit-{TAG}",
})
s_after = bal(ST, SID)
delta = None if s_before is None or s_after is None else round(s_after - s_before, 2)
rec("JWT_debit_seller_wallet",
    verdict="P0_OPEN" if (st == 200 and raw.strip() == "true" and delta is not None and delta < -0.01) else (
        "CALLABLE_NO_EFFECT" if st == 200 else "BLOCKED"),
    detail=f"http={st} body={raw[:80]} seller {s_before}->{s_after} delta={delta}")
# restore immediately if drained
if delta is not None and delta < 0:
    set_bal(SID, s_before)

st, raw = fn("batata_debit_wallet_once", BT, {
    "p_wallet_id": BID, "p_order_id": str(uuid.uuid4()), "p_amount": 0.50,
    "p_description": f"self-debit-{TAG}",
})
rec("JWT_debit_self", verdict="INFO", detail=f"http={st} {raw[:60]} b={bal(BT,BID)}")
set_bal(BID, W0B)

# ---- JWT clawback on released order (buyer) ----
oid_cb = nord()
capture(oid_cb)
rest("PATCH", "orders", BT, f"id=eq.{oid_cb}", {"status": "concluido"})
st, raw = rest("POST", "reviews", BT, body={"order_id": oid_cb, "buyer_id": BID, "stars": 5, "comment": TAG})
rid = first(raw).get("id")
if rid:
    created["r"].append(rid)
s_rel = bal(ST, SID)
st, raw = fn("batata_clawback_seller_wallet_for_order", BT, {"p_order_id": oid_cb})
s_cb = bal(ST, SID)
lg = ledger(oid_cb)
rec("JWT_clawback_after_release",
    verdict="P1_OPEN" if (s_cb is not None and s_rel is not None and s_cb < s_rel - 0.01) else "NO_EFFECT",
    detail=f"http={st} body={raw[:80]} seller {s_rel}->{s_cb} ledger={lg}")

# seller JWT clawback own order
oid_cb2 = nord()
capture(oid_cb2)
rest("PATCH", "orders", BT, f"id=eq.{oid_cb2}", {"status": "concluido"})
st, raw = rest("POST", "reviews", BT, body={"order_id": oid_cb2, "buyer_id": BID, "stars": 5, "comment": TAG+"2"})
if first(raw).get("id"):
    created["r"].append(first(raw).get("id"))
s_rel = bal(ST, SID)
st, raw = fn("batata_clawback_seller_wallet_for_order", ST, {"p_order_id": oid_cb2})
s_cb = bal(ST, SID)
rec("JWT_seller_clawback_own",
    verdict="OPEN" if (s_cb is not None and s_rel is not None and s_cb < s_rel - 0.01) else "NO_EFFECT",
    detail=f"http={st} {raw[:60]} seller {s_rel}->{s_cb} ledger={ledger(oid_cb2)}")

# ---- Partial: dispute BEFORE review ----
oid_p = nord()
capture(oid_p)
rest("PATCH", "orders", BT, f"id=eq.{oid_p}", {"status": "concluido"})
st, raw = rest("POST", "order_disputes", BT, body={
    "order_id": oid_p, "buyer_id": BID, "reason": "outro", "description": TAG,
})
did = first(raw).get("id")
rec("DISP_insert_before_review", verdict="OK" if did else "FAIL",
    detail=f"http={st} {raw[:160]}")
if did:
    created["d"].append(did)
    st, raw = rest("PATCH", "order_disputes", ST, f"id=eq.{did}", {
        "seller_refund_percent": 40, "seller_offer_type": "partial_refund",
    })
    rec("DISP_seller_set_40", verdict="INFO",
        detail=f"http={st} pct={first(raw).get('seller_refund_percent')} set_by={first(raw).get('seller_offer_set_by')} type={first(raw).get('seller_offer_type')}")
    # GET as seller to see row
    st, raw = rest("GET", "order_disputes", ST, f"id=eq.{did}&select=seller_refund_percent,seller_offer_type,seller_offer_set_by,status")
    rec("DISP_row", verdict="INFO", detail=raw[:240])

# A) partial RPC before release
s0, b0 = bal(ST, SID), bal(BT, BID)
st, raw = fn("batata_process_partial_refund_dispute", BT, {"p_order_id": oid_p})
s1, b1 = bal(ST, SID), bal(BT, BID)
rec("PARTIAL_before_release", verdict="INFO",
    detail=f"http={st} {raw[:180]} seller {s0}->{s1} buyer {b0}->{b1} ledger={ledger(oid_p)}")

# try review after partial
st, raw = rest("POST", "reviews", BT, body={"order_id": oid_p, "buyer_id": BID, "stars": 5, "comment": TAG+"p"})
if first(raw).get("id"):
    created["r"].append(first(raw).get("id"))
s2, b2 = bal(ST, SID), bal(BT, BID)
rec("RELEASE_after_partial",
    verdict="OVER" if ((s2 or 0)-(s0 or 0)+(b2 or 0)-(b0 or 0)) > 3.01 else "OK",
    detail=f"rev_http={st} seller {s0}->{s1}->{s2} buyer {b0}->{b1}->{b2} ledger={ledger(oid_p)}")

# B) new order: dispute, seller 50%, THEN review, THEN partial RPC
oid_p2 = nord()
capture(oid_p2)
rest("PATCH", "orders", BT, f"id=eq.{oid_p2}", {"status": "concluido"})
st, raw = rest("POST", "order_disputes", BT, body={
    "order_id": oid_p2, "buyer_id": BID, "reason": "outro", "description": TAG+"b",
})
did2 = first(raw).get("id")
if did2:
    created["d"].append(did2)
    rest("PATCH", "order_disputes", ST, f"id=eq.{did2}", {
        "seller_refund_percent": 50, "seller_offer_type": "partial_refund",
    })
st, raw = rest("POST", "reviews", BT, body={"order_id": oid_p2, "buyer_id": BID, "stars": 5, "comment": TAG+"b"})
if first(raw).get("id"):
    created["r"].append(first(raw).get("id"))
s0, b0 = bal(ST, SID), bal(BT, BID)
st, raw = fn("batata_process_partial_refund_dispute", BT, {"p_order_id": oid_p2})
s1, b1 = bal(ST, SID), bal(BT, BID)
lg = ledger(oid_p2)
gross = 0.0
for t in lg:
    if (t.get("type") or "") in ("venda", "reembolso"):
        gross += float(t.get("amount") or 0)
    if (t.get("type") or "") == "estorno":
        gross -= float(t.get("amount") or 0)
rec("PARTIAL_after_release_preexisting_dispute",
    verdict="OVER_CAPTURE" if gross > 3.01 else "CLOSED",
    detail=f"http={st} {raw[:180]} seller {s0}->{s1} buyer {b0}->{b1} gross_led={round(gross,2)} ledger={lg}")

# C) 100% partial after release
oid_p3 = nord()
capture(oid_p3)
rest("PATCH", "orders", BT, f"id=eq.{oid_p3}", {"status": "concluido"})
st, raw = rest("POST", "order_disputes", BT, body={
    "order_id": oid_p3, "buyer_id": BID, "reason": "outro", "description": TAG+"c",
})
did3 = first(raw).get("id")
if did3:
    created["d"].append(did3)
    rest("PATCH", "order_disputes", ST, f"id=eq.{did3}", {
        "seller_refund_percent": 100, "seller_offer_type": "partial_refund",
    })
rest("POST", "reviews", BT, body={"order_id": oid_p3, "buyer_id": BID, "stars": 5, "comment": TAG+"c"})
s0, b0 = bal(ST, SID), bal(BT, BID)
st, raw = fn("batata_process_partial_refund_dispute", BT, {"p_order_id": oid_p3})
s1, b1 = bal(ST, SID), bal(BT, BID)
rec("PARTIAL100_after_release", verdict="INFO",
    detail=f"http={st} {raw[:160]} seller {s0}->{s1} buyer {b0}->{b1} ledger={ledger(oid_p3)}")

# ---- Chat delete proof ----
st, raw = rest("GET", "chats", BT, f"or=(and(user_a.eq.{BID},user_b.eq.{SID}),and(user_a.eq.{SID},user_b.eq.{BID}))&select=id&limit=1")
chat = first(raw).get("id")
st, raw = rest("POST", "chat_messages", ST, body={
    "chat_id": chat, "sender_id": SID, "receiver_id": BID, "text": f"keep-{TAG}",
})
mid = first(raw).get("id")
created["m"].append(mid)
st_del, raw_del = rest("DELETE", "chat_messages", BT, f"id=eq.{mid}")
st_g, raw_g = rest("GET", "chat_messages", BT, f"id=eq.{mid}&select=id,text,sender_id")
still = first(raw_g).get("id")
rec("CHAT_delete_others_proof",
    verdict="OPEN" if not still else "CLOSED_RLS_EMPTY",
    detail=f"del_http={st_del} del_body={raw_del[:40]} get={raw_g[:120]}")

# ---- payout edge JWT (do not complete if it would need real connect; record error) ----
st, raw = edge("create-connect-account", ST, {
    "action": "payout", "amount_cents": 100, "idempotency_key": f"raf-{TAG}-pay",
})
rec("PAYOUT_edge_seller_1eur", verdict="INFO", detail=f"http={st} {raw[:240]}")
st, raw = fn("batata_wallet_payout_debit", BT, {
    "p_user_id": SID, "p_amount_cents": 100, "p_idempotency_key": f"raf-{TAG}-jwt",
})
rec("PAYOUT_debit_jwt", verdict="INFO", detail=f"http={st} {raw[:160]}")

# leftover hostile estorno rows
st, raw = rest("GET", "wallet_transactions", SVC,
               f"description=like.*{TAG}*&select=id,wallet_id,type,amount,description")
rec("LEFTOVER_hostile_tx", verdict="INFO", detail=raw[:300])

# cleanup
set_bal(BID, W0B)
set_bal(SID, W0S)
for rid in created["r"]:
    rest("DELETE", "reviews", SVC, f"id=eq.{rid}")
rest("DELETE", "reviews", SVC, f"comment=like.{TAG}*")
for did in created["d"]:
    rest("DELETE", "order_disputes", SVC, f"id=eq.{did}")
for mid in created["m"]:
    rest("DELETE", "chat_messages", SVC, f"id=eq.{mid}")
rest("DELETE", "wallet_transactions", SVC, f"description=like.*hostile-debit*")
rest("DELETE", "wallet_transactions", SVC, f"description=like.*self-debit*")
rest("DELETE", "wallet_transactions", SVC, f"description=like.*{TAG}*")
for oid in created["o"]:
    rest("DELETE", "wallet_transactions", SVC, f"order_id=eq.{oid}")
    rest("DELETE", "fleaber_commissions", SVC, f"order_id=eq.{oid}")
    rest("DELETE", "orders", SVC, f"id=eq.{oid}")
for pid in created["p"]:
    rest("DELETE", "products", SVC, f"id=eq.{pid}")

rec("fu_cleanup", verdict="RESTORED" if bal(BT,BID)==W0B and bal(ST,SID)==W0S else "DRIFT",
    detail=f"b {W0B}->{bal(BT,BID)} s {W0S}->{bal(ST,SID)}")
OUT_PATH.write_text(json.dumps({"tag": TAG, "rows": rows}, indent=2, default=str), encoding="utf-8")
print("WROTE", OUT_PATH)
