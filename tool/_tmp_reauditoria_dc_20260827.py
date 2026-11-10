# Independent re-audit of double-credit class + claimed C1 fixes.
# Staging only. Does not deploy or patch SQL. Cleans lab fixtures.
import json, ssl, time, uuid, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

ENV_PATH = Path(r"c:\Users\Casa\Desktop\Fleaber\fleaber\tool\live_ops_staging.env")
OUT_PATH = Path(r"c:\Users\Casa\Desktop\Fleaber\fleaber\tool\reports\REAUDITORIA_DC_2026-08-27.json")
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
TAG = f"RA-{int(time.time())}"

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

def rest(method, path, token, qs="", body=None, prefer="return=representation"):
    url = f"{BASE}/rest/v1/{path}" + (f"?{qs}" if qs else "")
    return http(method, url, token, body, prefer=prefer)

def fn(name, token, args):
    return rest("POST", f"rpc/{name}", token, body=args)

def edge(name, token, body):
    return http("POST", f"{BASE}/functions/v1/{name}", token, body, prefer=None)

def auth(email, password):
    last = None
    for i in range(4):
        try:
            st, raw = http(
                "POST",
                f"{BASE}/auth/v1/token?grant_type=password",
                ANON,
                {"email": email, "password": password},
                prefer=None,
            )
            j = json.loads(raw)
            return j["access_token"], j["user"]["id"]
        except Exception as e:
            last = e
            time.sleep(2 * (i + 1))
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

def money(x):
    if x is None:
        return None
    return round(float(x), 2)

rows = []

def rec(i, **k):
    rows.append({"id": i, **k})
    print(f"[{i}] {k.get('verdict')} {str(k.get('detail', ''))[:280]}")

BT, BID = auth(env["LIVE_OPS_TEST_BUYER_EMAIL"], env["LIVE_OPS_TEST_BUYER_PASSWORD"])
ST, SID = auth(env["LIVE_OPS_TEST_SELLER_EMAIL"], env["LIVE_OPS_TEST_SELLER_PASSWORD"])
W0B, W0S = bal(BT, BID), bal(ST, SID)
created = {"p": [], "o": [], "d": [], "r": [], "c": [], "m": [], "li": [], "rr": [], "po": []}

def set_bal(uid, value):
    rest("PATCH", "wallets", SVC, f"id=eq.{uid}", {"balance": round(float(value), 2)})

def ledger(oid):
    st, raw = rest(
        "GET",
        "wallet_transactions",
        SVC,
        f"order_id=eq.{oid}&select=id,wallet_id,amount,type,description,created_at&order=created_at.asc",
    )
    items = jload(raw) if isinstance(jload(raw), list) else []
    return items

def order_row(oid, token=SVC):
    st, raw = rest(
        "GET",
        "orders",
        token,
        f"id=eq.{oid}&select=id,status,price_total,quantity,amount_paid_cents,wallet_release_processed_at,wallet_refund_processed_at,stripe_refund_id,stripe_refunded_at,stock_units_applied,payment_method",
    )
    return first(raw)

def net_from_ledger(items, seller_id, buyer_id):
    s_credit = 0.0
    b_credit = 0.0
    s_claw = 0.0
    types = {}
    for t in items:
        typ = (t.get("type") or "").lower()
        amt = float(t.get("amount") or 0)
        types[typ] = types.get(typ, 0) + 1
        wid = t.get("wallet_id")
        if typ in ("venda",) and wid == seller_id:
            s_credit += amt
        elif typ in ("reembolso",) and wid == buyer_id:
            b_credit += amt
        elif typ in ("estorno",) and wid == seller_id:
            s_claw += amt
    return {
        "seller_venda": money(s_credit),
        "buyer_reembolso": money(b_credit),
        "seller_estorno_rows": money(s_claw),
        "gross_credits": money(s_credit + b_credit),
        "types": types,
        "n": len(items),
    }

def make_product(qty=20, price=3.00, title=None):
    st, raw = rest(
        "POST",
        "products",
        ST,
        body={
            "seller_id": SID,
            "title": title or f"RA-{TAG}",
            "price": price,
            "quantity": qty,
            "list_on_marketplace": False,
            "available_for_live": True,
            "is_sold": False,
        },
    )
    pid = first(raw).get("id")
    if pid:
        created["p"].append(pid)
    return pid, first(raw), st, raw

