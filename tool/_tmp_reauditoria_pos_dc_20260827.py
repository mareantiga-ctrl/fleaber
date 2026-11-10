# Independent re-audit of C1 post-DC hardening. Staging only. No SQL/deploy/fix.
import json, ssl, time, uuid, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ENV_PATH = Path(r"c:\Users\Casa\Desktop\Fleaber\fleaber\tool\live_ops_staging.env")
OUT_PATH = Path(r"c:\Users\Casa\Desktop\Fleaber\fleaber\tool\reports\REAUDITORIA_POS_DC_HARDENING_2026-08-27.json")
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
TAG = f"PH-{int(time.time())}"

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
    return http(method, f"{BASE}/rest/v1/{path}" + (f"?{qs}" if qs else ""), token, body)

def fn(name, token, args):
    return rest("POST", f"rpc/{name}", token, body=args)

def edge(name, token, body):
    return http("POST", f"{BASE}/functions/v1/{name}", token, body, prefer=None)

def auth(email, password):
    last = None
    for i in range(4):
        try:
            st, raw = http(
                "POST", f"{BASE}/auth/v1/token?grant_type=password", ANON,
                {"email": email, "password": password}, prefer=None,
            )
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
    try:
        return float(first(rest("GET", "wallets", token, f"id=eq.{uid}&select=balance")[1]).get("balance"))
    except Exception:
        return None

def money(x):
    return None if x is None else round(float(x), 2)

rows = []

def rec(i, **k):
    rows.append({"id": i, **k})
    print(f"[{i}] {k.get('verdict')} {str(k.get('detail', ''))[:280]}")

BT, BID = auth(env["LIVE_OPS_TEST_BUYER_EMAIL"], env["LIVE_OPS_TEST_BUYER_PASSWORD"])
ST, SID = auth(env["LIVE_OPS_TEST_SELLER_EMAIL"], env["LIVE_OPS_TEST_SELLER_PASSWORD"])
W0B, W0S = bal(BT, BID), bal(ST, SID)
created = {"p": [], "o": [], "d": [], "r": []}

def set_bal(uid, v):
    rest("PATCH", "wallets", SVC, f"id=eq.{uid}", {"balance": round(float(v), 2)})

def ledger(oid):
    st, raw = rest("GET", "wallet_transactions", SVC,
                   f"order_id=eq.{oid}&select=type,amount,wallet_id,description&order=created_at.asc")
    return jload(raw) if isinstance(jload(raw), list) else []

def net_led(items):
    g = 0.0
    types = []
    for t in items:
        typ = (t.get("type") or "").lower()
        amt = float(t.get("amount") or 0)
        types.append(typ)
        if typ in ("venda", "reembolso"):
            g += amt
        elif typ == "estorno":
            g -= amt
    return {"gross": money(g), "types": types, "n": len(items)}

def orow(oid):
    return first(rest("GET", "orders", SVC,
        f"id=eq.{oid}&select=id,status,quantity,price_total,amount_paid_cents,wallet_release_processed_at,wallet_refund_processed_at,stripe_refund_id")[1])

def make_product(qty=30, price=3.0, title=None):
    st, raw = rest("POST", "products", ST, body={
        "seller_id": SID, "title": title or TAG, "price": price, "quantity": qty,
        "list_on_marketplace": False, "available_for_live": True, "is_sold": False,
    })
    pid = first(raw).get("id")
    if pid:
        created["p"].append(pid)
    return pid

def nord(pid=None, price=3.0, qty=1, extra=None):
    b = {
        "buyer_id": BID, "seller_id": SID, "product_id": pid or PRODUCT,
        "quantity": qty, "price_total": price, "status": "reserva_pendente",
        "payment_method": "MB WAY", "shipping_method": "mao",
    }
    if extra:
        b.update(extra)
    st, raw = rest("POST", "orders", BT, body=b)
    oid = first(raw).get("id")
    if oid:
        created["o"].append(oid)
    return oid, first(raw), st, raw

def capture(oid, cents=300):
    rest("PATCH", "orders", ST, f"id=eq.{oid}", {"status": "pago"})
    rest("PATCH", "orders", SVC, f"id=eq.{oid}", {"amount_paid_cents": cents})
    rest("PATCH", "orders", BT, f"id=eq.{oid}", {"status": "concluido"})

