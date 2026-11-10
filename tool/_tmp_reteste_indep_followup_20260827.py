# Follow-up isolated tests: stock restore, live qty=0, capture vs price_total, CPI qty, chat UPDATE.
import json, ssl, time, urllib.request, urllib.error
from pathlib import Path

ENV_PATH = Path(r"c:\Users\Casa\Desktop\Fleaber\fleaber\tool\live_ops_staging.env")
OUT_PATH = Path(r"c:\Users\Casa\Desktop\Fleaber\fleaber\tool\reports\RETESTE_INDEP_P0P1_FOLLOWUP_2026-08-27.json")
BASE = "https://fxdknzrqjenzqcvnwqqq.supabase.co"
ctx = ssl.create_default_context()
env = {}
for line in ENV_PATH.read_text(encoding="utf-8").splitlines():
    line=line.strip()
    if not line or line.startswith("#") or "=" not in line: continue
    k,v=line.split("=",1); env[k.strip()]=v.strip()
ANON=env["SUPABASE_ANON_KEY"]; SVC=env["SUPABASE_SERVICE_ROLE_KEY"]
TAG=f"RT2-{int(time.time())}"

def http(method, url, token, body=None, prefer="return=representation"):
    data=None if body is None else json.dumps(body).encode()
    h={"apikey":ANON,"Authorization":f"Bearer {token}"}
    if prefer: h["Prefer"]=prefer
    if data is not None: h["Content-Type"]="application/json"
    req=urllib.request.Request(url,data=data,headers=h,method=method)
    try:
        with urllib.request.urlopen(req,context=ctx,timeout=45) as resp:
            return resp.status, resp.read().decode("utf-8","replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8","replace")

def rest(method, path, token, qs="", body=None):
    url=f"{BASE}/rest/v1/{path}" + (f"?{qs}" if qs else "")
    return http(method,url,token,body)

def rpc(name, token, args):
    return rest("POST", f"rpc/{name}", token, body=args)

def auth(email, password):
    st,raw=http("POST", f"{BASE}/auth/v1/token?grant_type=password", ANON, {"email":email,"password":password}, prefer=None)
    j=json.loads(raw); return j["access_token"], j["user"]["id"]

def first(raw):
    try:
        o=json.loads(raw)
        if isinstance(o,list) and o: return o[0]
        if isinstance(o,dict): return o
    except Exception:
        pass
    return {}

def bal(token, uid):
    st,raw=rest("GET","wallets",token,f"id=eq.{uid}&select=balance")
    try: return float(first(raw).get("balance"))
    except Exception: return None

rows=[]
def rec(i,**k):
    rows.append({"id":i,**k}); print(f"[{i}] {k.get('verdict')} {str(k.get('detail',''))[:240]}")

BT,BID=auth(env["LIVE_OPS_TEST_BUYER_EMAIL"], env["LIVE_OPS_TEST_BUYER_PASSWORD"])
ST,SID=auth(env["LIVE_OPS_TEST_SELLER_EMAIL"], env["LIVE_OPS_TEST_SELLER_PASSWORD"])
W0B,W0S=bal(BT,BID),bal(ST,SID)
created={"p":[],"o":[],"li":[],"rr":[],"c":[]}

st,raw=rest("POST","products",ST,body={"seller_id":SID,"title":f"ISO-STOCK-{TAG}","price":2.00,"quantity":4,"list_on_marketplace":False,"available_for_live":True,"is_sold":False})
P=first(raw).get("id"); created["p"].append(P)
rec("iso_product", verdict="OK", detail=f"pid={P} qty={first(raw).get('quantity')}")

def nord(extra=None):
    b={"buyer_id":BID,"seller_id":SID,"product_id":P,"quantity":1,"price_total":2.00,"status":"reserva_pendente","payment_method":"MB WAY","shipping_method":"mao"}
    if extra: b.update(extra)
    st,raw=rest("POST","orders",BT,body=b)
    oid=first(raw).get("id"); created["o"].append(oid)
    return oid, first(raw)

def qty():
    st,raw=rest("GET","products",ST,f"id=eq.{P}&select=quantity,is_sold")
    return first(raw).get("quantity"), first(raw).get("is_sold")