def make_order(extra=None, qty=1, price=3.00, method="MB WAY"):
    b = {
        "buyer_id": BID,
        "seller_id": SID,
        "product_id": PRODUCT,
        "quantity": qty,
        "price_total": price,
        "status": "reserva_pendente",
        "payment_method": method,
        "shipping_method": "mao",
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
    st, raw = rest("PATCH", "orders", SVC, f"id=eq.{oid}", {"amount_paid_cents": cents})
    return first(raw)

def review_release(oid, comment="ra"):
    rest("PATCH", "orders", BT, f"id=eq.{oid}", {"status": "concluido"})
    st, raw = rest(
        "POST",
        "reviews",
        BT,
        body={
            "order_id": oid,
            "buyer_id": BID,
            "target_id": SID,
            "stars": 5,
            "author_role": "comprador",
            "comment": comment,
        },
    )
    rid = first(raw).get("id")
    if rid:
        created["r"].append(rid)
    return st, first(raw), raw

def seller_devolvida(oid):
    st, raw = rest("PATCH", "orders", ST, f"id=eq.{oid}", {"status": "devolvida"})
    return st, first(raw), raw

PRODUCT, prow, *_ = make_product(qty=50, price=3.00)
rec("setup", verdict="OK", detail=f"product={PRODUCT} w0b={W0B} w0s={W0S}")

# ---------------------------------------------------------------------------
# Live fingerprint: is C1 SQL actually deployed?
# ---------------------------------------------------------------------------
st, raw = fn("batata_order_wallet_net_disbursed_eur", BT, {"p_order_id": str(uuid.uuid4())})
rec("live_fn_net_disbursed", verdict="DEPLOYED" if st in (200, 201) else "MISSING",
    detail=f"http={st} body={raw[:160]}")
st, raw = fn("batata_clawback_seller_wallet_for_order", BT, {"p_order_id": str(uuid.uuid4())})
rec("live_fn_clawback_jwt", verdict="INFO", detail=f"http={st} body={raw[:160]}")
st, raw = fn("batata_debit_wallet_once", BT, {
    "p_wallet_id": BID, "p_order_id": str(uuid.uuid4()), "p_amount": 1, "p_description": "x"
})
rec("live_fn_debit_jwt", verdict="INFO", detail=f"http={st} body={raw[:120]}")

# ===========================================================================
# 1. EXACT original attack: capture 3€ → concluido → review → devolvida
# ===========================================================================
oid_a, *_ = make_order(price=3.00, qty=1)
capture(oid_a, 300)
wb_s, wb_b = bal(ST, SID), bal(BT, BID)
st_r, rev, raw_r = review_release(oid_a, "exact-dc")
ws_mid, bb_mid = bal(ST, SID), bal(BT, BID)
st_d, od, raw_d = seller_devolvida(oid_a)
ws_end, bb_end = bal(ST, SID), bal(BT, BID)
lg = ledger(oid_a)
orow = order_row(oid_a)
ns = net_from_ledger(lg, SID, BID)
seller_net = money((ws_end or 0) - (wb_s or 0))
buyer_net = money((bb_end or 0) - (wb_b or 0))
liq = money((seller_net or 0) + (buyer_net or 0))
capture_eur = 3.00
over = liq is not None and liq > capture_eur + 0.01
rec(
    "DC_exact_release_then_refund",
    verdict="OVER_CAPTURE" if over else ("CLOSED" if (liq is not None and liq <= capture_eur + 0.01) else "INFO"),
    detail=(
        f"capture=3.00 seller {wb_s}->{ws_mid}->{ws_end} (net {seller_net}) "
        f"buyer {wb_b}->{bb_mid}->{bb_end} (net {buyer_net}) liquid={liq} "
        f"ledger={ns} flags rel={orow.get('wallet_release_processed_at')} "
        f"ref={orow.get('wallet_refund_processed_at')} status={orow.get('status')} "
        f"rev_http={st_r} dev_http={st_d}"
    ),
    capture=3.00,
    seller_after_release=money((ws_mid or 0) - (wb_s or 0)),
    seller_final_net=seller_net,
    buyer_final_net=buyer_net,
    liquid_distributed=liq,
    ledger=ns,
    tx=[
        {"type": t.get("type"), "amt": t.get("amount"), "wid": t.get("wallet_id"), "desc": t.get("description")}
        for t in lg
    ],
)

# retry same events
st, raw = fn("batata_release_seller_wallet_for_order", BT, {"p_order_id": oid_a})
rec("DC_retry_release_rpc", verdict="INFO", detail=f"http={st} {raw[:80]} bal_s={bal(ST,SID)}")
st, raw = fn("batata_refund_buyer_wallet_for_order", BT, {"p_order_id": oid_a})
rec("DC_retry_refund_rpc", verdict="INFO", detail=f"http={st} {raw[:80]} bal_b={bal(BT,BID)}")
st, raw = seller_devolvida(oid_a)[2], None
seller_devolvida(oid_a)
rec("DC_retry_devolvida_status", verdict="INFO",
    detail=f"s={bal(ST,SID)} b={bal(BT,BID)} n_tx={len(ledger(oid_a))}")

# ===========================================================================
# refund → release
# ===========================================================================
oid_b, *_ = make_order(price=3.00)
capture(oid_b, 300)
s0, b0 = bal(ST, SID), bal(BT, BID)
seller_devolvida(oid_b)
s1, b1 = bal(ST, SID), bal(BT, BID)
# try to complete + review after refund
st_c, raw_c = rest("PATCH", "orders", BT, f"id=eq.{oid_b}", {"status": "concluido"})
st_r, rev, raw_r = review_release(oid_b, "after-refund")
s2, b2 = bal(ST, SID), bal(BT, BID)
liq = money((s2 or 0) - (s0 or 0) + (b2 or 0) - (b0 or 0))
rec(
    "DC_refund_then_release",
    verdict="OVER_CAPTURE" if liq is not None and liq > 3.01 else "CLOSED" if liq is not None and liq <= 3.01 else "INFO",
    detail=f"seller {s0}->{s1}->{s2} buyer {b0}->{b1}->{b2} liquid={liq} conc_http={st_c} rev_http={st_r} {raw_r[:80]} ledger={net_from_ledger(ledger(oid_b),SID,BID)}",
    liquid=liq,
)

# ===========================================================================
# partial after release + remaining cap
# ===========================================================================
oid_c, *_ = make_order(price=3.00)
capture(oid_c, 300)
review_release(oid_c, "partial-after-rel")
st, raw = rest("POST", "order_disputes", BT, body={
    "order_id": oid_c, "buyer_id": BID, "reason": "outro", "description": f"{TAG}-p",
})
did = first(raw).get("id")
if did:
    created["d"].append(did)
    rest("PATCH", "order_disputes", ST, f"id=eq.{did}", {
        "seller_refund_percent": 40, "seller_offer_type": "partial_refund",
    })
s0, b0 = bal(ST, SID), bal(BT, BID)
st, raw = fn("batata_process_partial_refund_dispute", BT, {"p_order_id": oid_c, "p_refund_percent": 40})
s1, b1 = bal(ST, SID), bal(BT, BID)
# wallet already moved at release; measure from before capture? use ledger
ns = net_from_ledger(ledger(oid_c), SID, BID)
liq_led = ns.get("gross_credits")
rec(
    "DC_partial_after_release",
    verdict="OVER_CAPTURE" if (liq_led or 0) > 3.01 else "INFO",
    detail=f"http={st} body={raw[:180]} seller {s0}->{s1} buyer {b0}->{b1} ledger={ns} row={order_row(oid_c)}",
    liquid_ledger=liq_led,
)

# second partial / full after partial
st2, raw2 = fn("batata_process_partial_refund_dispute", BT, {"p_order_id": oid_c, "p_refund_percent": 100})
seller_devolvida(oid_c)
rec("DC_full_after_partial", verdict="INFO",
    detail=f"rpc2={st2} {raw2[:100]} after_dev s={bal(ST,SID)} b={bal(BT,BID)} n_tx={len(ledger(oid_c))}")

# ===========================================================================
# partial then release (review)
# ===========================================================================
oid_d, *_ = make_order(price=3.00)
capture(oid_d, 300)
st, raw = rest("POST", "order_disputes", BT, body={
    "order_id": oid_d, "buyer_id": BID, "reason": "outro", "description": f"{TAG}-pr",
})
did = first(raw).get("id")
if did:
    created["d"].append(did)
    rest("PATCH", "order_disputes", ST, f"id=eq.{did}", {
        "seller_refund_percent": 50, "seller_offer_type": "partial_refund",
    })
s0, b0 = bal(ST, SID), bal(BT, BID)
st, raw = fn("batata_process_partial_refund_dispute", BT, {"p_order_id": oid_d})
s1, b1 = bal(ST, SID), bal(BT, BID)
st_r, rev, raw_r = review_release(oid_d, "after-partial")
s2, b2 = bal(ST, SID), bal(BT, BID)
ns = net_from_ledger(ledger(oid_d), SID, BID)
liq = money((s2 or 0) - (s0 or 0) + (b2 or 0) - (b0 or 0))
rec(
    "DC_partial_then_release",
    verdict="OVER_CAPTURE" if (ns.get("gross_credits") or 0) > 3.01 else "CLOSED",
    detail=f"rpc={st} {raw[:120]} seller {s0}->{s1}->{s2} buyer {b0}->{b1}->{b2} liquid_w={liq} ledger={ns} rev={st_r}",
)

# several partials on fresh order (60 then 50) — first should consume flag
oid_e, *_ = make_order(price=3.00)
capture(oid_e, 300)
st, raw = rest("POST", "order_disputes", BT, body={
    "order_id": oid_e, "buyer_id": BID, "reason": "outro", "description": f"{TAG}-m",
})
did = first(raw).get("id")
if did:
    created["d"].append(did)
    rest("PATCH", "order_disputes", ST, f"id=eq.{did}", {
        "seller_refund_percent": 30, "seller_offer_type": "partial_refund",
    })
    fn("batata_process_partial_refund_dispute", BT, {"p_order_id": oid_e})
    rest("PATCH", "order_disputes", ST, f"id=eq.{did}", {
        "seller_refund_percent": 90, "seller_offer_type": "partial_refund",
    })
    st2, raw2 = fn("batata_process_partial_refund_dispute", BT, {"p_order_id": oid_e})
    rec("DC_second_partial_same_order", verdict="INFO",
        detail=f"http={st2} {raw2[:120]} ledger={net_from_ledger(ledger(oid_e),SID,BID)}")

# buyer forged percent after seller 10%
oid_f, *_ = make_order(price=3.00)
capture(oid_f, 300)
st, raw = rest("POST", "order_disputes", BT, body={
    "order_id": oid_f, "buyer_id": BID, "reason": "outro",
    "description": f"{TAG}-forge", "seller_refund_percent": 100,
    "seller_offer_type": "partial_refund",
})
did = first(raw).get("id")
if did:
    created["d"].append(did)
rec("P0_02_buyer_insert_pct", verdict="INFO",
    detail=f"http={st} pct={first(raw).get('seller_refund_percent')} set_by={first(raw).get('seller_offer_set_by')}")
if did:
    rest("PATCH", "order_disputes", ST, f"id=eq.{did}", {
        "seller_refund_percent": 10, "seller_offer_type": "partial_refund",
    })
    rest("PATCH", "order_disputes", BT, f"id=eq.{did}", {"seller_refund_percent": 100})
    st, raw = rest("GET", "order_disputes", BT, f"id=eq.{did}&select=seller_refund_percent,seller_offer_set_by")
    rec("P0_02_buyer_patch_pct_after_seller", verdict="INFO", detail=raw[:200])
    st, raw = fn("batata_process_partial_refund_dispute", BT, {"p_order_id": oid_f, "p_refund_percent": 100})
    rec("P0_02_rpc_after_buyer_raise", verdict="INFO",
        detail=f"http={st} {raw[:160]} ledger={net_from_ledger(ledger(oid_f),SID,BID)}")

# ===========================================================================
# ping-pong concluido ↔ devolvida
# ===========================================================================
oid_g, *_ = make_order(price=3.00)
capture(oid_g, 300)
review_release(oid_g, "ping")
s_a = bal(ST, SID)
seller_devolvida(oid_g)
rest("PATCH", "orders", BT, f"id=eq.{oid_g}", {"status": "concluido"})
rest("POST", "reviews", BT, body={
    "order_id": oid_g, "buyer_id": BID, "stars": 5, "comment": "ping2",
})
seller_devolvida(oid_g)
s_b, b_b = bal(ST, SID), bal(BT, BID)
rec("DC_pingpong_concluido_devolvida", verdict="INFO",
    detail=f"seller_after_first_rel={s_a} end s={s_b} b={b_b} ledger={net_from_ledger(ledger(oid_g),SID,BID)} status={order_row(oid_g).get('status')}")

# devolvida then review without recapture
# already covered in oid_b

# ===========================================================================
# concurrency: review vs devolvida
# ===========================================================================
oid_h, *_ = make_order(price=3.00)
capture(oid_h, 300)
rest("PATCH", "orders", BT, f"id=eq.{oid_h}", {"status": "concluido"})
s0, b0 = bal(ST, SID), bal(BT, BID)

def t_review():
    return rest("POST", "reviews", BT, body={
        "order_id": oid_h, "buyer_id": BID, "stars": 5, "comment": "race",
    })

def t_dev():
    return rest("PATCH", "orders", ST, f"id=eq.{oid_h}", {"status": "devolvida"})

with ThreadPoolExecutor(max_workers=2) as ex:
    futs = [ex.submit(t_review), ex.submit(t_dev)]
    race_out = [f.result() for f in futs]
s1, b1 = bal(ST, SID), bal(BT, BID)
ns = net_from_ledger(ledger(oid_h), SID, BID)
liq = money((s1 or 0) - (s0 or 0) + (b1 or 0) - (b0 or 0))
rec(
    "DC_race_review_vs_devolvida",
    verdict="OVER_CAPTURE" if (ns.get("gross_credits") or 0) > 3.01 or (liq or 0) > 3.01 else "CLOSED",
    detail=f"liquid_w={liq} ledger={ns} http={[x[0] for x in race_out]} bodies={[x[1][:80] for x in race_out]} flags={order_row(oid_h)}",
)

# concurrent double devolvida after release
oid_i, *_ = make_order(price=3.00)
capture(oid_i, 300)
review_release(oid_i, "race2")
s0, b0 = bal(ST, SID), bal(BT, BID)
with ThreadPoolExecutor(max_workers=2) as ex:
    futs = [ex.submit(seller_devolvida, oid_i) for _ in range(2)]
    _ = [f.result() for f in futs]
s1, b1 = bal(ST, SID), bal(BT, BID)
ns = net_from_ledger(ledger(oid_i), SID, BID)
rec("DC_race_double_devolvida", verdict="INFO",
    detail=f"seller {s0}->{s1} buyer {b0}->{b1} ledger={ns}")

# ===========================================================================
# price_total / qty / cents tamper around captured order
# ===========================================================================
oid_j, rowj, *_ = make_order(price=3.00, qty=1)
capture(oid_j, 300)
st, raw = rest("PATCH", "orders", BT, f"id=eq.{oid_j}", {"price_total": 999.00, "quantity": 20})
rec("tamper_price_qty_post_capture_buyer", verdict="INFO",
    detail=f"http={st} now={order_row(oid_j)}")
st, raw = rest("PATCH", "orders", ST, f"id=eq.{oid_j}", {"price_total": 999.00})
rec("tamper_price_post_capture_seller", verdict="INFO",
    detail=f"http={st} {raw[:160]} now={order_row(oid_j)}")
st, raw = rest("PATCH", "orders", BT, f"id=eq.{oid_j}", {"amount_paid_cents": 99999})
st2, raw2 = rest("PATCH", "orders", ST, f"id=eq.{oid_j}", {"amount_paid_cents": 99999})
rec("tamper_cents_jwt", verdict="OPEN" if order_row(oid_j).get("amount_paid_cents") not in (300, 300.0) else "CLOSED",
    detail=f"buyer={st} seller={st2} paid={order_row(oid_j).get('amount_paid_cents')}")
review_release(oid_j, "tamper")
seller_devolvida(oid_j)
ns = net_from_ledger(ledger(oid_j), SID, BID)
rec("tamper_then_dc_path", verdict="OVER_CAPTURE" if (ns.get("gross_credits") or 0) > 3.01 else "CLOSED",
    detail=f"ledger={ns} order={order_row(oid_j)}")

# mint without capture regression
oid_k, *_ = make_order(price=50.00)
rest("PATCH", "orders", ST, f"id=eq.{oid_k}", {"status": "pago"})
s0, b0 = bal(ST, SID), bal(BT, BID)
seller_devolvida(oid_k)
s1, b1 = bal(ST, SID), bal(BT, BID)
rec("REG_mint_pago_devolvida_no_capture",
    verdict="OPEN" if abs((b1 or 0) - (b0 or 0)) > 0.01 or abs((s1 or 0) - (s0 or 0)) > 0.01 else "CLOSED",
    detail=f"seller {s0}->{s1} buyer {b0}->{b1} paid={order_row(oid_k).get('amount_paid_cents')}")

oid_l, *_ = make_order(price=50.00)
rest("PATCH", "orders", ST, f"id=eq.{oid_l}", {"status": "pago"})
s0 = bal(ST, SID)
review_release(oid_l, "nocap")
s1 = bal(ST, SID)
rec("REG_mint_review_no_capture",
    verdict="OPEN" if abs((s1 or 0) - (s0 or 0)) > 0.01 else "CLOSED",
    detail=f"seller {s0}->{s1} paid={order_row(oid_l).get('amount_paid_cents')}")

# JWT credit rpc
st, raw = fn("batata_credit_wallet_once", BT, {
    "p_wallet_id": BID, "p_order_id": oid_a, "p_amount": 10, "p_type": "reembolso", "p_description": "x"
})
rec("REG_credit_wallet_once_jwt", verdict="INFO", detail=f"http={st} {raw[:120]}")

# ===========================================================================
# 2. CLAWBACK quality + payout-before-clawback
# ===========================================================================
# Inspect ledger of exact attack for DELETE vs estorno
lg_a = ledger(oid_a)
has_venda = any((t.get("type") or "").lower() == "venda" for t in lg_a)
has_estorno = any((t.get("type") or "").lower() == "estorno" for t in lg_a)
rec("CLAW_ledger_shape_after_release_refund",
    verdict="DELETED_VENDA" if (not has_venda and not has_estorno) else ("ESTORNO" if has_estorno else "VENDA_REMAINS"),
    detail=f"types={[t.get('type') for t in lg_a]} n={len(lg_a)}")

# Simulate seller payout of the released amount, then refund
oid_m, *_ = make_order(price=3.00)
capture(oid_m, 300)
s_before_rel = bal(ST, SID)
review_release(oid_m, "payout-then-claw")
s_after_rel = bal(ST, SID)
released = money((s_after_rel or 0) - (s_before_rel or 0))
# Real payout RPC (service_role = same path as Edge payout)
payout_key = f"ra-payout-{TAG}-{oid_m[:8]}"
st, raw = fn("batata_wallet_payout_debit", SVC, {
    "p_user_id": SID, "p_amount_cents": int(round((released or 0) * 100)), "p_idempotency_key": payout_key,
})
created["po"].append(payout_key)
s_after_pay = bal(ST, SID)
b_before = bal(BT, BID)
seller_devolvida(oid_m)
s_after_cb, b_after = bal(ST, SID), bal(BT, BID)
# Economic: seller kept payout (money left platform wallet), buyer credited
seller_kept_payout = released
buyer_got = money((b_after or 0) - (b_before or 0))
platform_out = money((seller_kept_payout or 0) + (buyer_got or 0))
rec(
    "CLAW_payout_then_devolvida",
    verdict="PLATFORM_LOSS" if (platform_out or 0) > 3.01 else "RECOVERED",
    detail=(
        f"released={released} payout_rpc={st} {str(raw)[:140]} "
        f"seller {s_before_rel}->{s_after_rel}->{s_after_pay}->{s_after_cb} "
        f"buyer +{buyer_got} platform_out_vs_capture={platform_out}/3.00 "
        f"ledger={net_from_ledger(ledger(oid_m),SID,BID)}"
    ),
    released=released,
    buyer_refund=buyer_got,
    platform_out=platform_out,
    payout_http=st,
    payout_body=raw[:240] if isinstance(raw, str) else raw,
)

# Floor to 0: drain seller wallet to 0 after release, then devolvida
oid_n, *_ = make_order(price=3.00)
capture(oid_n, 300)
review_release(oid_n, "floor0")
s_rel = bal(ST, SID)
set_bal(SID, 0)  # remaining funds already extracted
b0 = bal(BT, BID)
seller_devolvida(oid_n)
s_end, b_end = bal(ST, SID), bal(BT, BID)
rec(
    "CLAW_floor_zero_after_drain",
    verdict="INFO",
    detail=f"seller_after_rel={s_rel} after_drain_then_cb={s_end} buyer {b0}->{b_end} ledger={net_from_ledger(ledger(oid_n),SID,BID)}",
)
# restore seller lab balance later globally

# repeat clawback
st, raw = fn("batata_clawback_seller_wallet_for_order", SVC, {"p_order_id": oid_a})
rec("CLAW_repeat_svc", verdict="INFO", detail=f"http={st} {raw[:80]} s={bal(ST,SID)}")

# ===========================================================================
# 3. Stripe refund + wallet
# ===========================================================================
# A) captured + released, then simulate Stripe refund finalize → cancelado
oid_o, *_ = make_order(price=3.00, method="Pagamento na app (Stripe)")
capture(oid_o, 300)
review_release(oid_o, "stripe-ref")
s0, b0 = bal(ST, SID), bal(BT, BID)
st, raw = fn("batata_finalize_stripe_order_refund", SVC, {
    "p_order_id": oid_o,
    "p_refund_id": f"re_test_{TAG}",
    "p_payment_intent_id": "pi_test_fake",
    "p_session_id": None,
    "p_amount_cents": 300,
})
s1, b1 = bal(ST, SID), bal(BT, BID)
orow = order_row(oid_o)
rec(
    "STRIPE_finalize_after_release",
    verdict="INFO",
    detail=f"rpc={st} {raw[:180]} seller {s0}->{s1} buyer {b0}->{b1} status={orow.get('status')} stripe_ref={orow.get('stripe_refund_id')} ledger={net_from_ledger(ledger(oid_o),SID,BID)}",
)
# then try devolvida anyway
st_d, od, raw_d = seller_devolvida(oid_o)
s2, b2 = bal(ST, SID), bal(BT, BID)
rec(
    "STRIPE_then_devolvida",
    verdict="DOUBLE" if (b2 or 0) - (b1 or 0) > 0.01 else "BLOCKED",
    detail=f"http={st_d} seller {s1}->{s2} buyer {b1}->{b2} status={order_row(oid_o).get('status')}",
)

# B) stripe_refund_id set but status still concluido (inconsistent), then devolvida
oid_p, *_ = make_order(price=3.00, method="Pagamento na app (Stripe)")
capture(oid_p, 300)
review_release(oid_p, "flag-only")
s0, b0 = bal(ST, SID), bal(BT, BID)
rest("PATCH", "orders", SVC, f"id=eq.{oid_p}", {
    "stripe_refund_id": f"re_orphan_{TAG}",
    "stripe_refunded_at": "2026-08-27T00:00:00Z",
})
seller_devolvida(oid_p)
s1, b1 = bal(ST, SID), bal(BT, BID)
ns = net_from_ledger(ledger(oid_p), SID, BID)
rec(
    "STRIPE_orphan_refund_id_then_devolvida",
    verdict="WALLET_AFTER_STRIPE_FLAG" if (b1 or 0) - (b0 or 0) > 0.01 else "NO_WALLET",
    detail=f"seller {s0}->{s1} buyer {b0}->{b1} ledger={ns} order={order_row(oid_p)}",
)

# C) refund-order edge JWT buyer vs seller
st, raw = edge("refund-order", BT, {"order_id": oid_o})
rec("STRIPE_refund_order_buyer", verdict="INFO", detail=f"http={st} {raw[:160]}")
st, raw = edge("refund-order", ST, {"order_id": oid_o})
rec("STRIPE_refund_order_seller_already", verdict="INFO", detail=f"http={st} {raw[:200]}")

# D) JWT cannot call finalize
st, raw = fn("batata_finalize_stripe_order_refund", BT, {
    "p_order_id": oid_p, "p_refund_id": "re_jwt",
})
rec("STRIPE_finalize_jwt", verdict="INFO", detail=f"http={st} {raw[:120]}")

# E) cancelado without stripe after release
oid_q, *_ = make_order(price=3.00)
capture(oid_q, 300)
review_release(oid_q, "cancel")
s0, b0 = bal(ST, SID), bal(BT, BID)
st, raw = rest("PATCH", "orders", ST, f"id=eq.{oid_q}", {"status": "cancelado"})
st_b, raw_b = rest("PATCH", "orders", BT, f"id=eq.{oid_q}", {"status": "cancelado"})
# svc cancel
st_s, raw_s = rest("PATCH", "orders", SVC, f"id=eq.{oid_q}", {"status": "cancelado"})
s1, b1 = bal(ST, SID), bal(BT, BID)
rec("CANCEL_after_release", verdict="INFO",
    detail=f"seller_jwt={st} buyer_jwt={st_b} svc={st_s} seller {s0}->{s1} buyer {b0}->{b1} status={order_row(oid_q).get('status')} {raw_s[:80]}")

# ===========================================================================
# 4. CHAT
# ===========================================================================
st, raw = rest("POST", "chats", BT, body={"user_a": BID, "user_b": SID})
chat_id = first(raw).get("id")
if not chat_id:
    st, raw = rest("GET", "chats", BT, f"or=(and(user_a.eq.{BID},user_b.eq.{SID}),and(user_a.eq.{SID},user_b.eq.{BID}))&select=id&limit=1")
    chat_id = first(raw).get("id")
if chat_id:
    created["c"].append(chat_id)
st, raw = rest("POST", "chat_messages", ST, body={
    "chat_id": chat_id, "sender_id": SID, "receiver_id": BID, "text": f"seller-orig-{TAG}",
})
mid_s = first(raw).get("id")
if mid_s:
    created["m"].append(mid_s)
st, raw = rest("PATCH", "chat_messages", BT, f"id=eq.{mid_s}", {"text": "buyer-rewrote-AGAIN"})
rec("CHAT_cross_edit_text",
    verdict="OPEN" if "buyer-rewrote" in raw else ("CLOSED" if st in (200, 201) and first(raw).get("text", "").startswith("seller-orig") else "INFO"),
    detail=f"http={st} text={first(raw).get('text')} body={raw[:160]}")
st, raw = rest("PATCH", "chat_messages", BT, f"id=eq.{mid_s}", {"sender_id": BID})
rec("CHAT_spoof_sender_update", verdict="INFO",
    detail=f"http={st} sender={first(raw).get('sender_id')}")
st, raw = rest("PATCH", "chat_messages", BT, f"id=eq.{mid_s}", {"is_read": True})
rec("CHAT_mark_read_other",
    verdict="OK" if first(raw).get("is_read") is True else "FAIL",
    detail=f"http={st} is_read={first(raw).get('is_read')} text={first(raw).get('text')}")
st, raw = rest("DELETE", "chat_messages", BT, f"id=eq.{mid_s}")
rec("CHAT_delete_others_msg",
    verdict="OPEN" if st in (200, 204) else "CLOSED",
    detail=f"http={st} {raw[:80]}")
# own message edit
st, raw = rest("POST", "chat_messages", BT, body={
    "chat_id": chat_id, "sender_id": BID, "receiver_id": SID, "text": f"buyer-own-{TAG}",
})
mid_b = first(raw).get("id")
if mid_b:
    created["m"].append(mid_b)
st, raw = rest("PATCH", "chat_messages", BT, f"id=eq.{mid_b}", {"text": "buyer-edited-own"})
rec("CHAT_edit_own", verdict="INFO", detail=f"http={st} text={first(raw).get('text')}")
# stranger
# use anon-as-unauth: Bearer anon without user - actually ANON jwt isn't a user. Skip.
st, raw = rest("GET", "chat_messages", BT, f"chat_id=neq.{chat_id}&select=id,text,sender_id&limit=5")
foreign = jload(raw) if isinstance(jload(raw), list) else []
rec("CHAT_stranger_select", verdict="OPEN" if foreign else "CLOSED",
    detail=f"n={len(foreign) if isinstance(foreign,list) else 'err'}")
st, raw = rest("POST", "chat_messages", BT, body={
    "chat_id": "00000000-0000-0000-0000-000000000001", "sender_id": BID, "text": "x",
})
rec("CHAT_insert_unknown", verdict="INFO", detail=f"http={st} {raw[:80]}")

# ===========================================================================
# 5. QUANTITY / STOCK
# ===========================================================================
P2, *_ = make_product(qty=2, price=5.00, title=f"RA-QTY-{TAG}")
# qty > stock
st, raw = rest("POST", "orders", BT, body={
    "buyer_id": BID, "seller_id": SID, "product_id": P2, "quantity": 50,
    "price_total": 250, "status": "reserva_pendente", "payment_method": "MB WAY", "shipping_method": "mao",
})
oid_q1 = first(raw).get("id")
if oid_q1:
    created["o"].append(oid_q1)
rec("QTY_gt_stock_insert", verdict="INFO",
    detail=f"http={st} stored_qty={first(raw).get('quantity')} stock=2")
# qty 0 / neg
st, raw = rest("POST", "orders", BT, body={
    "buyer_id": BID, "seller_id": SID, "product_id": P2, "quantity": 0,
    "price_total": 5, "status": "reserva_pendente", "payment_method": "MB WAY", "shipping_method": "mao",
})
rec("QTY_zero_insert", verdict="INFO", detail=f"http={st} qty={first(raw).get('quantity')} {raw[:100]}")
oid_z = first(raw).get("id")
if oid_z:
    created["o"].append(oid_z)
st, raw = rest("POST", "orders", BT, body={
    "buyer_id": BID, "seller_id": SID, "product_id": P2, "quantity": -3,
    "price_total": 5, "status": "reserva_pendente", "payment_method": "MB WAY", "shipping_method": "mao",
})
rec("QTY_neg_insert", verdict="INFO", detail=f"http={st} qty={first(raw).get('quantity')} {raw[:100]}")
oid_neg = first(raw).get("id")
if oid_neg:
    created["o"].append(oid_neg)
# two orders each qty=2 on stock=2
st, raw = rest("POST", "orders", BT, body={
    "buyer_id": BID, "seller_id": SID, "product_id": P2, "quantity": 2,
    "price_total": 10, "status": "reserva_pendente", "payment_method": "MB WAY", "shipping_method": "mao",
})
oid_t1 = first(raw).get("id")
if oid_t1:
    created["o"].append(oid_t1)
st, raw = rest("POST", "orders", BT, body={
    "buyer_id": BID, "seller_id": SID, "product_id": P2, "quantity": 2,
    "price_total": 10, "status": "reserva_pendente", "payment_method": "MB WAY", "shipping_method": "mao",
})
oid_t2 = first(raw).get("id")
if oid_t2:
    created["o"].append(oid_t2)
rec("QTY_two_orders_each_full_stock", verdict="INFO",
    detail=f"q1={order_row(oid_t1).get('quantity') if oid_t1 else None} q2={order_row(oid_t2).get('quantity') if oid_t2 else None}")
if oid_t1:
    rest("PATCH", "orders", ST, f"id=eq.{oid_t1}", {"status": "pago"})
if oid_t2:
    st, raw = rest("PATCH", "orders", ST, f"id=eq.{oid_t2}", {"status": "pago"})
    rec("QTY_second_pago_oversell",
        verdict="OVERSELL" if first(raw).get("status") == "pago" else "BLOCKED",
        detail=f"http={st} status={first(raw).get('status')} {raw[:160]} prod={first(rest('GET','products',ST,f'id=eq.{P2}&select=quantity')[1]).get('quantity') if False else ''}")
st, raw = rest("GET", "products", ST, f"id=eq.{P2}&select=quantity")
rec("QTY_stock_after_double_pago", verdict="INFO", detail=f"qty={first(raw).get('quantity')}")

# patch qty after create
if oid_q1:
    st, raw = rest("PATCH", "orders", BT, f"id=eq.{oid_q1}", {"quantity": 99})
    rec("QTY_patch_after_create", verdict="INFO",
        detail=f"http={st} qty={first(raw).get('quantity')}")

# checkout qty vs stock
if oid_q1:
    st, raw = edge("create-payment-intent", BT, {"order_id": oid_q1})
    rec("QTY_checkout_over_stock", verdict="INFO", detail=f"http={st} {raw[:220]}")

# stock 0 checkout of qty 1 order
P0, *_ = make_product(qty=0, price=1.00, title=f"RA-0-{TAG}")
st, raw = rest("POST", "orders", BT, body={
    "buyer_id": BID, "seller_id": SID, "product_id": P0, "quantity": 1,
    "price_total": 1, "status": "reserva_pendente", "payment_method": "MB WAY", "shipping_method": "mao",
})
oid_0 = first(raw).get("id")
if oid_0:
    created["o"].append(oid_0)
rec("QTY_order_on_stock0", verdict="INFO", detail=f"http={st} qty={first(raw).get('quantity')}")
if oid_0:
    st, raw = rest("PATCH", "orders", ST, f"id=eq.{oid_0}", {"status": "pago"})
    rec("QTY_pago_stock0", verdict="OVERSELL" if first(raw).get("status")=="pago" else "BLOCKED",
        detail=f"http={st} {raw[:160]}")
    st, raw = edge("create-payment-intent", BT, {"order_id": oid_0})
    rec("QTY_checkout_stock0", verdict="INFO", detail=f"http={st} {raw[:180]}")

# restore stock on devolvida isolated
P3, *_ = make_product(qty=4, price=2.00, title=f"RA-STK-{TAG}")
st, raw = rest("POST", "orders", BT, body={
    "buyer_id": BID, "seller_id": SID, "product_id": P3, "quantity": 1,
    "price_total": 2, "status": "reserva_pendente", "payment_method": "MB WAY", "shipping_method": "mao",
})
oid_st = first(raw).get("id")
if oid_st:
    created["o"].append(oid_st)
rest("PATCH", "orders", ST, f"id=eq.{oid_st}", {"status": "pago"})
st, raw = rest("GET", "products", ST, f"id=eq.{P3}&select=quantity")
q1 = first(raw).get("quantity")
rest("PATCH", "orders", ST, f"id=eq.{oid_st}", {"status": "devolvida"})
st, raw = rest("GET", "products", ST, f"id=eq.{P3}&select=quantity")
q2 = first(raw).get("quantity")
rest("PATCH", "orders", ST, f"id=eq.{oid_st}", {"status": "devolvida"})
st, raw = rest("GET", "products", ST, f"id=eq.{P3}&select=quantity")
q3 = first(raw).get("quantity")
rec("STOCK_pago_devolvida_restore",
    verdict="DOUBLE_RESTORE" if q3 is not None and q2 is not None and q3 > q2 else ("RESTORED" if q2 == 4 else "INFO"),
    detail=f"4->{q1}->{q2}->{q3}")

# live qty RPC
st, raw = fn("batata_live_item_total_qty", ST, {"p_live_item_id": str(uuid.uuid4())})
rec("LIVE_qty_missing_item", verdict="INFO", detail=f"http={st} {raw[:60]}")

# ===========================================================================
# 6. REVIEWS fields + insert guards
# ===========================================================================
st, raw = rest("GET", "reviews", BT, "select=*&limit=8")
revs = jload(raw) if isinstance(jload(raw), list) else []
keys = sorted({k for r in revs if isinstance(r, dict) for k in r.keys()}) if revs else []
other = [r for r in revs if r.get("buyer_id") != BID] if isinstance(revs, list) else []
rec("REV_select_public_fields", verdict="INFO",
    detail=f"n={len(revs) if isinstance(revs,list) else 'err'} keys={keys} others={len(other)}")
# unauthenticated
st, raw = http("GET", f"{BASE}/rest/v1/reviews?select=*&limit=3", ANON, prefer=None)
anon_revs = jload(raw)
rec("REV_select_anon", verdict="INFO",
    detail=f"http={st} n={len(anon_revs) if isinstance(anon_revs,list) else str(anon_revs)[:80]}")
# insert other order
st, raw = rest("GET", "orders", SVC, f"buyer_id=neq.{BID}&select=id,status&limit=1")
other_oid = first(raw).get("id")
if other_oid:
    st, raw = rest("POST", "reviews", BT, body={
        "order_id": other_oid, "buyer_id": BID, "stars": 1, "comment": "x",
    })
    rec("REV_insert_foreign_order", verdict="OPEN" if st in (200, 201) else "CLOSED",
        detail=f"http={st} {raw[:120]}")
st, raw = rest("POST", "reviews", BT, body={
    "order_id": oid_k, "buyer_id": BID, "stars": 5, "comment": "unpaid",
})
rec("REV_insert_unpaid", verdict="OPEN" if st in (200, 201) else "CLOSED",
    detail=f"http={st} {raw[:120]}")
# update/delete own
if created["r"]:
    rid = created["r"][0]
    st, raw = rest("PATCH", "reviews", BT, f"id=eq.{rid}", {"stars": 1, "comment": "edited"})
    rec("REV_update_own", verdict="INFO", detail=f"http={st} stars={first(raw).get('stars')}")
    st, raw = rest("PATCH", "reviews", ST, f"id=eq.{rid}", {"stars": 5, "comment": "seller-edit"})
    rec("REV_update_by_seller", verdict="OPEN" if first(raw).get("comment") == "seller-edit" else "CLOSED",
        detail=f"http={st} {raw[:100]}")

# ===========================================================================
# extra RPCs that might credit
# ===========================================================================
for name, args in [
    ("batata_admin_resolve_dispute", {"p_order_id": oid_a}),
    ("batata_tip_from_wallet", {"p_to": SID, "p_amount": 1}),
    ("credit_wallet", {"p_wallet_id": BID, "p_amount": 1}),
]:
    st, raw = fn(name, BT, args)
    rec(f"RPC_{name}", verdict="INFO", detail=f"http={st} {raw[:100]}")

# ===========================================================================
# Cleanup
# ===========================================================================
# wallets back
set_bal(BID, W0B)
set_bal(SID, W0S)
# payout ledger rows
for key in created["po"]:
    rest("DELETE", "wallet_payout_ledger", SVC, f"idempotency_key=eq.{key}")
for rid in created["r"]:
    rest("DELETE", "reviews", SVC, f"id=eq.{rid}")
for did in created["d"]:
    rest("DELETE", "order_disputes", SVC, f"id=eq.{did}")
# extra reviews created in race
rest("DELETE", "reviews", SVC, f"comment=eq.race")
rest("DELETE", "reviews", SVC, f"comment=like.RA-*")
for mid in created["m"]:
    rest("DELETE", "chat_messages", SVC, f"id=eq.{mid}")
# chat created this run: only delete if title/tag in messages gone
for oid in created["o"]:
    rest("DELETE", "wallet_transactions", SVC, f"order_id=eq.{oid}")
    rest("DELETE", "fleaber_commissions", SVC, f"order_id=eq.{oid}")
    rest("DELETE", "orders", SVC, f"id=eq.{oid}")
for pid in created["p"]:
    rest("DELETE", "products", SVC, f"id=eq.{pid}")
# leftover reviews on deleted orders
rest("DELETE", "reviews", SVC, f"comment=eq.exact-dc")
rest("DELETE", "reviews", SVC, f"comment=eq.after-refund")
rest("DELETE", "chat_messages", SVC, f"text=eq.buyer-edited-own")
rest("DELETE", "chat_messages", SVC, f"text=like.*{TAG}*")

WFB, WFS = bal(BT, BID), bal(ST, SID)
rec("cleanup_wallets", verdict="RESTORED" if WFB == W0B and WFS == W0S else "DRIFT",
    detail=f"buyer {W0B}->{WFB} seller {W0S}->{WFS}")

OUT_PATH.write_text(json.dumps({"tag": TAG, "w0": {"b": W0B, "s": W0S}, "rows": rows}, indent=2, default=str), encoding="utf-8")
print("WROTE", OUT_PATH)
print("N", len(rows))