def review(oid, comment="ph"):
    st, raw = rest("POST", "reviews", BT, body={
        "order_id": oid, "buyer_id": BID, "stars": 5, "author_role": "comprador", "comment": comment,
    })
    rid = first(raw).get("id")
    if rid:
        created["r"].append(rid)
    return st, first(raw), raw

def dispute(oid, extra=None):
    b = {"order_id": oid, "buyer_id": BID, "reason": "outro", "description": f"{TAG}-d"}
    if extra:
        b.update(extra)
    st, raw = rest("POST", "order_disputes", BT, body=b)
    did = first(raw).get("id")
    if did:
        created["d"].append(did)
    return did, first(raw), st, raw

PRODUCT = make_product()
rec("setup", verdict="OK", detail=f"p={PRODUCT} w0b={W0B} w0s={W0S}")

# =====================================================================
# 1. SELLER → devolvida
# =====================================================================
oid1, *_ = nord()
capture(oid1)
st, raw = rest("PATCH", "orders", ST, f"id=eq.{oid1}", {"status": "devolvida"})
rec("S_dev_sem_disputa_concluido",
    verdict="OPEN" if orow(oid1).get("status") == "devolvida" else "CLOSED",
    detail=f"http={st} status={orow(oid1).get('status')} {raw[:80]}")

for src in ("pago", "enviado", "entregue", "pedido_devolucao", "em_devolucao"):
    oid, *_ = nord()
    capture(oid)
    # force old status via svc then seller patch
    rest("PATCH", "orders", SVC, f"id=eq.{oid}", {"status": src})
    st, raw = rest("PATCH", "orders", ST, f"id=eq.{oid}", {"status": "devolvida"})
    rec(f"S_dev_from_{src}",
        verdict="OPEN" if orow(oid).get("status") == "devolvida" else "CLOSED",
        detail=f"http={st} now={orow(oid).get('status')}")

# skip: concluido → devolucao_entregue → devolvida (sem disputa)
oid_skip, *_ = nord()
capture(oid_skip)
st, raw = rest("PATCH", "orders", ST, f"id=eq.{oid_skip}", {"status": "devolucao_entregue"})
rec("S_skip_to_devolucao_entregue",
    verdict="SKIP_OK" if orow(oid_skip).get("status") == "devolucao_entregue" else "BLOCKED",
    detail=f"http={st} now={orow(oid_skip).get('status')}")
st, raw = rest("PATCH", "orders", ST, f"id=eq.{oid_skip}", {"status": "devolvida"})
rec("S_dev_after_skip_no_dispute",
    verdict="OPEN" if orow(oid_skip).get("status") == "devolvida" else "CLOSED",
    detail=f"http={st} now={orow(oid_skip).get('status')}")

st, raw = rest("PATCH", "orders", ST, f"id=eq.{oid_skip}", {"status": "disputa_devolucao_vendedor"})
rec("S_skip_to_disputa_dev_vend",
    verdict="SKIP_OK" if orow(oid_skip).get("status") == "disputa_devolucao_vendedor" else "BLOCKED",
    detail=f"now={orow(oid_skip).get('status')}")
st, raw = rest("PATCH", "orders", ST, f"id=eq.{oid_skip}", {"status": "devolvida"})
rec("S_dev_from_disputa_status_no_row",
    verdict="OPEN" if orow(oid_skip).get("status") == "devolvida" else "CLOSED",
    detail=f"now={orow(oid_skip).get('status')}")

# dispute other order, then devolvida on this one
oid_a, *_ = nord()
oid_b, *_ = nord()
capture(oid_a)
capture(oid_b)
did_a, row_a, st_a, raw_a = dispute(oid_a)
rec("disp_on_A", verdict="INFO", detail=f"http={st_a} did={did_a}")
rest("PATCH", "orders", SVC, f"id=eq.{oid_b}", {"status": "devolucao_entregue"})
st, raw = rest("PATCH", "orders", ST, f"id=eq.{oid_b}", {"status": "devolvida"})
rec("S_dev_dispute_other_order",
    verdict="OPEN" if orow(oid_b).get("status") == "devolvida" else "CLOSED",
    detail=f"http={st} now={orow(oid_b).get('status')} dispA={did_a}")