oid1, _ = nord()
q0,_=qty()
st,raw=rest("PATCH","orders",ST,f"id=eq.{oid1}",{"status":"pago"})
r=first(raw); q1,_=qty()
rec("iso_pago",verdict="INFO",detail=f"status={r.get('status')} applied={r.get('stock_units_applied')} qty {q0}->{q1} http={st}")
st,raw=rest("PATCH","orders",ST,f"id=eq.{oid1}",{"status":"devolvida"})
r=first(raw); q2,_=qty()
rec("iso_devolvida_restore",verdict="RESTORED" if q2==q0 else "NOT_RESTORED",
    detail=f"qty {q0}->{q1}->{q2} applied_now={r.get('stock_units_applied')} refund_at={r.get('wallet_refund_processed_at')}")
# second devolvida
rest("PATCH","orders",ST,f"id=eq.{oid1}",{"status":"devolvida"})
q3,_=qty()
rec("iso_second_devolvida",verdict="DOUBLE" if q3 is not None and q2 is not None and q3>q2 else "NO_DOUBLE", detail=f"qty={q3}")

# pago when stock 0
st,raw=rest("PATCH","products",ST,f"id=eq.{P}",{"quantity":0})
oid2,_=nord({"quantity":1})
st,raw=rest("PATCH","orders",ST,f"id=eq.{oid2}",{"status":"pago"})
r=first(raw); qz,_=qty()
rec("iso_pago_at_qty0",verdict="PAGO_WITHOUT_STOCK" if r.get("status")=="pago" else "BLOCKED",
    detail=f"http={st} status={r.get('status')} applied={r.get('stock_units_applied')} qty={qz} body={raw[:180]}")

# reset qty 2 for later
rest("PATCH","products",ST,f"id=eq.{P}",{"quantity":2})

# capture formula: svc sets amount_paid_cents=100 (1 EUR), price_total=50, then devolvida
oid3,_=nord({"price_total":50.00})
rest("PATCH","orders",ST,f"id=eq.{oid3}",{"status":"pago"})
st,raw=rest("PATCH","orders",SVC,f"id=eq.{oid3}",{"amount_paid_cents":100})
rec("iso_svc_set_paid_cents",verdict="INFO",detail=f"http={st} paid={first(raw).get('amount_paid_cents')}")
wb=bal(BT,BID)
st,raw=rest("PATCH","orders",ST,f"id=eq.{oid3}",{"status":"devolvida"})
wa=bal(BT,BID)
delta = None if wb is None or wa is None else round(wa-wb,2)
rec("iso_credit_vs_capture_1eur_price50",verdict="OVER_CAPTURE" if delta is not None and delta>1.01 else ("CAPTURE_CAPPED" if delta==1.0 else ("NO_CREDIT" if delta==0 else "INFO")),
    detail=f"delta={delta} w {wb}->{wa} status={first(raw).get('status')} refund_at={first(raw).get('wallet_refund_processed_at')}")

# double credit: concluido+review AND devolvida on captured order
oid4,_=nord({"price_total":3.00})
rest("PATCH","orders",ST,f"id=eq.{oid4}",{"status":"pago"})
rest("PATCH","orders",SVC,f"id=eq.{oid4}",{"amount_paid_cents":300})
rest("PATCH","orders",BT,f"id=eq.{oid4}",{"status":"concluido"})
wb=bal(ST,SID); bb=bal(BT,BID)
st,raw=rest("POST","reviews",BT,body={"order_id":oid4,"buyer_id":BID,"target_id":SID,"stars":5,"author_role":"comprador","comment":"cap"})
ws=bal(ST,SID)
rec("iso_release_on_captured",verdict="INFO",detail=f"rev_http={st} seller {wb}->{ws} body={raw[:80]}")
st,raw=rest("PATCH","orders",ST,f"id=eq.{oid4}",{"status":"devolvida"})
ws2=bal(ST,SID); bb2=bal(BT,BID)
rec("iso_then_devolvida_double",verdict="DOUBLE" if (bb2 is not None and bb is not None and ws is not None and wb is not None and (bb2-bb)>0.01 and (ws-wb)>0.01) else "INFO",
    detail=f"seller {wb}->{ws}->{ws2} buyer {bb}->{bb2} status={first(raw).get('status')}")

