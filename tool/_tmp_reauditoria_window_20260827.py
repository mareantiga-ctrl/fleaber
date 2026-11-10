# Confirm product window: after review/release, buyer cannot open return; seller still can PATCH devolvida.
import json, ssl, time, urllib.request, urllib.error
from pathlib import Path

ENV_PATH = Path(r"c:\Users\Casa\Desktop\Fleaber\fleaber\tool\live_ops_staging.env")
OUT = Path(r"c:\Users\Casa\Desktop\Fleaber\fleaber\tool\reports\REAUDITORIA_DC_WINDOW_2026-08-27.json")
BASE = "https://fxdknzrqjenzqcvnwqqq.supabase.co"
ctx = ssl.create_default_context()
env = {}
for line in ENV_PATH.read_text(encoding="utf-8").splitlines():
    line=line.strip()
    if not line or line.startswith("#") or "=" not in line: continue
    k,v=line.split("=",1); env[k.strip()]=v.strip()
ANON=env["SUPABASE_ANON_KEY"]; SVC=env["SUPABASE_SERVICE_ROLE_KEY"]

def http(method, url, token, body=None, prefer="return=representation"):
    data=None if body is None else json.dumps(body).encode()
    h={"apikey":ANON,"Authorization":f"Bearer {token}"}
    if prefer: h["Prefer"]=prefer
    if data is not None: h["Content-Type"]="application/json"
    req=urllib.request.Request(url,data=data,headers=h,method=method)
    try:
        with urllib.request.urlopen(req,context=ctx,timeout=60) as resp:
            return resp.status, resp.read().decode("utf-8","replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8","replace")

def rest(method, path, token, qs="", body=None):
    return http(method, f"{BASE}/rest/v1/{path}"+(f"?{qs}" if qs else ""), token, body)

def first(raw):
    try:
        o=json.loads(raw)
        return o[0] if isinstance(o,list) and o else (o if isinstance(o,dict) else {})
    except Exception:
        return {}

def auth(email, password):
    st,raw=http("POST", f"{BASE}/auth/v1/token?grant_type=password", ANON, {"email":email,"password":password}, prefer=None)
    j=json.loads(raw); return j["access_token"], j["user"]["id"]

rows=[]
def rec(i,**k):
    rows.append({"id":i,**k}); print(f"[{i}] {k.get('verdict')} {str(k.get('detail',''))[:240]}")

def bal(token, uid):
    st,raw=rest("GET","wallets",token,f"id=eq.{uid}&select=balance")
    try: return float(first(raw).get("balance"))
    except Exception: return None

BT,BID=auth(env["LIVE_OPS_TEST_BUYER_EMAIL"], env["LIVE_OPS_TEST_BUYER_PASSWORD"])
ST,SID=auth(env["LIVE_OPS_TEST_SELLER_EMAIL"], env["LIVE_OPS_TEST_SELLER_PASSWORD"])
W0B,W0S=bal(BT,BID),bal(ST,SID)
TAG=f"WIN-{int(time.time())}"

st,raw=rest("POST","products",ST,body={"seller_id":SID,"title":TAG,"price":3,"quantity":5,"list_on_marketplace":False,"available_for_live":True,"is_sold":False})
P=first(raw).get("id")
st,raw=rest("POST","orders",BT,body={"buyer_id":BID,"seller_id":SID,"product_id":P,"quantity":1,"price_total":3,"status":"reserva_pendente","payment_method":"MB WAY","shipping_method":"mao"})
oid=first(raw).get("id")
rest("PATCH","orders",ST,f"id=eq.{oid}",{"status":"pago"})
rest("PATCH","orders",SVC,f"id=eq.{oid}",{"amount_paid_cents":300})
rest("PATCH","orders",BT,f"id=eq.{oid}",{"status":"concluido"})
st,raw=rest("POST","reviews",BT,body={"order_id":oid,"buyer_id":BID,"stars":5,"comment":TAG})
rec("review",verdict="OK",detail=f"http={st} rel={first(rest('GET','orders',SVC,f'id=eq.{oid}&select=wallet_release_processed_at,status')[1]).get('wallet_release_processed_at')}")

st,raw=rest("POST","order_disputes",BT,body={"order_id":oid,"buyer_id":BID,"reason":"outro","description":"window-test"})
rec("buyer_dispute_after_review",verdict="BLOCKED" if st>=400 else "OPEN",detail=f"http={st} {raw[:180]}")

st,raw=rest("PATCH","orders",BT,f"id=eq.{oid}",{"status":"pedido_devolucao"})
rec("buyer_pedido_devolucao_after_review",verdict="INFO",detail=f"http={st} status={first(raw).get('status')} {raw[:120]}")

st,raw=rest("PATCH","orders",ST,f"id=eq.{oid}",{"status":"pedido_devolucao"})
rec("seller_pedido_devolucao_after_review",verdict="INFO",detail=f"http={st} status={first(raw).get('status')}")

# restore concluido then seller jump devolvida (already known); skip extra mint: use cancelado? we'll devolvida then cleanup wallets
st,raw=rest("GET","orders",SVC,f"id=eq.{oid}&select=status,wallet_release_processed_at")
rec("status_now",verdict="INFO",detail=raw[:200])

# cleanup
rest("DELETE","reviews",SVC,f"comment=eq.{TAG}")
rest("DELETE","order_disputes",SVC,f"order_id=eq.{oid}")
rest("DELETE","wallet_transactions",SVC,f"order_id=eq.{oid}")
rest("DELETE","fleaber_commissions",SVC,f"order_id=eq.{oid}")
rest("DELETE","orders",SVC,f"id=eq.{oid}")
rest("DELETE","products",SVC,f"id=eq.{P}")
rest("PATCH","wallets",SVC,f"id=eq.{SID}",{"balance":W0S})
rest("PATCH","wallets",SVC,f"id=eq.{BID}",{"balance":W0B})
OUT.write_text(json.dumps(rows,indent=2),encoding="utf-8")
print("WROTE", OUT)