# after review (released)
oid_r, *_ = nord()
capture(oid_r)
review(oid_r, "after-rel")
st, raw = rest("PATCH", "orders", ST, f"id=eq.{oid_r}", {"status": "devolvida"})
rec("S_dev_after_review",
    verdict="OPEN" if orow(oid_r).get("status") == "devolvida" else "CLOSED",
    detail=f"now={orow(oid_r).get('status')} rel={orow(oid_r).get('wallet_release_processed_at')}")

# legitimate-ish: dispute then skip to devolucao_entregue then devolvida
oid_leg, *_ = nord()
capture(oid_leg)
did, drow, st, raw = dispute(oid_leg)
rec("disp_before_review", verdict="INFO", detail=f"http={st} did={did} status_d={drow.get('status')}")
if did:
    rest("PATCH", "orders", BT, f"id=eq.{oid_leg}", {"status": "pedido_devolucao"})
    rec("B_pedido_with_dispute", verdict="INFO", detail=f"now={orow(oid_leg).get('status')}")
    rest("PATCH", "orders", ST, f"id=eq.{oid_leg}", {"status": "em_devolucao"})
    rec("S_em_devolucao", verdict="INFO", detail=f"now={orow(oid_leg).get('status')}")
    rest("PATCH", "orders", ST, f"id=eq.{oid_leg}", {"status": "devolucao_entregue"})
    rec("S_devolucao_entregue_with_disp", verdict="INFO", detail=f"now={orow(oid_leg).get('status')}")
    s0, b0 = bal(ST, SID), bal(BT, BID)
    st, raw = rest("PATCH", "orders", ST, f"id=eq.{oid_leg}", {"status": "devolvida"})
    rec("S_dev_legit_chain",
        verdict="OPEN" if orow(oid_leg).get("status") != "devolvida" and did else (
            "LEGIT_OK" if orow(oid_leg).get("status") == "devolvida" else "BLOCKED"),
        detail=f"now={orow(oid_leg).get('status')} seller {s0}->{bal(ST,SID)} buyer {b0}->{bal(BT,BID)} led={net_led(ledger(oid_leg))}")

# recusada dispute then devolvida
oid_rec, *_ = nord()
capture(oid_rec)
did, _, st, _ = dispute(oid_rec)
if did:
    rest("PATCH", "order_disputes", ST, f"id=eq.{did}", {"status": "recusada"})
    rest("PATCH", "orders", SVC, f"id=eq.{oid_rec}", {"status": "devolucao_entregue"})
    st, raw = rest("PATCH", "orders", ST, f"id=eq.{oid_rec}", {"status": "devolvida"})
    rec("S_dev_disputa_recusada",
        verdict="OPEN" if orow(oid_rec).get("status") == "devolvida" else "CLOSED",
        detail=f"now={orow(oid_rec).get('status')}")

# resolvida then jump
oid_res, *_ = nord()
capture(oid_res)
did, _, st, _ = dispute(oid_res)
if did:
    rest("PATCH", "order_disputes", ST, f"id=eq.{did}", {"status": "resolvida"})
    rest("PATCH", "orders", SVC, f"id=eq.{oid_res}", {"status": "devolucao_entregue"})
    st, raw = rest("PATCH", "orders", ST, f"id=eq.{oid_res}", {"status": "devolvida"})
    rec("S_dev_disputa_resolvida",
        verdict="OPEN" if orow(oid_res).get("status") == "devolvida" else "INFO",
        detail=f"now={orow(oid_res).get('status')} (resolvida still counts as not recusada in SQL)")

# retry PATCH devolvida
st, raw = rest("PATCH", "orders", ST, f"id=eq.{oid1}", {"status": "devolvida"})
rec("S_dev_retry", verdict="INFO", detail=f"now={orow(oid1).get('status')}")

# seller INSERT dispute
oid_si, *_ = nord()
capture(oid_si)
st, raw = rest("POST", "order_disputes", ST, body={
    "order_id": oid_si, "buyer_id": BID, "reason": "outro", "description": "seller-insert",
})
rec("S_insert_dispute", verdict="OPEN" if st in (200, 201) else "CLOSED", detail=f"http={st} {raw[:100]}")