# RPC release retry
st,raw=rpc("batata_release_seller_wallet_for_order",BT,{"p_order_id":oid4})
rec("iso_release_retry",verdict="INFO",detail=f"http={st} {raw[:80]}")
st,raw=rpc("batata_refund_buyer_wallet_for_order",BT,{"p_order_id":oid4})
rec("iso_refund_retry",verdict="INFO",detail=f"http={st} {raw[:80]}")

# live qty: set existing marketplace product to 0, call total_qty
st,raw=rest("GET","live_items",ST,"select=id,product_id,item_kind,quantity&item_kind=eq.marketplace_product&limit=5")
items=json.loads(raw) if raw.startswith("[") else []
rec("live_items_sample",verdict="INFO",detail=str(items)[:240])
if items:
    it=items[0]
    pid=it.get("product_id"); li=it.get("id")
    st,raw=rest("GET","products",ST,f"id=eq.{pid}&select=id,quantity,seller_id")
    rec("linked_product",verdict="INFO",detail=raw[:200])
    prow=first(raw)
    # only mutate if seller owns it
    if prow.get("seller_id")==SID:
        oldq=prow.get("quantity")
        rest("PATCH","products",ST,f"id=eq.{pid}",{"quantity":0})
        st,raw=rpc("batata_live_item_total_qty",ST,{"p_live_item_id":li})
        rec("live_qty_when_product_0",verdict="PHANTOM_1" if str(raw).strip() in ("1","1.0") else ("ZERO_OK" if str(raw).strip() in ("0","0.0") else "INFO"),
            detail=f"rpc={raw[:40]} oldq={oldq}")
        # reservation + accept
        st,raw=rest("GET","lives",ST,f"id=eq.{it.get('live_id') if False else ''}&select=id")
        # get live_id from item
        st,raw=rest("GET","live_items",ST,f"id=eq.{li}&select=id,live_id")
        live_id=first(raw).get("live_id")
        st,raw=rest("POST","live_reservation_requests",BT,body={
            "live_id":live_id,"live_item_id":li,"seller_id":SID,"buyer_id":BID,
            "requested_qty":1,"status":"pending","source":"fleaber_live",
        })
        rid=first(raw).get("id")
        rec("resv_on_zero",verdict="INFO",detail=f"http={st} rid={rid} {raw[:120]}")
        if rid:
            created["rr"].append(rid)
            st,raw=rpc("batata_process_live_reservation_request",ST,{"p_request_id":rid,"p_action":"accept"})
            body=first(raw) if isinstance(first(raw),dict) else {}
            rec("accept_on_zero",verdict="EXPLOITABLE" if body.get("ok") is True else ("BLOCKED" if body.get("error") in ("no_stock","qty_exceeds_stock") else "INFO"),
                detail=f"http={st} {raw[:220]}")
            rest("DELETE","live_reservation_requests",SVC,f"id=eq.{rid}")
        rest("PATCH","products",ST,f"id=eq.{pid}",{"quantity":oldq})
    else:
        # still call rpc without mutating others' stock
        st,raw=rpc("batata_live_item_total_qty",ST,{"p_live_item_id":li})
        rec("live_qty_other_seller_item",verdict="INFO",detail=f"prod_qty={prow.get('quantity')} rpc={raw[:40]}")

