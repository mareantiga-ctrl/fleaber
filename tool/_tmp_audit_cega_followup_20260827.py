import json, os, urllib.request, urllib.error, ssl
from pathlib import Path

env = {}
for line in Path(r"c:\Users\Casa\Desktop\Fleaber\fleaber\tool\live_ops_staging.env").read_text(encoding="utf-8").splitlines():
    line=line.strip()
    if not line or line.startswith("#") or "=" not in line: continue
    k,v=line.split("=",1); env[k.strip()]=v.strip()

BASE="https://fxdknzrqjenzqcvnwqqq.supabase.co"
ANON=env["SUPABASE_ANON_KEY"]
SVC=env["SUPABASE_SERVICE_ROLE_KEY"]
ctx=ssl.create_default_context()

def req(method, url, token, body=None, extra=None):
    data=None if body is None else json.dumps(body).encode()
    h={"apikey": ANON, "Authorization": f"Bearer {token}"}
    if extra: h.update(extra)
    if data is not None: h["Content-Type"]="application/json"
    r=urllib.request.Request(url, data=data, headers=h, method=method)
    try:
        with urllib.request.urlopen(r, context=ctx, timeout=30) as resp:
            raw=resp.read().decode("utf-8","replace")
            return resp.status, raw
    except urllib.error.HTTPError as e:
        raw=e.read().decode("utf-8","replace")
        return e.code, raw

def auth(email, pw):
    st, raw = req("POST", f"{BASE}/auth/v1/token?grant_type=password", ANON, {"email":email,"password":pw})
    j=json.loads(raw)
    return j["access_token"], j["user"]["id"]

BT, BID = auth(env["LIVE_OPS_TEST_BUYER_EMAIL"], env["LIVE_OPS_TEST_BUYER_PASSWORD"])
ST, SID = auth(env["LIVE_OPS_TEST_SELLER_EMAIL"], env["LIVE_OPS_TEST_SELLER_PASSWORD"])
out={}

def add(k, st, raw):
    shown = raw[:240].replace("\n"," ")
    out[k]={"status":st,"body":raw[:800]}
    print(f"[{k}] {st} {shown}")

pref={"Prefer":"return=representation"}

st,raw=req("GET", f"{BASE}/rest/v1/products?id=eq.0892ca04-9c67-4990-9dad-02e0cf360811&select=id,quantity,is_sold,title", ST)
add("product_qty", st, raw)

st,raw=req("PATCH", f"{BASE}/rest/v1/wallets?id=eq.{BID}", BT, {"balance": 9999.00}, pref)
add("buyer_patch_wallet", st, raw)

st,raw=req("GET", f"{BASE}/rest/v1/chats?select=id,user_a,user_b&or=(and(user_a.neq.{BID},user_b.neq.{BID}))&limit=2", BT)
add("chats_foreign", st, raw)

st,raw=req("GET", f"{BASE}/rest/v1/chat_messages?select=id,chat_id,sender_id,text&sender_id=neq.{BID}&limit=2", BT)
add("msgs_foreign", st, raw)

st,raw=req("POST", f"{BASE}/rest/v1/chat_messages", BT, {
    "chat_id":"fa1a3f99-03b8-40fc-a923-7964a6dad586",
    "sender_id": SID,
    "receiver_id": BID,
    "text":"audit-cega-spoof"
}, pref)
add("spoof_msg", st, raw)

st,raw=req("POST", f"{BASE}/rest/v1/reviews", BT, {
    "order_id":"d0972f17-ea2d-4457-a4ad-f720aec3f54b",
    "buyer_id": BID,
    "target_id": SID,
    "target_type":"seller",
    "stars":5,
    "author_role":"comprador",
    "comment":"audit-spoof-review"
}, pref)
add("spoof_review", st, raw)

st,raw=req("GET", f"{BASE}/rest/v1/lives?select=id,mux_stream_key,stream_key&limit=1", BT)
add("lives_keys_buyer", st, raw)
st,raw=req("GET", f"{BASE}/rest/v1/lives?select=id,mux_stream_key,stream_key&limit=1", ST)
add("lives_keys_seller", st, raw)
st,raw=req("GET", f"{BASE}/rest/v1/lives?select=id,status&limit=2", BT)
add("lives_safe", st, raw)