# =====================================================================
# 2. BUYER pedido_devolucao
# =====================================================================
oid_br, *_ = nord()
capture(oid_br)
review(oid_br, "b-rel")
st, raw = rest("PATCH", "orders", BT, f"id=eq.{oid_br}", {"status": "pedido_devolucao"})
rec("B_pedido_after_review",
    verdict="OPEN" if orow(oid_br).get("status") == "pedido_devolucao" else "CLOSED",
    detail=f"now={orow(oid_br).get('status')}")
for nxt in ("em_devolucao", "devolucao_entregue", "disputa_devolucao_vendedor", "devolvida"):
    st, raw = rest("PATCH", "orders", BT, f"id=eq.{oid_br}", {"status": nxt})
    rec(f"B_jump_{nxt}_after_release",
        verdict="OPEN" if orow(oid_br).get("status") == nxt else "CLOSED",
        detail=f"now={orow(oid_br).get('status')}")

# without dispute, before review
oid_nd, *_ = nord()
capture(oid_nd)
st, raw = rest("PATCH", "orders", BT, f"id=eq.{oid_nd}", {"status": "pedido_devolucao"})
rec("B_pedido_sem_disputa",
    verdict="OPEN" if orow(oid_nd).get("status") == "pedido_devolucao" else "CLOSED",
    detail=f"now={orow(oid_nd).get('status')}")

# other buyer's order: get some order not ours via svc then patch as buyer
st, raw = rest("GET", "orders", SVC, f"buyer_id=neq.{BID}&select=id,status,buyer_id&limit=1")
foreign = first(raw).get("id")
if foreign:
    st, raw = rest("PATCH", "orders", BT, f"id=eq.{foreign}", {"status": "pedido_devolucao"})
    rec("B_pedido_foreign_order", verdict="INFO",
        detail=f"http={st} body={raw[:80]} now_via_svc={first(rest('GET','orders',SVC,f'id=eq.{foreign}&select=status')[1]).get('status')}")

did, _, st, raw = dispute(oid_nd)
rec("B_dispute_unreleased", verdict="INFO", detail=f"http={st} did={did}")
if did:
    st, raw = rest("PATCH", "orders", BT, f"id=eq.{oid_nd}", {"status": "pedido_devolucao"})
    rec("B_pedido_with_own_dispute",
        verdict="OK" if orow(oid_nd).get("status") == "pedido_devolucao" else "FAIL",
        detail=f"now={orow(oid_nd).get('status')}")

# RPC refund without devolvida
st, raw = fn("batata_refund_buyer_wallet_for_order", BT, {"p_order_id": oid_br})
rec("B_rpc_refund_not_devolvida", verdict="INFO", detail=f"http={st} {raw[:80]} b={bal(BT,BID)}")

# =====================================================================
# 3. Double-credit invariant + concurrency
# =====================================================================
oid_dc, *_ = nord()
capture(oid_dc)
s0, b0 = bal(ST, SID), bal(BT, BID)
# race: two reviews? second duplicate. race release rpc || seller skip devolvida
def t_rev():
    return rest("POST", "reviews", BT, body={"order_id": oid_dc, "buyer_id": BID, "stars": 5, "comment": "race"})
def t_rel():
    return fn("batata_release_seller_wallet_for_order", BT, {"p_order_id": oid_dc})
def t_dev():
    return rest("PATCH", "orders", ST, f"id=eq.{oid_dc}", {"status": "devolvida"})
with ThreadPoolExecutor(max_workers=3) as ex:
    outs = [f.result() for f in [ex.submit(t_rev), ex.submit(t_rel), ex.submit(t_dev)]]
s1, b1 = bal(ST, SID), bal(BT, BID)
ns = net_led(ledger(oid_dc))
liq = money((s1 or 0) - (s0 or 0) + (b1 or 0) - (b0 or 0))
rec("DC_race_review_release_devolvida",
    verdict="OVER" if (ns.get("gross") or 0) > 3.01 or (liq or 0) > 3.01 else "CLOSED",
    detail=f"liq={liq} led={ns} http={[o[0] for o in outs]} now={orow(oid_dc)}")

