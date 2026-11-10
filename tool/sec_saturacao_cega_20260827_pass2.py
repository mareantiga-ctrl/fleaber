#!/usr/bin/env python3
"""Passagem 2–3 follow-up: variantes, limpeza, superfícies em falta."""
from __future__ import annotations

import json
import ssl
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = ROOT / "tool" / "live_ops_staging.env"
CTX = ssl.create_default_context()
STAGING = "fxdknzrqjenzqcvnwqqq"
BASE = f"https://{STAGING}.supabase.co"
FINDINGS: list[dict] = []
PROBES: list[dict] = []

def load_env():
    kv = {}
    for line in ENV_PATH.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.strip().startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        kv[k.strip()] = v.strip()
    return kv

def http(method, url, token=None, apikey=None, body=None, extra=None, timeout=45):
    headers = {"Accept": "application/json", "apikey": apikey}
    headers["Authorization"] = f"Bearer {token or apikey}"
    if extra:
        headers.update(extra)
    data = None
    if body is not None:
        raw = body if isinstance(body, (bytes, bytearray)) else json.dumps(body).encode()
        data = raw
        headers.setdefault("Content-Type", "application/json")
    req = Request(url, data=data, headers=headers, method=method)
    try:
        with urlopen(req, timeout=timeout, context=CTX) as resp:
            raw = resp.read()
            try:
                parsed = json.loads(raw.decode() or "null")
            except Exception:
                parsed = raw.decode("utf-8", errors="replace")[:3000]
            return resp.status, parsed
    except HTTPError as e:
        raw = e.read()
        try:
            parsed = json.loads(raw.decode() or "null")
        except Exception:
            parsed = raw.decode("utf-8", errors="replace")[:3000]
        return e.code, parsed
    except URLError as e:
        return 0, {"error": str(e.reason)}

def snip(o, n=700):
    return json.dumps(o, default=str, ensure_ascii=False)[:n]

def probe(name, **kw):
    PROBES.append({"name": name, **kw})
    print(f"  {name}: {kw.get('status')} {str(kw.get('note') or kw.get('body') or '')[:180]}")

def finding(**kw):
    FINDINGS.append(kw)
    title = str(kw.get("title") or "").encode("ascii", "replace").decode("ascii")
    print(f"[FINDING {kw['severity']}] {kw['id']} {title}")

def rest(method, path, token, apikey, body=None, qs=""):
    return http(method, f"{BASE}/rest/v1/{path}{qs}", token=token, apikey=apikey, body=body, extra={"Prefer": "return=representation"})

def rpc(name, token, apikey, args=None):
    return http("POST", f"{BASE}/rest/v1/rpc/{name}", token=token, apikey=apikey, body=args or {})

def edge(name, token, apikey, body=None, method="POST", qs=""):
    return http(method, f"{BASE}/functions/v1/{name}{qs}", token=token or apikey, apikey=apikey, body=body)

def login(email, password, anon):
    st, p = http("POST", f"{BASE}/auth/v1/token?grant_type=password", token=anon, apikey=anon, body={"email": email, "password": password})
    if st != 200:
        raise SystemExit(f"login {email} {st} {p}")
    return p["access_token"]