# create live_item with quantity 0 live_only if constraint allows
st,raw=rest("GET","lives",ST,"select=id,seller_id&limit=3")
lives=json.loads(raw) if raw.startswith("[") else []
own=[x for x in lives if x.get("seller_id")==SID]
if own:
    lid=own[0]["id"]
    st,raw=rest("POST","live_items",ST,body={
        "live_id":lid,"item_kind":"live_only","title":f"zero-only-{TAG}","price":1,
        "quantity":0,"ref_code":f"T{TAG[-5:]}","status":"available",
    })
    rec("create_live_only_qty0",verdict="INFO",detail=f"http={st} {raw[:180]}")
    li2=first(raw).get("id")
    if li2:
        created["li"].append(li2)
        st,raw=rpc("batata_live_item_total_qty",ST,{"p_live_item_id":li2})
        rec("live_only_total_qty0",verdict="PHANTOM_1" if str(raw).strip() in ("1","1.0") else ("ZERO_OK" if str(raw).strip() in ("0","0.0") else "INFO"),
            detail=f"rpc={raw[:40]}")
        st,raw=rest("POST","live_reservation_requests",BT,body={
            "live_id":lid,"live_item_id":li2,"seller_id":SID,"buyer_id":BID,
            "requested_qty":1,"status":"pending","source":"fleaber_live",
        })
        rid=first(raw).get("id")
        if rid:
            created["rr"].append(rid)
            st,raw=rpc("batata_process_live_reservation_request",ST,{"p_request_id":rid,"p_action":"accept"})
            body=json.loads(raw) if raw.startswith("{") else {}
            rec("accept_live_only_qty0",verdict="EXPLOITABLE" if body.get("ok") is True else ("BLOCKED" if body.get("error") in ("no_stock","qty_exceeds_stock") else "INFO"),
                detail=f"{raw[:220]}")

# CPI inflated qty
oid5,_=nord({"quantity":20,"price_total":1.00})
st,raw=http("POST", f"{BASE}/functions/v1/create-payment-intent", BT, {
    "buyer_id": BID, "order_id": oid5, "shipping_method": "Levantamento em mao",
}, prefer=None)
rec("cpi_qty20",verdict="INFO",detail=f"http={st} {raw[:300]}")

# chat UPDATE other participant message: create chat, seller sends, buyer patches
st,raw=rest("POST","chats",BT,body={"user_a":BID,"user_b":SID})
cid=first(raw).get("id"); created["c"].append(cid)
st,raw=rest("POST","chat_messages",ST,body={"chat_id":cid,"sender_id":SID,"text":"seller-msg"})
mid=first(raw).get("id")
st,raw=rest("PATCH","chat_messages",BT,f"id=eq.{mid}",{"text":"buyer-rewrote"})
rec("chat_buyer_rewrite_seller_msg",verdict="OPEN" if first(raw).get("text")=="buyer-rewrote" else "CLOSED",
    detail=f"http={st} text={first(raw).get('text')} {raw[:120]}")

# leftover open policies? select chats count
st,raw=rest("GET","chats",BT,"select=id")
n=len(json.loads(raw)) if raw.startswith("[") else -1
rec("chats_visible_count",verdict="INFO",detail=f"n={n} http={st}")

# tip apply with null tip? already 409. Try without tip_id if signature allows
st,raw=rpc("batata_send_live_tip_from_wallet",BT,{"p_live_id": own[0]["id"] if own else None, "p_seller_id": SID, "p_amount": 1})
rec("rpc_wallet_tip",verdict="INFO",detail=f"http={st} {raw[:180]}")

# cleanup
rest("PATCH","wallets",SVC,f"id=eq.{BID}",{"balance":W0B})
rest("PATCH","wallets",SVC,f"id=eq.{SID}",{"balance":W0S})
for t,ids in [("live_reservation_requests",created["rr"]),("live_items",created["li"]),("orders",created["o"]),("products",created["p"])]:
    for i in ids:
        if i: rest("DELETE",t,SVC,f"id=eq.{i}")
if cid:
    rest("DELETE","chat_messages",SVC,f"chat_id=eq.{cid}")
    rest("DELETE","chats",SVC,f"id=eq.{cid}")
rec("cleanup",verdict="DONE",detail=f"restored wallets {W0B}/{W0S}")
st,raw=rest("GET","wallets",BT,f"id=eq.{BID}&select=balance")
rec("verify_b",verdict="OK" if abs(float(first(raw).get("balance",-1))-W0B)<0.01 else "DRIFT", detail=raw)
st,raw=rest("GET","wallets",ST,f"id=eq.{SID}&select=balance")
rec("verify_s",verdict="OK" if abs(float(first(raw).get("balance",-1))-W0S)<0.01 else "DRIFT", detail=raw)

OUT_PATH.write_text(json.dumps({"findings":rows,"created":created},indent=2),encoding="utf-8")
print("WROTE", OUT_PATH)