# two releases
st1, raw1 = fn("batata_release_seller_wallet_for_order", BT, {"p_order_id": oid_dc})
st2, raw2 = fn("batata_release_seller_wallet_for_order", BT, {"p_order_id": oid_dc})
rec("DC_double_release_rpc", verdict="INFO",
    detail=f"{st1}/{raw1[:40]} {st2}/{raw2[:40]} led={net_led(ledger(oid_dc))}")

# captured + legit chain refund vs capture
# use oid_leg if devolvida
if orow(oid_leg).get("status") == "devolvida":
    ns = net_led(ledger(oid_leg))
    rec("DC_legit_full_refund_cap",
        verdict="OVER" if (ns.get("gross") or 0) > 3.01 else "CLOSED",
        detail=f"led={ns}")

# partial after dispute+offer, then retry
oid_p, *_ = nord()
capture(oid_p)
did, _, st, _ = dispute(oid_p)
if did:
    rest("PATCH", "order_disputes", ST, f"id=eq.{did}", {
        "seller_refund_percent": 40, "seller_offer_type": "partial_refund",
    })
    s0, b0 = bal(ST, SID), bal(BT, BID)
    with ThreadPoolExecutor(max_workers=2) as ex:
        futs = [ex.submit(fn, "batata_process_partial_refund_dispute", BT, {"p_order_id": oid_p}) for _ in range(2)]
        pouts = [f.result() for f in futs]
    ns = net_led(ledger(oid_p))
    rec("DC_double_partial_rpc",
        verdict="OVER" if (ns.get("gross") or 0) > 3.01 else "CLOSED",
        detail=f"led={ns} http={[p[0] for p in pouts]} bodies={[p[1][:60] for p in pouts]} seller {s0}->{bal(ST,SID)} buyer {b0}->{bal(BT,BID)}")

# mint no capture
oid_m, *_ = nord(price=50)
rest("PATCH", "orders", ST, f"id=eq.{oid_m}", {"status": "pago"})
s0, b0 = bal(ST, SID), bal(BT, BID)
# try force devolvida via svc (ops) — that's not JWT. JWT:
rest("PATCH", "orders", ST, f"id=eq.{oid_m}", {"status": "devolvida"})
rec("REG_mint_no_capture_jwt_dev",
    verdict="OPEN" if abs((bal(BT,BID) or 0)-(b0 or 0))>0.01 else "CLOSED",
    detail=f"now={orow(oid_m).get('status')} paid={orow(oid_m).get('amount_paid_cents')} b {b0}->{bal(BT,BID)}")

# JWT write cents
oid_c, *_ = nord()
st, raw = rest("PATCH", "orders", BT, f"id=eq.{oid_c}", {"amount_paid_cents": 99999})
st2, raw2 = rest("PATCH", "orders", ST, f"id=eq.{oid_c}", {"amount_paid_cents": 99999})
rec("cents_jwt",
    verdict="OPEN" if orow(oid_c).get("amount_paid_cents") not in (None, 0) else "CLOSED",
    detail=f"paid={orow(oid_c).get('amount_paid_cents')}")

# credit_wallet JWT
st, raw = fn("batata_credit_wallet_once", BT, {
    "p_wallet_id": BID, "p_order_id": oid_dc, "p_amount": 10, "p_type": "reembolso", "p_description": "x",
})
rec("credit_once_jwt", verdict="INFO", detail=f"http={st} {raw[:80]}")

# different description duplicate venda via JWT insert txs
st, raw = rest("POST", "wallet_transactions", BT, body={
    "wallet_id": BID, "order_id": oid_dc, "amount": 50, "type": "reembolso", "description": "hostile-alt",
})
rec("insert_tx_jwt", verdict="OPEN" if st in (200, 201) else "CLOSED", detail=f"http={st} {raw[:80]}")

# =====================================================================
# 4. Ledger after clawback (need a devolvida that actually refunds)
# Use SVC to set devolvida on captured+released order to inspect ledger shape
# (JWT seller blocked — that's the point; ops path still clawbacks)
# =====================================================================
oid_led, *_ = nord()
capture(oid_led)
review(oid_led, "ledger")
# try JWT first
rest("PATCH", "orders", ST, f"id=eq.{oid_led}", {"status": "devolvida"})
jwt_blocked = orow(oid_led).get("status") != "devolvida"
rec("ledger_jwt_blocked_before_svc", verdict="INFO", detail=f"jwt_blocked={jwt_blocked} status={orow(oid_led).get('status')}")
# svc force devolvida to see append-only trail (simulates successful legit chain)
rest("PATCH", "orders", SVC, f"id=eq.{oid_led}", {"status": "devolvida"})
lg = ledger(oid_led)
ns = net_led(lg)
has_venda = "venda" in ns["types"]
has_est = "estorno" in ns["types"]
has_reb = "reembolso" in ns["types"]
rec("ledger_after_svc_devolvida",
    verdict="APPEND" if has_venda and has_est and has_reb else ("DELETED" if has_reb and not has_venda else "INFO"),
    detail=f"led={ns} rows={lg} gross={ns.get('gross')}")