st,raw=req("POST", f"{BASE}/rest/v1/rpc/batata_release_seller_wallet_for_order", BT, {"p_order_id":"eec1c79e-20cc-4fb8-8a5b-67e2650efafa"})
add("rpc_release", st, raw)
st,raw=req("POST", f"{BASE}/rest/v1/rpc/batata_process_partial_refund_dispute", BT, {"p_order_id":"eec1c79e-20cc-4fb8-8a5b-67e2650efafa","p_refund_percent":100})
add("rpc_partial", st, raw)
st,raw=req("POST", f"{BASE}/rest/v1/rpc/batata_live_system_message", BT, {"p_live_id":"00000000-0000-0000-0000-000000000001","p_body":"x","p_sender_label":"Sistema"})
add("rpc_sysmsg", st, raw)
st,raw=req("POST", f"{BASE}/rest/v1/rpc/batata_ensure_checkout_product", BT, {"p_live_item_id":"00000000-0000-0000-0000-000000000001"})
add("rpc_ensure", st, raw)

st,raw=req("POST", f"{BASE}/rest/v1/orders", BT, {
    "buyer_id":BID,"seller_id":SID,"product_id":"0892ca04-9c67-4990-9dad-02e0cf360811",
    "quantity":1,"price_total":1.11,"status":"reserva_pendente","payment_method":"MB WAY",
    "shipping_method":"Levantamento em mao"
}, pref)
add("disp_order", st, raw)
oid=None
try:
    oid=json.loads(raw)[0]["id"]
except Exception:
    pass
if oid:
    st,raw=req("PATCH", f"{BASE}/rest/v1/orders?id=eq.{oid}", ST, {"status":"pago"}, pref)
    add("disp_pago", st, raw)
    st,raw=req("PATCH", f"{BASE}/rest/v1/orders?id=eq.{oid}", BT, {"status":"concluido"}, pref)
    add("disp_conc", st, raw)
    st,raw=req("POST", f"{BASE}/rest/v1/order_disputes", BT, {
        "order_id":oid,"buyer_id":BID,"reason":"outro","description":"audit-dispute",
        "seller_refund_percent":100,"seller_offer_type":"partial_refund"
    }, pref)
    add("disp_insert", st, raw)
    st,raw=req("POST", f"{BASE}/rest/v1/rpc/batata_process_partial_refund_dispute", BT, {"p_order_id":oid,"p_refund_percent":1})
    add("disp_rpc", st, raw)
    # read wallets after dispute
    st,raw=req("GET", f"{BASE}/rest/v1/wallets?id=eq.{BID}&select=id,balance", BT)
    add("w_buyer_after_disp", st, raw)

st,raw=req("PATCH", f"{BASE}/rest/v1/profiles?id=eq.{BID}", BT, {"phone_verified_at": None}, pref)
add("cleanup_phone", st, raw)

# if dispute minted, revert again
st,raw=req("GET", f"{BASE}/rest/v1/wallets?id=eq.{BID}&select=balance", BT)
add("w_buyer_final", st, raw)
st,raw=req("GET", f"{BASE}/rest/v1/wallets?id=eq.{SID}&select=balance", ST)
add("w_seller_final", st, raw)

# revert if drifted
try:
    bb=json.loads(out["w_buyer_final"]["body"])[0]["balance"]
    if float(bb)!=10.0:
        st,raw=req("PATCH", f"{BASE}/rest/v1/wallets?id=eq.{BID}", SVC, {"balance":10.00}, pref)
        add("cleanup_buyer_bal", st, raw)
except Exception as e:
    add("cleanup_buyer_err", 0, str(e))
try:
    sb=json.loads(out["w_seller_final"]["body"])[0]["balance"]
    if abs(float(sb)-10.90)>0.001:
        st,raw=req("PATCH", f"{BASE}/rest/v1/wallets?id=eq.{SID}", SVC, {"balance":10.90}, pref)
        add("cleanup_seller_bal", st, raw)
except Exception as e:
    add("cleanup_seller_err", 0, str(e))

Path(r"c:\Users\Casa\Desktop\Fleaber\fleaber\tool\reports\AUDIT_CEGA_INDEP_PROBES_FOLLOWUP_2026-08-27.json").write_text(json.dumps(out, indent=2), encoding="utf-8")
print("WROTE followup json")
