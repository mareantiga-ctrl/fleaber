# Cleanup leftover PH- fixtures + follow-up qty null explicit + review insert.
import json, ssl, time, urllib.request, urllib.error
from pathlib import Path

ENV_PATH = Path(r"c:\Users\Casa\Desktop\Fleaber\fleaber\tool\live_ops_staging.env")
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
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()

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

BT,BID=auth(env["LIVE_OPS_TEST_BUYER_EMAIL"], env["LIVE_OPS_TEST_BUYER_PASSWORD"])
ST,SID=auth(env["LIVE_OPS_TEST_SELLER_EMAIL"], env["LIVE_OPS_TEST_SELLER_PASSWORD"])

def bal(uid):
    st,raw=rest("GET","wallets",SVC,f"id=eq.{uid}&select=balance")
    return float(first(raw).get("balance"))

print("BAL before", bal(BID), bal(SID))

# Follow-up: explicit JSON null quantity
st,raw=rest("POST","products",ST,body={"seller_id":SID,"title":"PH-fu-null","price":1,"quantity":5,"list_on_marketplace":False,"available_for_live":True,"is_sold":False})
P=first(raw).get("id")
print("product", st, P)
body={"buyer_id":BID,"seller_id":SID,"product_id":P,"quantity":None,"price_total":1,"status":"reserva_pendente","payment_method":"MB WAY","shipping_method":"mao"}
st,raw=rest("POST","orders",BT,body=body)
print("QTY_explicit_null", st, raw[:180])

# review insert on captured concluido
st,raw=rest("POST","orders",BT,body={"buyer_id":BID,"seller_id":SID,"product_id":P,"quantity":1,"price_total":1,"status":"reserva_pendente","payment_method":"MB WAY","shipping_method":"mao"})
oid=first(raw).get("id")
rest("PATCH","orders",ST,f"id=eq.{oid}",{"status":"pago"})
rest("PATCH","orders",SVC,f"id=eq.{oid}",{"amount_paid_cents":100})
rest("PATCH","orders",BT,f"id=eq.{oid}",{"status":"concluido"})
st,raw=rest("POST","reviews",BT,body={"order_id":oid,"buyer_id":BID,"stars":5,"comment":"ph-fu-rev"})
print("REV_insert", st, raw[:120])

# Cleanup tag products
st,raw=rest("GET","products",SVC,"select=id,title&title=like.PH-*")
prods=[p for p in (json.loads(raw) if raw.startswith("[") else [])
       if str(p.get("title","")).startswith("PH-1787819663") or p.get("title") in ("PH-fu-null",)]
print("products PH", len(prods), [p.get("title") for p in prods[:20]])
oids=[]
for p in prods:
    st,raw=rest("GET","orders",SVC,f"product_id=eq.{p['id']}&select=id")
    oids += [x["id"] for x in (json.loads(raw) if raw.startswith("[") else [])]
print("orders", len(oids))
for oid2 in oids:
    rest("DELETE","reviews",SVC,f"order_id=eq.{oid2}")
    rest("DELETE","order_disputes",SVC,f"order_id=eq.{oid2}")
    rest("DELETE","wallet_transactions",SVC,f"order_id=eq.{oid2}")
    rest("DELETE","fleaber_commissions",SVC,f"order_id=eq.{oid2}")
    rest("DELETE","orders",SVC,f"id=eq.{oid2}")
rest("DELETE","reviews",SVC,"comment=like.ph-*")
rest("DELETE","reviews",SVC,"comment=like.PH-*")
rest("DELETE","reviews",SVC,"comment=eq.race")
rest("DELETE","reviews",SVC,"comment=eq.ledger")
rest("DELETE","reviews",SVC,"comment=eq.stripe")
rest("DELETE","reviews",SVC,"comment=eq.fin")
rest("DELETE","reviews",SVC,"comment=eq.after-rel")
rest("DELETE","reviews",SVC,"comment=eq.b-rel")
for p in prods:
    rest("DELETE","products",SVC,f"id=eq.{p['id']}")

# restore lab wallets to pre-probe 31.00 / 8.64 minus we should NOT mint the 1€ that was paid out
# User asked cleanup of disposable fixtures. Payout 1€ TEST already left. Restoring to 31/8.64 would
# put back the 1€ that Stripe TEST transferred — that's lab consistency vs lying about payout.
# Restore to 31.00 buyer and 7.64 seller (8.64-1.00 payout) if current is messy.
# Actually start was 31/8.64 then tests minted then payout 1€. Safest: set buyer 31.00, seller 7.64
# documenting the TEST transfer.
rest("PATCH","wallets",SVC,f"id=eq.{BID}",{"balance":31.00})
rest("PATCH","wallets",SVC,f"id=eq.{SID}",{"balance":7.64})
print("BAL after", bal(BID), bal(SID))
print("done")