# retry clawback
st, raw = fn("batata_clawback_seller_wallet_for_order", SVC, {"p_order_id": oid_led})
rec("ledger_clawback_retry", verdict="INFO",
    detail=f"http={st} {raw[:40]} led={net_led(ledger(oid_led))}")
# alt description debit
st, raw = fn("batata_debit_wallet_once", SVC, {
    "p_wallet_id": SID, "p_order_id": oid_led, "p_amount": 0.50,
    "p_description": f"alt-{TAG}",
})
rec("ledger_debit_alt_desc", verdict="INFO",
    detail=f"http={st} {raw[:40]} led={net_led(ledger(oid_led))}")
# restore extra 0.50 if applied
set_bal(SID, bal(ST, SID) if False else W0S)  # will global-restore at end

# =====================================================================
# 5. Stripe × wallet
# =====================================================================
oid_st, *_ = nord()
capture(oid_st)
review(oid_st, "stripe")
rest("PATCH", "orders", SVC, f"id=eq.{oid_st}", {
    "stripe_refund_id": f"re_orphan_{TAG}",
    "stripe_refunded_at": "2026-08-27T00:00:00Z",
})
b0 = bal(BT, BID)
s0 = bal(ST, SID)
rest("PATCH", "orders", SVC, f"id=eq.{oid_st}", {"status": "devolvida"})
b1, s1 = bal(BT, BID), bal(ST, SID)
rec("STRIPE_orphan_then_devolvida",
    verdict="DOUBLE" if (b1 or 0) - (b0 or 0) > 0.01 else "NO_WALLET",
    detail=f"buyer {b0}->{b1} seller {s0}->{s1} led={net_led(ledger(oid_st))} now={orow(oid_st)}")

oid_fin, *_ = nord()
capture(oid_fin)
review(oid_fin, "fin")
s0, b0 = bal(ST, SID), bal(BT, BID)
st, raw = fn("batata_finalize_stripe_order_refund", SVC, {
    "p_order_id": oid_fin, "p_refund_id": f"re_fin_{TAG}",
    "p_payment_intent_id": "pi_fake", "p_amount_cents": 300,
})
s1, b1 = bal(ST, SID), bal(BT, BID)
rec("STRIPE_finalize_after_release",
    verdict="INFO",
    detail=f"rpc={st} {str(raw)[:120]} seller {s0}->{s1} buyer {b0}->{b1} status={orow(oid_fin).get('status')}")
rest("PATCH", "orders", ST, f"id=eq.{oid_fin}", {"status": "devolvida"})
rec("STRIPE_jwt_dev_after_finalize",
    verdict="INFO",
    detail=f"now={orow(oid_fin).get('status')} b {b1}->{bal(BT,BID)}")
st, raw = fn("batata_finalize_stripe_order_refund", BT, {
    "p_order_id": oid_fin, "p_refund_id": "re_jwt",
})
rec("STRIPE_finalize_jwt", verdict="INFO", detail=f"http={st} {raw[:80]}")

# JWT write stripe_refund_id
oid_wr, *_ = nord()
st, raw = rest("PATCH", "orders", ST, f"id=eq.{oid_wr}", {"stripe_refund_id": "re_jwt"})
rec("STRIPE_id_jwt_write",
    verdict="OPEN" if orow(oid_wr).get("stripe_refund_id") else "CLOSED",
    detail=f"id={orow(oid_wr).get('stripe_refund_id')}")