def main():
    e = load_env()
    anon, svc = e["SUPABASE_ANON_KEY"], e["SUPABASE_SERVICE_ROLE_KEY"]
    buyer_id, seller_id = e["LIVE_OPS_TEST_BUYER_ID"], e["LIVE_OPS_TEST_SELLER_ID"]
    buyer = login(e["LIVE_OPS_TEST_BUYER_EMAIL"], e["LIVE_OPS_TEST_BUYER_PASSWORD"], anon)
    seller = login(e["LIVE_OPS_TEST_SELLER_EMAIL"], e["LIVE_OPS_TEST_SELLER_PASSWORD"], anon)

    # --- CLEANUP: revert privileged profile fields ---
    st, p = rest("PATCH", "profiles", buyer, anon, {
        "user_type": "comprador",
        "phone_verified_at": None,
        "iban": None,
    }, qs=f"?id=eq.{buyer_id}")
    probe("revert_buyer_profile", status=st, body=snip(p, 250))
    st, p = rest("GET", "profiles", buyer, anon, qs=f"?id=eq.{buyer_id}&select=id,user_type,phone_verified_at,iban,mb_way")
    probe("buyer_profile_after_revert", status=st, body=snip(p))

    # End mux live created in pass 1
    live_id = "0f0f239d-e2c6-44bd-8a13-c1ccf2fa3495"
    st, p = rest("PATCH", "lives", svc, svc, {"status": "ended", "is_active": False}, qs=f"?id=eq.{live_id}")
    probe("end_mux_live_svc", status=st, body=snip(p, 200))
    st, p = edge("complete-mux-live", buyer, anon, {"live_id": live_id})
    probe("complete_own_mux", status=st, body=snip(p, 250))

    # Cancel hostile reservation
    st, p = rest("PATCH", "live_reservation_requests", buyer, anon, {"status": "cancelled", "requested_qty": 1}, qs="?id=eq.bb9d65e0-7750-4d6f-b5fb-952cd1f138f0")
    probe("cancel_hostile_reservation", status=st, body=snip(p, 200))

    # --- AUTH user_type vendedor (re-test then revert) ---
    st, before = rest("GET", "profiles", buyer, anon, qs=f"?id=eq.{buyer_id}&select=id,user_type,phone_verified_at")
    st, p = rest("PATCH", "profiles", buyer, anon, {"user_type": "vendedor"}, qs=f"?id=eq.{buyer_id}")
    st, after = rest("GET", "profiles", buyer, anon, qs=f"?id=eq.{buyer_id}&select=id,user_type")
    probe("user_type_to_vendedor", status=st, before=snip(before), after=snip(after), patch=snip(p, 150))
    if isinstance(after, list) and after and str(after[0].get("user_type")).lower() == "vendedor":
        finding(
            id="SAT-AUTH-06",
            severity="P1",
            surface="AUTH",
            title="JWT comprador promove-se a vendedor (user_type)",
            preconditions="perfil comprador",
            identity="buyer",
            request="PATCH profiles user_type=vendedor",
            response=snip(after),
            before=snip(before),
            after=after[0].get("user_type"),
            impact="Acesso a Mux/create-live e fluxos de vendedor sem KYC.",
            confidence="alta",
            variant="vendedor",
            false_positive="produto permite qualquer conta ser vendedor — ainda é elevação sem fluxo de onboarding se a UI não o expõe",
        )
    rest("PATCH", "profiles", buyer, anon, {"user_type": "comprador"}, qs=f"?id=eq.{buyer_id}")

    # phone_verified variants
    st, p = rest("PATCH", "profiles", buyer, anon, {"phone_verified_at": "2030-12-31T23:59:59Z"}, qs=f"?id=eq.{buyer_id}")
    st, after = rest("GET", "profiles", buyer, anon, qs=f"?id=eq.{buyer_id}&select=phone_verified_at")
    probe("phone_verified_future", status=st, body=snip(after))
    rest("PATCH", "profiles", buyer, anon, {"phone_verified_at": None}, qs=f"?id=eq.{buyer_id}")

    # Cross-user PII with correct columns
    st, p = rest("GET", "profiles", buyer, anon, qs=f"?id=eq.{seller_id}&select=id,full_name,iban,mb_way,phone,phone_verified_at,user_type,handle")
    probe("buyer_read_seller_pii", status=st, body=snip(p))
    leaked = {}
    if isinstance(p, list) and p:
        leaked = {k: p[0].get(k) for k in ("iban", "mb_way", "phone") if p[0].get(k)}
        if leaked:
            finding(id="SAT-PII-02b", severity="P1", surface="PROFILES", title="Buyer lê IBAN/MB WAY do seller",
                    preconditions="id conhecido", identity="buyer", request="GET profiles seller",
                    response=snip(leaked), before=None, after=None, impact="PII financeiro",
                    confidence="alta", variant="mb_way/iban", false_positive="directório intencional")
    st, p = rest("GET", "profiles", None, anon, qs="?select=id,full_name,iban,mb_way,phone&limit=5")
    probe("anon_profiles_pii", status=st, body=snip(p))
    st, p = rest("GET", "profiles", seller, anon, qs=f"?id=eq.{buyer_id}&select=id,iban,mb_way,phone,full_name")
    probe("seller_read_buyer_pii", status=st, body=snip(p))

    # --- PRICING variants that pass Stripe 50c min ---
    st, prod = rest("POST", "products", seller, anon, {
        "seller_id": seller_id, "title": "SATCEGA-P2 unit 40", "price": 40.00,
        "quantity": 8, "list_on_marketplace": False, "available_for_live": False,
        "state": "Bom", "category": "Outros",
    })
    probe("p2_product", status=st, body=snip(prod, 180))
    pid = prod[0]["id"] if isinstance(prod, list) and prod else None
    if pid:
        # contract 50 cents (min stripe item)
        st, o = rest("POST", "orders", buyer, anon, {
            "product_id": pid, "buyer_id": buyer_id, "seller_id": seller_id,
            "price_total": 40, "payment_method": "Pagamento na App",
            "status": "reserva_pendente", "quantity": 1,
            "contract_unit_cents": 50, "contract_qty": 1,
            "shipping_method": "Entrega em mão (€0.00)",
        })
        probe("order_contract_50c", status=st, body=snip(o, 300))
        oid50 = o[0]["id"] if isinstance(o, list) and o else None
        if oid50:
            st, ck = edge("create-payment-intent", buyer, anon, {
                "order_id": oid50, "buyer_id": buyer_id, "shipping_method": "hand",
            })
            probe("checkout_contract_50c_hand", status=st, body=snip(ck))
            amt = ck.get("server_amount_cents") if isinstance(ck, dict) else None
            if st == 200 and isinstance(amt, int) and amt < 4000:
                finding(id="SAT-CHK-05", severity="P0", surface="CHECKOUT",
                        title="Checkout Stripe a ~0.50€+taxas com contract_unit_cents=50 vs catálogo 40€",
                        preconditions="SAT-PRC-01 variante ≥50c", identity="buyer",
                        request="create-payment-intent hand", response=snip(ck),
                        before={"catalog": 40.0, "contract_unit_cents": 50},
                        after=amt, impact="Invariante A/K — cobrança ~1€ em artigo 40€.",
                        confidence="alta", variant="50c hand", false_positive="nenhum")
        # contract_qty 8 * 50c = 400c items
        st, o = rest("POST", "orders", buyer, anon, {
            "product_id": pid, "buyer_id": buyer_id, "seller_id": seller_id,
            "price_total": 40, "payment_method": "Pagamento na App",
            "status": "reserva_pendente", "quantity": 1,
            "contract_unit_cents": 50, "contract_qty": 8,
        })
        probe("order_qty_split_8", status=st, body=snip(o, 250))
        oidq = o[0]["id"] if isinstance(o, list) and o else None
        if oidq:
            st, ck = edge("create-payment-intent", buyer, anon, {
                "order_id": oidq, "buyer_id": buyer_id, "shipping_method": "hand",
            })
            probe("checkout_qty_split_8x50c", status=st, body=snip(ck))
            amt = ck.get("server_amount_cents") if isinstance(ck, dict) else None
            # honest 8*40€ = 320€; hostile 8*0.50=4€ + prot
            if st == 200 and isinstance(amt, int) and amt < 20000:
                finding(id="SAT-CHK-06", severity="P0", surface="CHECKOUT",
                        title="contract_qty=8 com quantity=1 cobra 8×0,50€",
                        preconditions="stock 8, quantity 1", identity="buyer",
                        request="create-payment-intent", response=snip(ck),
                        before={"catalog_unit": 40, "qty_row": 1, "contract_qty": 8},
                        after=amt, impact="Undercharge + possível consumo de 8 unidades no settle.",
                        confidence="alta", variant="qty split", false_positive="checkout bloqueia stock")
        # proposta 1.00
        st, o = rest("POST", "orders", buyer, anon, {
            "product_id": pid, "buyer_id": buyer_id, "seller_id": seller_id,
            "price_total": 1.00, "payment_method": "proposta negociada",
            "status": "reserva_pendente", "quantity": 1,
        })
        probe("order_proposta_1eur", status=st, body=snip(o, 250))
        oidp = o[0]["id"] if isinstance(o, list) and o else None
        if oidp:
            st, ck = edge("create-payment-intent", buyer, anon, {
                "order_id": oidp, "buyer_id": buyer_id, "shipping_method": "carrier",
            })
            probe("checkout_proposta_1eur_carrier", status=st, body=snip(ck))
            amt = ck.get("server_amount_cents") if isinstance(ck, dict) else None
            if st == 200 and isinstance(amt, int) and amt < 2000:
                finding(id="SAT-CHK-07", severity="P0", surface="CHECKOUT",
                        title="Proposta 1€ + portes 3.50 → Session << catálogo 40€",
                        preconditions="payment_method contém proposta", identity="buyer",
                        request="create-payment-intent carrier", response=snip(ck),
                        before={"catalog": 40}, after=amt, impact="Undercharge com portes reais.",
                        confidence="alta", variant="proposta 1 + carrier", false_positive="nenhum")
        # seller hike catalog then checkout sealed order
        if oid50:
            rest("PATCH", "products", seller, anon, {"price": 9.00}, qs=f"?id=eq.{pid}")
            st, ck = edge("create-payment-intent", buyer, anon, {
                "order_id": oid50, "buyer_id": buyer_id, "shipping_method": "hand",
            })
            probe("checkout_after_catalog_drop", status=st, body=snip(ck))
            rest("PATCH", "products", seller, anon, {"price": 99.00}, qs=f"?id=eq.{pid}")
            st, ck2 = edge("create-payment-intent", buyer, anon, {
                "order_id": oid50, "buyer_id": buyer_id, "shipping_method": "hand",
            })
            probe("checkout_after_catalog_hike", status=st, body=snip(ck2))
        # bag 2 lines sealed cheap
        st, o1 = rest("POST", "orders", buyer, anon, {
            "product_id": pid, "buyer_id": buyer_id, "seller_id": seller_id,
            "price_total": 40, "payment_method": "Pagamento na App",
            "status": "reserva_pendente", "quantity": 1, "contract_unit_cents": 100,
        })
        pid2 = None
        st, prod2 = rest("POST", "products", seller, anon, {
            "seller_id": seller_id, "title": "SATCEGA-P2 bag2", "price": 25.00,
            "quantity": 3, "list_on_marketplace": False, "state": "Bom", "category": "Outros",
        })
        if isinstance(prod2, list) and prod2:
            pid2 = prod2[0]["id"]
            st, o2 = rest("POST", "orders", buyer, anon, {
                "product_id": pid2, "buyer_id": buyer_id, "seller_id": seller_id,
                "price_total": 25, "payment_method": "Pagamento na App",
                "status": "reserva_pendente", "quantity": 1, "contract_unit_cents": 100,
            })
            lines = []
            if isinstance(o1, list) and o1:
                lines.append({"order_id": o1[0]["id"]})
            if isinstance(o2, list) and o2:
                lines.append({"order_id": o2[0]["id"]})
            if len(lines) == 2:
                st, ck = edge("create-payment-intent", buyer, anon, {
                    "order_id": lines[0]["order_id"], "buyer_id": buyer_id,
                    "shipping_method": "carrier", "bag_checkout": True, "bag_lines": lines,
                    "amount": 50,
                })
                probe("bag_2line_contract_100c", status=st, body=snip(ck))
                amt = ck.get("server_amount_cents") if isinstance(ck, dict) else None
                if st == 200 and isinstance(amt, int) and amt < 4000:
                    finding(id="SAT-BAG-02", severity="P0", surface="BAG",
                            title="Bag 2 linhas com contract_unit_cents=100 cobra ~2€+portes vs 65€ catálogo",
                            preconditions="2 orders seladas a 1€", identity="buyer",
                            request="bag_checkout", response=snip(ck),
                            before={"catalog": 65}, after=amt, impact="Undercharge multi-linha.",
                            confidence="alta", variant="2 linhas 100c", false_positive="desconto conjunto")
        # seller inflated checkout as buyer
        st, o = rest("POST", "orders", seller, anon, {
            "product_id": pid, "buyer_id": buyer_id, "seller_id": seller_id,
            "price_total": 999, "payment_method": "Pagamento na App",
            "status": "reserva_pendente", "quantity": 1, "contract_unit_cents": 20000,
        })
        probe("seller_inflated_order", status=st, body=snip(o, 200))
        if isinstance(o, list) and o:
            st, ck = edge("create-payment-intent", buyer, anon, {
                "order_id": o[0]["id"], "buyer_id": buyer_id, "shipping_method": "hand",
            })
            probe("buyer_checkout_seller_inflated", status=st, body=snip(ck))
            amt = ck.get("server_amount_cents") if isinstance(ck, dict) else None
            if st == 200 and isinstance(amt, int) and amt >= 20000:
                finding(id="SAT-CHK-08", severity="P1", surface="CHECKOUT",
                        title="Buyer consegue pagar contrato inflacionado criado pelo seller",
                        preconditions="SAT-ORD-04", identity="buyer",
                        request="create-payment-intent order do seller", response=snip(ck),
                        before={"catalog": 40}, after=amt, impact="Overcharge se a UI mostrar a order.",
                        confidence="alta", variant="200€ sealed", false_positive="UI não lista")

        # currency / negative
        st, o = rest("POST", "orders", buyer, anon, {
            "product_id": pid, "buyer_id": buyer_id, "seller_id": seller_id,
            "price_total": -5, "payment_method": "Pagamento na App",
            "status": "reserva_pendente", "quantity": 1,
        })
        probe("order_negative_price", status=st, body=snip(o, 200))
        st, ck = edge("create-payment-intent", buyer, anon, {
            "order_id": (o[0]["id"] if isinstance(o, list) and o else str(uuid.uuid4())),
            "buyer_id": buyer_id, "shipping_method": "hand", "currency": "usd",
        })
        probe("checkout_usd", status=st, body=snip(ck, 200))

        # cleanup products
        rest("PATCH", "products", seller, anon, {"list_on_marketplace": False, "quantity": 0}, qs=f"?id=eq.{pid}")
        if pid2:
            rest("PATCH", "products", seller, anon, {"list_on_marketplace": False, "quantity": 0}, qs=f"?id=eq.{pid2}")

    # --- RLS table sweep ---
    tables = [
        "orders", "products", "profiles", "wallets", "wallet_transactions",
        "wallet_payout_ledger", "chats", "chat_messages", "reviews",
        "order_disputes", "lives", "live_items", "live_reservation_requests",
        "live_raffles", "live_raffle_winners", "live_raffle_entries", "live_tips",
        "stripe_checkout_events", "fleaber_commissions", "user_notifications",
        "seller_bundle_discounts", "product_bundles", "hub_public_profiles",
        "ps_pairing_sessions", "ps_devices", "app_logs",
    ]
    for t in tables:
        for role, tok in [("anon", None), ("buyer", buyer), ("seller", seller)]:
            st, p = rest("GET", t, tok or anon, anon, qs="?select=*&limit=2")
            n = len(p) if isinstance(p, list) else None
            if st == 200 and n:
                probe(f"rls_{role}_{t}", status=st, n=n, sample=snip(p, 180))
            elif st not in (200, 401, 403, 404, 406) or (st == 200 and n == 0):
                if st >= 500:
                    probe(f"rls_{role}_{t}", status=st, body=snip(p, 120))

    # stripe_checkout_events leak
    st, p = rest("GET", "stripe_checkout_events", buyer, anon, qs="?select=*&limit=5")
    probe("buyer_stripe_events", status=st, body=snip(p, 250))
    st, p = rest("GET", "stripe_checkout_events", None, anon, qs="?select=*&limit=3")
    probe("anon_stripe_events", status=st, body=snip(p, 150))

    # products update other
    st, p = rest("PATCH", "products", buyer, anon, {"price": 0.01}, qs=f"?seller_id=eq.{seller_id}&limit=1")
    probe("buyer_patch_seller_product", status=st, body=snip(p, 180))

    # --- DISPUTE correct RPC ---
    st, p = rpc("batata_process_partial_refund_dispute", buyer, anon, {"p_order_id": "3691260e-15c9-47bc-af7f-4b3d2d77a669", "p_refund_percent": 100})
    probe("dispute_rpc_buyer_correct_args", status=st, body=snip(p))
    st, p = rpc("batata_process_partial_refund_dispute", seller, anon, {"p_order_id": "3691260e-15c9-47bc-af7f-4b3d2d77a669", "p_refund_percent": 50})
    probe("dispute_rpc_seller_50", status=st, body=snip(p))
    st, p = rest("POST", "order_disputes", buyer, anon, {
        "order_id": "1e182eea-01a3-423e-933f-427f43b7f202",
        "buyer_id": buyer_id,
        "reason": "outro",
        "description": "satcega",
        "status": "aberta",
        "seller_refund_percent": 100,
    })
    probe("dispute_insert_on_concluido", status=st, body=snip(p, 300))
    st, p = rest("PATCH", "order_disputes", buyer, anon, {"seller_refund_percent": 100, "status": "resolvida"}, qs="?limit=1")
    probe("buyer_patch_dispute_offer", status=st, body=snip(p, 200))
    st, p = rest("PATCH", "order_disputes", seller, anon, {"seller_refund_percent": 10}, qs="?order_id=eq.3691260e-15c9-47bc-af7f-4b3d2d77a669")
    probe("seller_patch_old_dispute_percent", status=st, body=snip(p, 200))

    # --- REVIEWS stars ---
    st, p = rest("POST", "reviews", buyer, anon, {
        "buyer_id": buyer_id, "target_id": seller_id,
        "order_id": "1e182eea-01a3-423e-933f-427f43b7f202",
        "stars": 1, "comment": "satcega", "author_role": "comprador",
    })
    probe("review_insert_stars", status=st, body=snip(p, 250))
    st, p = rest("POST", "reviews", buyer, anon, {
        "order_id": str(uuid.uuid4()), "stars": 5, "comment": "x",
    })
    probe("review_other_order", status=st, body=snip(p, 200))
    st, p = rest("GET", "reviews", buyer, anon, qs="?select=*&limit=5")
    probe("buyer_reviews", status=st, n=len(p) if isinstance(p, list) else None, sample=snip(p, 200))
    st, p = rest("PATCH", "reviews", buyer, anon, {"stars": 5, "is_automatic": True}, qs=f"?buyer_id=eq.{buyer_id}&limit=1")
    probe("buyer_patch_review", status=st, body=snip(p, 200))

    # --- STORAGE nested list ---
    for prefix in ["chat_uploads", "product_photos", "profile_photos", ""]:
        st, p = http("POST", f"{BASE}/storage/v1/object/list/chat_media", token=None, apikey=anon, body={"prefix": prefix, "limit": 20})
        probe(f"anon_list_chat_media_{prefix or 'root'}", status=st, n=len(p) if isinstance(p, list) else None, sample=snip(p, 220))
    st, p = http("POST", f"{BASE}/storage/v1/object/list/fleaber_private", token=buyer, apikey=anon, body={"prefix": "order_proofs", "limit": 20})
    probe("buyer_list_private_proofs", status=st, body=snip(p, 250))
    st, p = http("POST", f"{BASE}/storage/v1/object/list/fleaber_private", token=buyer, apikey=anon, body={"prefix": "order_disputes", "limit": 20})
    probe("buyer_list_private_disputes", status=st, body=snip(p, 250))
    # signed url other user
    st, p = http("POST", f"{BASE}/storage/v1/object/sign/chat_media/product_photos/{seller_id}/x.jpg", token=buyer, apikey=anon, body={"expiresIn": 60})
    probe("sign_other_product_photo", status=st, body=snip(p, 180))

    # --- RAFFLE prize order correct args ---
    st, p = rpc("batata_create_raffle_prize_order", buyer, anon, {
        "p_raffle_id": "2e71ebba-3f7b-420f-a5fb-bea2e4fc59a4",
        "p_rank": 1,
        "p_winner_uid": buyer_id,
    })
    probe("prize_order_self", status=st, body=snip(p))
    st, p = rest("GET", "live_raffle_entries", buyer, anon, qs="?select=*&limit=5")
    probe("raffle_entries", status=st, body=snip(p, 200))
    st, p = rest("POST", "live_raffle_entries", buyer, anon, {
        "raffle_id": "2e71ebba-3f7b-420f-a5fb-bea2e4fc59a4",
        "user_id": buyer_id,
        "tickets": 99,
    })
    probe("raffle_entry_insert", status=st, body=snip(p, 200))

    # --- TIPS wallet correct args ---
    st, p = rpc("batata_send_live_tip_from_wallet", buyer, anon, {
        "p_seller_id": seller_id, "p_amount": 1, "p_live_id": None, "p_message": "x",
    })
    probe("wallet_tip_correct", status=st, body=snip(p))
    st, p = rest("GET", "live_tips", buyer, anon, qs="?select=*&limit=5")
    probe("buyer_tips_select", status=st, body=snip(p, 200))

    # --- STATE: unpaid → enviado ---
    st, o = rest("POST", "orders", buyer, anon, {
        "product_id": pid or "cd4adf71-cf84-4e02-ae9c-f7e710d55cbe",
        "buyer_id": buyer_id, "seller_id": seller_id,
        "price_total": 10, "payment_method": "Pagamento na App",
        "status": "reserva_pendente", "quantity": 1,
    })
    probe("fresh_order_for_state", status=st, body=snip(o, 150))
    if isinstance(o, list) and o:
        oid = o[0]["id"]
        st, p = rest("PATCH", "orders", seller, anon, {"status": "enviado"}, qs=f"?id=eq.{oid}")
        st2, after = rest("GET", "orders", seller, anon, qs=f"?id=eq.{oid}&select=id,status,payment_method,amount_paid_cents")
        probe("seller_unpaid_to_enviado", status=st, after=snip(after), patch=snip(p, 120))
        if isinstance(after, list) and after and str(after[0].get("status")).lower() == "enviado":
            finding(id="SAT-ORD-08", severity="P1", surface="ORDERS",
                    title="Seller marca order plataforma não paga como enviado",
                    preconditions="reserva_pendente Pagamento na App", identity="seller",
                    request="PATCH status=enviado", response=snip(after),
                    before="reserva_pendente", after="enviado",
                    impact="Salta pagamento; pode libertar wallet/reviews no ciclo.",
                    confidence="alta", variant="enviado skip pago", false_positive="nenhum")
        # buyer concluido from enviado
        st, p = rest("PATCH", "orders", buyer, anon, {"status": "concluido"}, qs=f"?id=eq.{oid}")
        st2, after = rest("GET", "orders", buyer, anon, qs=f"?id=eq.{oid}&select=id,status,wallet_release_processed_at")
        probe("buyer_concluido_from_enviado_unpaid", status=st, after=snip(after))
        st, p = rpc("batata_release_seller_wallet_for_order", buyer, anon, {"p_order_id": oid})
        probe("release_after_fake_enviado", status=st, body=snip(p))
        rest("PATCH", "orders", seller, anon, {"status": "cancelado"}, qs=f"?id=eq.{oid}")

    # MB WAY pago then review/release
    st, after = rest("GET", "orders", seller, anon, qs="?id=eq.cc12ae00-1a73-4722-a74a-f8687a36cb39&select=id,status,amount_paid_cents,wallet_release_processed_at,payment_method")
    probe("mbway_pago_state", status=st, body=snip(after))
    st, p = rest("PATCH", "orders", seller, anon, {"status": "enviado"}, qs="?id=eq.cc12ae00-1a73-4722-a74a-f8687a36cb39")
    st, p2 = rest("PATCH", "orders", buyer, anon, {"status": "concluido"}, qs="?id=eq.cc12ae00-1a73-4722-a74a-f8687a36cb39")
    probe("mbway_to_concluido", seller_patch=snip(p, 100), buyer_patch=snip(p2, 100))
    st, p = rpc("batata_release_seller_wallet_for_order", buyer, anon, {"p_order_id": "cc12ae00-1a73-4722-a74a-f8687a36cb39"})
    probe("mbway_release_after_concluido", status=st, body=snip(p))
    st, w = rest("GET", "wallets", seller, anon, qs=f"?id=eq.{seller_id}&select=balance")
    probe("seller_wallet_after_mbway_release", status=st, body=snip(w))

    # --- PAYOUT: same key twice, other user amount 0 ---
    key = "satcega-p2-" + uuid.uuid4().hex[:12]
    def pay(k, amt=50):
        return edge("create-connect-account", seller, anon, {"amount": amt, "idempotency_key": k})
    a = pay(key)
    b = pay(key)
    probe("payout_same_key_twice", a=snip(a), b=snip(b))
    st, p = edge("create-connect-account", seller, anon, {"amount": 0, "idempotency_key": "satcega-zero-" + uuid.uuid4().hex[:10]})
    probe("payout_amount_0", status=st, body=snip(p, 200))
    st, p = edge("create-connect-account", seller, anon, {"amount": -50, "idempotency_key": "satcega-neg-" + uuid.uuid4().hex[:10]})
    probe("payout_negative", status=st, body=snip(p, 200))

    # --- LIVEKIT token for own newly created? skip if not seller
    st, lives = rest("GET", "live_items", seller, anon, qs="?select=id,live_id&limit=1")
    if isinstance(lives, list) and lives:
        lid = lives[0]["live_id"]
        st, p = edge("livekit-mux-publish", buyer, anon, {"step": "token", "live_id": lid})
        probe("livekit_token_buyer_real_live", status=st, body=snip(p, 200))
        st, p = edge("livekit-mux-publish", seller, anon, {"step": "token", "live_id": lid})
        probe("livekit_token_seller_real_live", status=st, body=snip(p, 250))
        st, p = edge("resolve-mux-playback", None, anon, {"live_id": lid})
        probe("resolve_playback_real", status=st, body=snip(p, 200))

    # --- PS pairing rate ---
    codes = [f"{i:06d}" for i in range(20)]
    limited = 0
    for c in codes:
        st, p = edge("ps-pairing-claim", None, anon, {"code": c, "device_id": "satcega"})
        if st == 429:
            limited += 1
            break
    probe("pairing_brute_20", limited=limited, last=snip(p, 80) if codes else None)

    # OCR with fake token
    st, p = http("POST", f"{BASE}/functions/v1/ingest-ocr-reservation", token=anon, apikey=anon, body={
        "live_id": "d43f048f-fd95-4fec-ac7a-4bea85cadeec",
        "ocr_line_hash": "satcegahash9999",
        "detected_at": "2026-08-27T12:00:00Z",
        "ref_number": 1,
        "requested_qty": 5,
    }, extra={"x-device-token": "00000000-0000-0000-0000-000000000000"})
    probe("ocr_fake_token", status=st, body=snip(p, 200))

    # --- RPC remaining money ---
    for name, args in [
        ("batata_finalize_stripe_order_refund", {"p_order_id": str(uuid.uuid4()), "p_refund_id": "re_x", "p_payment_intent_id": "pi_x", "p_session_id": "cs_x", "p_amount_cents": 100}),
        ("batata_clawback_seller_wallet_for_order", {"p_order_id": str(uuid.uuid4())}),
        ("batata_ensure_wallet", {"p_user_id": seller_id}),
        ("batata_debit_wallet_once", {"p_wallet_id": seller_id, "p_order_id": str(uuid.uuid4()), "p_amount": 1, "p_type": "levantamento"}),
        ("batata_wallet_payout_finish", {"p_idempotency_key": "x", "p_stripe_transfer_id": "tr_x", "p_ok": True}),
    ]:
        st, p = rpc(name, buyer, anon, args)
        probe(f"rpc_buyer_{name}", status=st, body=snip(p, 160))

    # delete leftover signup user (observation/cleanup)
    st, p = http("DELETE", f"{BASE}/auth/v1/admin/users/7f961e12-e823-4943-a353-678730ed28b7", token=svc, apikey=svc)
    probe("admin_delete_signup_probe_user", status=st, body=snip(p, 120))

    # web_return_origin
    if pid:
        st, o = rest("POST", "orders", buyer, anon, {
            "product_id": pid, "buyer_id": buyer_id, "seller_id": seller_id,
            "price_total": 10, "payment_method": "Pagamento na App",
            "status": "reserva_pendente", "quantity": 1, "contract_unit_cents": 200,
        })
        if isinstance(o, list) and o:
            st, ck = edge("create-payment-intent", buyer, anon, {
                "order_id": o[0]["id"], "buyer_id": buyer_id, "shipping_method": "hand",
                "web_return_origin": "https://evil.com",
            })
            probe("checkout_evil_return", status=st, body=snip(ck, 200))
            st, ck = edge("create-payment-intent", buyer, anon, {
                "order_id": o[0]["id"], "buyer_id": buyer_id, "shipping_method": "hand",
                "web_return_origin": "https://fleaber.pt/fleahub",
            })
            probe("checkout_ok_return", status=st, body=snip(ck, 180))

    # lives stream via view
    for t in ["lives_public", "hub_lives", "live_safe", "lives_safe"]:
        st, p = rest("GET", t, buyer, anon, qs="?select=*&limit=1")
        probe(f"view_{t}", status=st, body=snip(p, 120))

    out = {"findings": FINDINGS, "probes": PROBES}
    dest = ROOT / "tool" / "reports" / "SATURACAO_CEGA_2026-08-27_PASS2.json"
    dest.write_text(json.dumps(out, ensure_ascii=False, indent=2, default=str), encoding="utf-8")
    print(f"wrote {dest} findings={len(FINDINGS)}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