# =====================================================================
# 6. Payout × clawback
# =====================================================================
st, raw = fn("batata_wallet_payout_debit", BT, {
    "p_user_id": SID, "p_amount_cents": 100, "p_idempotency_key": f"{TAG}-pb",
})
rec("PAY_debit_buyer_jwt", verdict="INFO", detail=f"http={st} {raw[:100]}")
st, raw = fn("batata_wallet_payout_debit", ST, {
    "p_user_id": SID, "p_amount_cents": 100, "p_idempotency_key": f"{TAG}-ps",
})
rec("PAY_debit_seller_jwt", verdict="INFO", detail=f"http={st} {raw[:100]}")

# release blocked when dispute open?
oid_pd, *_ = nord()
capture(oid_pd)
did, _, st, _ = dispute(oid_pd)
s0 = bal(ST, SID)
st, raw = fn("batata_release_seller_wallet_for_order", BT, {"p_order_id": oid_pd})
s1 = bal(ST, SID)
rec("PAY_release_while_dispute_open",
    verdict="RELEASED" if (s1 or 0) - (s0 or 0) > 0.01 else "HELD",
    detail=f"rpc={st} {raw[:40]} seller {s0}->{s1} rel={orow(oid_pd).get('wallet_release_processed_at')}")

# seller edge payout (wrong/right body)
st, raw = edge("create-connect-account", ST, {"amount": 100, "idempotency_key": f"{TAG}-edge1"})
rec("PAY_edge_seller", verdict="INFO", detail=f"http={st} {raw[:180]}")

# =====================================================================
# 7. Quantity
# =====================================================================
P2 = make_product(qty=3, title=f"{TAG}-q")
for q, name in [(0, "zero"), (-1, "neg"), (None, "null")]:
    body = {"buyer_id": BID, "seller_id": SID, "product_id": P2, "price_total": 3,
            "status": "reserva_pendente", "payment_method": "MB WAY", "shipping_method": "mao"}
    if q is not None:
        body["quantity"] = q
    st, raw = rest("POST", "orders", BT, body=body)
    rec(f"QTY_{name}",
        verdict="OPEN" if st in (200, 201) else "FAIL_CLOSED",
        detail=f"http={st} qty={first(raw).get('quantity')} {raw[:80]}")
st, raw = rest("POST", "orders", BT, body={
    "buyer_id": BID, "seller_id": SID, "product_id": P2, "quantity": 50,
    "price_total": 150, "status": "reserva_pendente", "payment_method": "MB WAY", "shipping_method": "mao",
})
oidq = first(raw).get("id")
if oidq:
    created["o"].append(oidq)
rec("QTY_gt_stock", verdict="INFO", detail=f"http={st} stored={first(raw).get('quantity')} stock=3")
st, raw = rest("POST", "orders", BT, body={
    "buyer_id": BID, "seller_id": SID, "product_id": P2, "quantity": "2",
    "price_total": 6, "status": "reserva_pendente", "payment_method": "MB WAY", "shipping_method": "mao",
})
if first(raw).get("id"):
    created["o"].append(first(raw).get("id"))
rec("QTY_string", verdict="INFO", detail=f"http={st} qty={first(raw).get('quantity')}")

P0 = make_product(qty=0, title=f"{TAG}-z")
st, raw = rest("POST", "orders", BT, body={
    "buyer_id": BID, "seller_id": SID, "product_id": P0, "quantity": 1,
    "price_total": 3, "status": "reserva_pendente", "payment_method": "MB WAY", "shipping_method": "mao",
})
if first(raw).get("id"):
    created["o"].append(first(raw).get("id"))
rec("QTY_order_on_stock0",
    verdict="OPEN" if st in (200, 201) else "FAIL_CLOSED",
    detail=f"http={st} {raw[:100]}")

# =====================================================================
# 8. Reviews privacy
# =====================================================================
st, raw = http("GET", f"{BASE}/rest/v1/reviews?select=*&limit=5", ANON, prefer=None)
anon_tab = jload(raw)
rec("REV_anon_table",
    verdict="OPEN" if isinstance(anon_tab, list) and anon_tab else "CLOSED",
    detail=f"http={st} n={len(anon_tab) if isinstance(anon_tab,list) else raw[:80]}")
st, raw = http("GET", f"{BASE}/rest/v1/reviews_public_ratings?select=*&limit=5", ANON, prefer=None)
anon_view = jload(raw)
keys = sorted({k for r in anon_view for k in r}) if isinstance(anon_view, list) and anon_view else []
pii = [k for k in keys if k in ("buyer_id", "order_id", "buyerId")]
rec("REV_anon_view",
    verdict="PII" if pii else "OK",
    detail=f"http={st} n={len(anon_view) if isinstance(anon_view,list) else 0} keys={keys} pii={pii}")
st, raw = rest("GET", "reviews", BT, "select=*&limit=8")
btab = jload(raw) if isinstance(jload(raw), list) else []
others = [r for r in btab if r.get("buyer_id") not in (BID, None) and r.get("target_id") != BID]
rec("REV_buyer_table",
    verdict="LEAK" if others else "PARTIES",
    detail=f"n={len(btab)} foreign={len(others)} sample_keys={sorted(btab[0].keys()) if btab else []}")
st, raw = rest("GET", "reviews_public_ratings", BT, "select=*&limit=5")
rec("REV_buyer_view", verdict="INFO", detail=f"http={st} n={len(jload(raw)) if isinstance(jload(raw),list) else raw[:60]}")
st, raw = rest("GET", "reviews", ST, "select=id,buyer_id,order_id,stars&limit=8")
stab = jload(raw) if isinstance(jload(raw), list) else []
rec("REV_seller_table", verdict="INFO",
    detail=f"n={len(stab)} has_order={[bool(r.get('order_id')) for r in stab[:3]]}")

# insert still works
oid_rv, *_ = nord()
capture(oid_rv)
st, raw = review(oid_rv, "legit-rev")
rec("REV_insert_own", verdict="OK" if st in (200, 201) else "REGRESSION", detail=f"http={st}")

# =====================================================================
# 9. Extra attacker: RPC refund as seller on concluido; admin; tip
# =====================================================================
st, raw = fn("batata_refund_buyer_wallet_for_order", ST, {"p_order_id": oid_dc})
rec("S_rpc_refund", verdict="INFO", detail=f"http={st} {raw[:80]}")
st, raw = fn("batata_release_seller_wallet_for_order", ST, {"p_order_id": oid_dc})
rec("S_rpc_release", verdict="INFO", detail=f"http={st} {raw[:80]}")
st, raw = rest("PATCH", "orders", BT, f"id=eq.{oid_dc}", {"wallet_release_processed_at": None, "wallet_refund_processed_at": None})
rec("B_clear_wallet_flags", verdict="INFO",
    detail=f"rel={orow(oid_dc).get('wallet_release_processed_at')} ref={orow(oid_dc).get('wallet_refund_processed_at')}")

# buyer PATCH stripe_refund_id then get refund somehow
# already tested write

# =====================================================================
# Cleanup
# =====================================================================
set_bal(BID, W0B)
set_bal(SID, W0S)
for rid in created["r"]:
    rest("DELETE", "reviews", SVC, f"id=eq.{rid}")
rest("DELETE", "reviews", SVC, f"comment=like.{TAG}*")
rest("DELETE", "reviews", SVC, f"comment=eq.race")
rest("DELETE", "reviews", SVC, f"comment=eq.legit-rev")
rest("DELETE", "reviews", SVC, f"comment=eq.after-rel")
for did in created["d"]:
    rest("DELETE", "order_disputes", SVC, f"id=eq.{did}")
for oid in created["o"]:
    rest("DELETE", "wallet_transactions", SVC, f"order_id=eq.{oid}")
    rest("DELETE", "fleaber_commissions", SVC, f"order_id=eq.{oid}")
    rest("DELETE", "orders", SVC, f"id=eq.{oid}")
for pid in created["p"]:
    rest("DELETE", "products", SVC, f"id=eq.{pid}")
rest("DELETE", "wallet_payout_ledger", SVC, f"idempotency_key=like.{TAG}*")

rec("cleanup",
    verdict="RESTORED" if bal(BT, BID) == W0B and bal(ST, SID) == W0S else "DRIFT",
    detail=f"b {W0B}->{bal(BT,BID)} s {W0S}->{bal(ST,SID)}")

OUT_PATH.write_text(json.dumps({"tag": TAG, "w0": {"b": W0B, "s": W0S}, "rows": rows}, indent=2, default=str), encoding="utf-8")
print("WROTE", OUT_PATH, "N", len(rows))
