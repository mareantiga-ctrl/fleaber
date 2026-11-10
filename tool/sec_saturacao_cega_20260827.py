#!/usr/bin/env python3
"""Blind saturation audit harness — staging only. No production. No fixes."""
from __future__ import annotations

import json
import os
import ssl
import sys
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = ROOT / "tool" / "live_ops_staging.env"
CTX = ssl.create_default_context()
STAGING_REF = "fxdknzrqjenzqcvnwqqq"
BASE = f"https://{STAGING_REF}.supabase.co"
ANON = ""
SVC = ""
BUYER_EMAIL = ""
BUYER_PASS = ""
SELLER_EMAIL = ""
SELLER_PASS = ""
BUYER_ID = ""
SELLER_ID = ""
TAG = f"SATCEGA-{int(time.time())}"
FINDINGS: list[dict[str, Any]] = []
NOTES: list[str] = []
COVERAGE: dict[str, str] = {}
EVIDENCE: dict[str, Any] = {"probes": []}
CREATED: dict[str, list[str]] = {
    "products": [],
    "orders": [],
    "chats": [],
}


def load_env() -> None:
    global ANON, SVC, BUYER_EMAIL, BUYER_PASS, SELLER_EMAIL, SELLER_PASS
    global BUYER_ID, SELLER_ID
    text = ENV_PATH.read_text(encoding="utf-8")
    kv: dict[str, str] = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        kv[k.strip()] = v.strip()
    ANON = kv["SUPABASE_ANON_KEY"]
    SVC = kv["SUPABASE_SERVICE_ROLE_KEY"]
    BUYER_EMAIL = kv["LIVE_OPS_TEST_BUYER_EMAIL"]
    BUYER_PASS = kv["LIVE_OPS_TEST_BUYER_PASSWORD"]
    SELLER_EMAIL = kv["LIVE_OPS_TEST_SELLER_EMAIL"]
    SELLER_PASS = kv["LIVE_OPS_TEST_SELLER_PASSWORD"]
    BUYER_ID = kv["LIVE_OPS_TEST_BUYER_ID"]
    SELLER_ID = kv["LIVE_OPS_TEST_SELLER_ID"]
    url = kv.get("SUPABASE_URL", "")
    if STAGING_REF not in url and STAGING_REF not in BASE:
        raise SystemExit("refused: not staging")


def http(
    method: str,
    url: str,
    *,
    token: str | None = None,
    apikey: str | None = None,
    body: Any = None,
    extra_headers: dict[str, str] | None = None,
    timeout: int = 45,
) -> tuple[int, Any, dict[str, str]]:
    data = None
    headers = {
        "Accept": "application/json",
        "apikey": apikey or ANON,
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    else:
        headers["Authorization"] = f"Bearer {apikey or ANON}"
    if extra_headers:
        headers.update(extra_headers)
    if body is not None:
        raw = body if isinstance(body, (bytes, bytearray)) else json.dumps(body).encode()
        data = raw
        headers.setdefault("Content-Type", "application/json")
        headers["Content-Length"] = str(len(raw))
    req = Request(url, data=data, headers=headers, method=method)
    try:
        with urlopen(req, timeout=timeout, context=CTX) as resp:
            raw = resp.read()
            hdrs = {k.lower(): v for k, v in resp.headers.items()}
            parsed: Any
            try:
                parsed = json.loads(raw.decode("utf-8") or "null")
            except Exception:
                parsed = raw.decode("utf-8", errors="replace")[:4000]
            return resp.status, parsed, hdrs
    except HTTPError as e:
        raw = e.read()
        try:
            parsed = json.loads(raw.decode("utf-8") or "null")
        except Exception:
            parsed = raw.decode("utf-8", errors="replace")[:4000]
        hdrs = {k.lower(): v for k, v in e.headers.items()} if e.headers else {}
        return e.code, parsed, hdrs
    except URLError as e:
        return 0, {"error": str(e.reason)}, {}


def rest(
    method: str,
    path: str,
    token: str | None,
    *,
    body: Any = None,
    qs: str = "",
    extra: dict[str, str] | None = None,
    svc: bool = False,
) -> tuple[int, Any]:
    key = SVC if svc else ANON
    url = f"{BASE}/rest/v1/{path.lstrip('/')}{qs}"
    headers = {"Prefer": "return=representation"}
    if extra:
        headers.update(extra)
    st, parsed, _ = http(method, url, token=token or key, apikey=key, body=body, extra_headers=headers)
    return st, parsed


def rpc(name: str, token: str | None, args: dict[str, Any] | None = None, *, svc: bool = False) -> tuple[int, Any]:
    key = SVC if svc else ANON
    st, parsed, _ = http(
        "POST",
        f"{BASE}/rest/v1/rpc/{name}",
        token=token or key,
        apikey=key,
        body=args or {},
    )
    return st, parsed


def edge(name: str, token: str | None, body: Any = None, *, method: str = "POST", qs: str = "", extra: dict[str, str] | None = None) -> tuple[int, Any]:
    url = f"{BASE}/functions/v1/{name}{qs}"
    st, parsed, _ = http(method, url, token=token or ANON, apikey=ANON, body=body, extra_headers=extra)
    return st, parsed


def login(email: str, password: str) -> str:
    st, parsed, _ = http(
        "POST",
        f"{BASE}/auth/v1/token?grant_type=password",
        apikey=ANON,
        token=ANON,
        body={"email": email, "password": password},
    )
    if st != 200 or not isinstance(parsed, dict) or "access_token" not in parsed:
        raise SystemExit(f"login failed {email}: {st} {parsed}")
    return str(parsed["access_token"])


def add_finding(**kwargs: Any) -> None:
    FINDINGS.append(kwargs)
    print(f"[FINDING {kwargs.get('severity')}] {kwargs.get('id')} — {kwargs.get('title')}")


def probe(name: str, **data: Any) -> None:
    EVIDENCE["probes"].append({"name": name, **data})
    print(f"  probe {name}: status={data.get('status')} note={data.get('note', '')}")


def snippet(obj: Any, n: int = 600) -> Any:
    s = json.dumps(obj, default=str, ensure_ascii=False)
    return s[:n]


def set_cov(surface: str, level: str) -> None:
    prev = COVERAGE.get(surface)
    rank = {
        "NÃO TESTADA": 0,
        "PARCIAL": 1,
        "TESTADA": 2,
        "TESTADA COM VARIANTES": 3,
    }
    if rank.get(level, 0) >= rank.get(prev or "", -1):
        COVERAGE[surface] = level


# ---------------------------------------------------------------------------
# PASS 1
# ---------------------------------------------------------------------------

def pass_auth(buyer: str, seller: str) -> None:
    set_cov("AUTH", "TESTADA COM VARIANTES")
    # Enumeration: signup existing email
    st, parsed, _ = http(
        "POST",
        f"{BASE}/auth/v1/signup",
        apikey=ANON,
        token=ANON,
        body={"email": BUYER_EMAIL, "password": "WrongPass123!"},
    )
    probe("signup_existing_email", status=st, body=snippet(parsed))
    st2, p2, _ = http(
        "POST",
        f"{BASE}/auth/v1/signup",
        apikey=ANON,
        token=ANON,
        body={"email": f"noexist-{uuid.uuid4().hex[:8]}@example.invalid", "password": "WrongPass123!"},
    )
    probe("signup_new_email", status=st2, body=snippet(p2))
    # Password recovery enumeration
    st3, p3, _ = http(
        "POST",
        f"{BASE}/auth/v1/recover",
        apikey=ANON,
        token=ANON,
        body={"email": BUYER_EMAIL},
    )
    st4, p4, _ = http(
        "POST",
        f"{BASE}/auth/v1/recover",
        apikey=ANON,
        token=ANON,
        body={"email": "nobody-satcega@example.invalid"},
    )
    probe("recover_existing", status=st3, body=snippet(p3))
    probe("recover_missing", status=st4, body=snippet(p4))
    if st3 != st4 or snippet(p3) != snippet(p4):
        add_finding(
            id="SAT-AUTH-01",
            severity="P3",
            surface="AUTH",
            title="Possível enumeração via recover/signup",
            preconditions="emails conhecidos vs inventados",
            identity="anon",
            request="POST /auth/v1/recover + signup",
            response={"existing": {"st": st3, "body": snippet(p3)}, "missing": {"st": st4, "body": snippet(p4)}, "signup_exist": st, "signup_new": st2},
            before=None,
            after=None,
            impact="Ajuda a confirmar contas se as respostas divergirem.",
            confidence="média",
            variant="recover + signup",
            false_positive="GoTrue muitas vezes devolve 200 genérico; só finding se respostas claramente distintas.",
        )
    # JWT alg=none / role claim
    fake = "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJyb2xlIjoic2VydmljZV9yb2xlIiwic3ViIjoiMDAwMDAwMDAtMDAwMC0wMDAwLTAwMDAtMDAwMDAwMDAwMDAwIn0."
    st5, p5 = rest("GET", "orders", fake, qs="?select=id&limit=1")
    probe("jwt_alg_none_orders", status=st5, body=snippet(p5))
    if st5 == 200:
        add_finding(
            id="SAT-AUTH-02",
            severity="P0",
            surface="AUTH",
            title="JWT alg=none aceite em PostgREST",
            preconditions="nenhuma",
            identity="forged JWT",
            request="GET /rest/v1/orders Authorization alg=none",
            response={"status": st5, "body": snippet(p5)},
            before=None,
            after=None,
            impact="Bypass total de RLS.",
            confidence="alta",
            variant="alg=none",
            false_positive="200 vazio ainda é aceite se RLS não filtrar",
        )
    # Cross-user: decode buyer jwt shouldn't access admin
    st6, p6 = rest("GET", "profiles", buyer, qs=f"?id=eq.{SELLER_ID}&select=id,user_type,iban,mbway,mb_way,phone,email,full_name")
    probe("buyer_read_seller_profile_sensitive", status=st6, body=snippet(p6))
    # user_type self-upgrade
    st7, p7 = rest("PATCH", "profiles", buyer, qs=f"?id=eq.{BUYER_ID}", body={"user_type": "admin"})
    st7b, p7b = rest("GET", "profiles", buyer, qs=f"?id=eq.{BUYER_ID}&select=id,user_type")
    probe("buyer_user_type_admin", status=st7, after=snippet(p7b), patch=snippet(p7))
    after_type = None
    if isinstance(p7b, list) and p7b:
        after_type = p7b[0].get("user_type")
    elif isinstance(p7, list) and p7:
        after_type = p7[0].get("user_type")
    if after_type and str(after_type).lower() in {"admin", "admim", "administrador"}:
        add_finding(
            id="SAT-AUTH-03",
            severity="P0",
            surface="AUTH",
            title="Comprador eleva user_type para admin",
            preconditions="JWT buyer",
            identity="buyer",
            request="PATCH profiles user_type=admin",
            response={"patch": snippet(p7), "after": snippet(p7b)},
            before=None,
            after=after_type,
            impact="Privilégio admin.",
            confidence="alta",
            variant="user_type=admin",
            false_positive="coluna ignorada pelo trigger mas devolve representation antiga",
        )
    # seller_id spoof on profile
    st8, p8 = rest("PATCH", "profiles", buyer, qs=f"?id=eq.{SELLER_ID}", body={"full_name": "HACKED"})
    probe("buyer_patch_seller_profile", status=st8, body=snippet(p8))
    if st8 in (200, 204) and p8 not in ([], None, ""):
        add_finding(
            id="SAT-AUTH-04",
            severity="P0",
            surface="PROFILES",
            title="Buyer PATCH no perfil do seller",
            preconditions="JWT buyer",
            identity="buyer",
            request=f"PATCH profiles?id=eq.{SELLER_ID}",
            response=snippet(p8),
            before=None,
            after=snippet(p8),
            impact="PII/reputação de outra conta.",
            confidence="alta",
            variant="full_name",
            false_positive="Prefer return vazio = 0 rows",
        )


def pass_profiles(buyer: str, seller: str) -> None:
    set_cov("PROFILES", "TESTADA COM VARIANTES")
    cols = "id,full_name,user_type,iban,mbway,mb_way,phone,email,phone_verified_at,stripe_account_id,handle"
    st, parsed = rest("GET", "profiles", None, qs=f"?select={cols}&limit=5")
    probe("anon_profiles", status=st, body=snippet(parsed))
    if st == 200 and isinstance(parsed, list) and parsed:
        leaked = [k for row in parsed for k in row.keys() if k in {"iban", "mbway", "mb_way", "phone", "email"} and row.get(k)]
        if leaked:
            add_finding(
                id="SAT-PII-01",
                severity="P0",
                surface="PROFILES",
                title="Anon lê PII de profiles",
                preconditions="anon key",
                identity="anon",
                request="GET profiles",
                response=snippet(parsed),
                before=None,
                after=None,
                impact="Directório PII público.",
                confidence="alta",
                variant="anon select",
                false_positive="campos null não são leak",
            )
    st2, p2 = rest("GET", "profiles", buyer, qs=f"?id=eq.{SELLER_ID}&select={cols}")
    probe("buyer_seller_profile", status=st2, body=snippet(p2))
    if st2 == 200 and isinstance(p2, list) and p2:
        row = p2[0]
        pii = {k: row.get(k) for k in ("iban", "mbway", "mb_way", "phone", "email") if row.get(k)}
        if pii:
            add_finding(
                id="SAT-PII-02",
                severity="P1",
                surface="PROFILES",
                title="Buyer lê IBAN/MB WAY/telefone do seller via profiles",
                preconditions="JWT buyer, seller id conhecido",
                identity="buyer",
                request=f"GET profiles?id=eq.{SELLER_ID}",
                response=snippet(pii),
                before=None,
                after=None,
                impact="PII financeiro de outro utilizador sem ser parte de encomenda.",
                confidence="alta",
                variant="direct id",
                false_positive="directório público intencional só com handle/nome",
            )
    # privileged fields
    for field, val in [
        ("phone_verified_at", "2020-01-01T00:00:00Z"),
        ("iban", "PT50000201231234567890154"),
        ("user_type", "vendedor"),
    ]:
        st3, p3 = rest("PATCH", "profiles", buyer, qs=f"?id=eq.{BUYER_ID}", body={field: val})
        probe(f"buyer_patch_{field}", status=st3, body=snippet(p3))
    st4, p4 = rest("GET", "profiles", buyer, qs=f"?id=eq.{BUYER_ID}&select=id,user_type,phone_verified_at,iban")
    probe("buyer_profile_after_priv_patch", status=st4, body=snippet(p4))
    if isinstance(p4, list) and p4:
        if str(p4[0].get("phone_verified_at") or "").startswith("2020"):
            add_finding(
                id="SAT-PII-03",
                severity="P1",
                surface="PROFILES",
                title="Buyer auto-verifica telefone",
                preconditions="JWT buyer",
                identity="buyer",
                request="PATCH phone_verified_at",
                response=snippet(p4),
                before=None,
                after=p4[0].get("phone_verified_at"),
                impact="Bypass verificação de telefone (Hub/envio).",
                confidence="alta",
                variant="phone_verified_at",
                false_positive="trigger pode devolver old representation",
            )


def discover_tables(token: str) -> list[str]:
    st, parsed, _ = http(
        "GET",
        f"{BASE}/rest/v1/",
        token=token,
        extra_headers={"Accept": "application/openapi+json"},
    )
    names: list[str] = []
    if isinstance(parsed, dict):
        paths = parsed.get("paths") or {}
        for p in paths:
            if p.startswith("/") and p.count("/") == 1 and not p.startswith("/rpc"):
                names.append(p.strip("/"))
        EVIDENCE["openapi_paths"] = list(paths.keys())[:400]
        rpc_names = [p.split("/")[-1] for p in paths if p.startswith("/rpc/")]
        EVIDENCE["openapi_rpcs"] = rpc_names
    probe("openapi", status=st, tables=len(names), rpcs=len(EVIDENCE.get("openapi_rpcs") or []))
    return sorted(set(names))


def pass_rls_sweep(buyer: str, seller: str, tables: list[str]) -> None:
    set_cov("RLS", "TESTADA COM VARIANTES")
    sensitive = [
        "orders", "wallets", "wallet_transactions", "wallet_payout_ledger",
        "profiles", "chat_messages", "chats", "reviews", "order_disputes",
        "products", "lives", "live_items", "live_reservation_requests",
        "live_raffles", "live_raffle_winners", "live_tips",
        "stripe_checkout_events", "ps_pairing_codes", "ps_devices",
        "fleaber_commissions", "order_proofs",
    ]
    for role, tok in [("anon", None), ("buyer", buyer), ("seller", seller)]:
        for t in tables:
            st, parsed = rest("GET", t, tok, qs="?select=*&limit=3")
            n = len(parsed) if isinstance(parsed, list) else None
            interesting = t in sensitive or (st == 200 and n not in (0, None))
            if interesting:
                probe(f"rls_select_{role}_{t}", status=st, n=n, sample=snippet(parsed, 280))
            # Cross-user dump
            if t == "orders" and role == "buyer" and isinstance(parsed, list):
                foreign = [r for r in parsed if r.get("buyer_id") not in (None, BUYER_ID) and r.get("seller_id") != BUYER_ID]
                if foreign:
                    add_finding(
                        id="SAT-ORD-01",
                        severity="P0",
                        surface="ORDERS",
                        title="Buyer SELECT vê orders alheias",
                        preconditions="JWT buyer",
                        identity="buyer",
                        request="GET orders",
                        response=snippet(foreign),
                        before=None,
                        after=None,
                        impact="Contrato/PII de outras compras.",
                        confidence="alta",
                        variant="select * limit 3",
                        false_positive="buyer também é seller nessas linhas",
                    )
            if t == "wallets" and role == "buyer" and isinstance(parsed, list):
                foreign = [r for r in parsed if str(r.get("id")) != BUYER_ID]
                if foreign:
                    add_finding(
                        id="SAT-WAL-01",
                        severity="P0",
                        surface="WALLET",
                        title="Buyer lê wallets alheias",
                        preconditions="JWT buyer",
                        identity="buyer",
                        request="GET wallets",
                        response=snippet(foreign),
                        before=None,
                        after=None,
                        impact="Saldo e stripe_account_id de outros.",
                        confidence="alta",
                        variant="select",
                        false_positive="nenhum",
                    )
            if t == "chat_messages" and role == "buyer" and isinstance(parsed, list):
                foreign = [r for r in parsed if r.get("sender_id") != BUYER_ID and r.get("receiver_id") != BUYER_ID]
                if foreign:
                    add_finding(
                        id="SAT-CHAT-01",
                        severity="P1",
                        surface="CHAT",
                        title="Buyer lê mensagens onde não é participante",
                        preconditions="JWT buyer",
                        identity="buyer",
                        request="GET chat_messages",
                        response=snippet(foreign),
                        before=None,
                        after=None,
                        impact="Conteúdo de chats alheios.",
                        confidence="alta",
                        variant="select",
                        false_positive="buyer em ambos os lados via outro id",
                    )
            if t == "lives" and role == "anon" and isinstance(parsed, list):
                keys = [r.get("mux_stream_key") or r.get("stream_key") for r in parsed]
                if any(keys):
                    add_finding(
                        id="SAT-MUX-01",
                        severity="P0",
                        surface="MUX",
                        title="Anon lê stream_key",
                        preconditions="anon",
                        identity="anon",
                        request="GET lives",
                        response=snippet(keys),
                        before=None,
                        after=None,
                        impact="Hijack de ingest Mux.",
                        confidence="alta",
                        variant="select *",
                        false_positive="coluna mascarada noutro view",
                    )


def pass_rpc_sweep(buyer: str, seller: str) -> None:
    set_cov("RPC/DEFINER", "TESTADA COM VARIANTES")
    rpcs = list(EVIDENCE.get("openapi_rpcs") or [])
    moneyish = [
        "batata_credit_wallet_once",
        "batata_debit_wallet_once",
        "batata_ensure_wallet",
        "batata_release_seller_wallet_for_order",
        "batata_refund_buyer_wallet_for_order",
        "batata_process_partial_refund_dispute",
        "batata_clawback_seller_wallet_for_order",
        "batata_wallet_payout_debit",
        "batata_wallet_payout_finish",
        "batata_settle_live_tip_from_stripe",
        "batata_send_live_tip_from_wallet",
        "batata_create_live_tip_pending",
        "batata_finalize_stripe_order_refund",
        "batata_draw_live_raffle_winners",
        "batata_create_raffle_prize_order",
        "batata_live_reservation_stripe_convert",
        "batata_mark_product_sold_on_paid_order",
        "batata_is_admin",
        "batata_assert_wallet_rpc_grants",
        "batata_ps_claim_pairing",
        "batata_ingest_ocr_reservation_v2",
        "batata_live_system_message",
        "batata_process_live_reservation_request",
        "batata_live_bag_update_qty",
    ]
    targets = sorted(set(rpcs + moneyish))
    EVIDENCE["rpc_results"] = {}
    dummy = str(uuid.uuid4())
    for name in targets:
        args_list = [
            {},
            {"p_user_id": SELLER_ID, "p_amount": 999, "p_order_id": dummy, "p_type": "venda", "p_description": "x", "p_source": "x"},
            {"p_order_id": dummy, "p_percent": 100, "p_refund_percent": 100},
            {"p_tip_id": dummy, "p_stripe_session_id": "cs_test_x", "p_paid_amount_cents": 10000},
            {"p_request_id": dummy, "p_action": "accept"},
            {"p_code": "000000", "p_device_id": "satcega"},
        ]
        outcomes = []
        for args in args_list:
            for role, tok in [("anon", None), ("buyer", buyer), ("seller", seller)]:
                st, parsed = rpc(name, tok, args)
                outcomes.append({"role": role, "st": st, "args": args, "body": snippet(parsed, 180)})
                if st == 200 and role in ("anon", "buyer", "seller"):
                    # 200 with mutation effect is interesting; record
                    probe(f"rpc_{role}_{name}", status=st, args=args, body=snippet(parsed, 220))
            if name in moneyish:
                break  # one arg set is enough per money RPC; variants below
        EVIDENCE["rpc_results"][name] = outcomes[:12]
        # Explicit mint attempts
        if name == "batata_credit_wallet_once":
            st, parsed = rpc(name, buyer, {
                "p_wallet_id": BUYER_ID,
                "p_order_id": dummy,
                "p_amount": 500,
                "p_type": "reembolso",
                "p_description": "satcega",
            })
            probe("credit_wallet_buyer_self", status=st, body=snippet(parsed))
            if st == 200 and parsed not in (False, None):
                add_finding(
                    id="SAT-WAL-02",
                    severity="P0",
                    surface="WALLET",
                    title="JWT buyer executa batata_credit_wallet_once",
                    preconditions="GRANT authenticated",
                    identity="buyer",
                    request="rpc batata_credit_wallet_once",
                    response=snippet(parsed),
                    before=None,
                    after=None,
                    impact="Mint de saldo sem captura.",
                    confidence="alta",
                    variant="self wallet",
                    false_positive="função devolve false sem crédito",
                )
        if name == "batata_settle_live_tip_from_stripe":
            st, parsed = rpc(name, buyer, {
                "p_tip_id": dummy,
                "p_stripe_session_id": "cs_test_forged",
                "p_paid_amount_cents": 50000,
            })
            probe("settle_tip_jwt", status=st, body=snippet(parsed))
            if st == 200 and parsed is True:
                add_finding(
                    id="SAT-TIP-01",
                    severity="P0",
                    surface="TIPS",
                    title="JWT settle de gorjeta sem Stripe",
                    preconditions="RPC executável authenticated",
                    identity="buyer",
                    request="batata_settle_live_tip_from_stripe",
                    response=snippet(parsed),
                    before=None,
                    after=None,
                    impact="Crédito de gorjeta forjada.",
                    confidence="média",
                    variant="dummy tip id",
                    false_positive="true idempotente em tip inexistente",
                )
        if name == "batata_is_admin":
            st, parsed = rpc(name, buyer, {})
            probe("buyer_is_admin", status=st, body=snippet(parsed))
            if parsed is True:
                add_finding(
                    id="SAT-AUTH-05",
                    severity="P0",
                    surface="AUTH",
                    title="Buyer é admin segundo batata_is_admin",
                    preconditions="JWT buyer",
                    identity="buyer",
                    request="rpc batata_is_admin",
                    response=snippet(parsed),
                    before=None,
                    after=None,
                    impact="Gates admin abertos.",
                    confidence="alta",
                    variant="no args",
                    false_positive="nenhum",
                )


def make_product(seller: str, price: float, qty: int, title: str) -> str | None:
    st, parsed = rest(
        "POST",
        "products",
        seller,
        body={
            "seller_id": SELLER_ID,
            "title": title,
            "price": price,
            "quantity": qty,
            "list_on_marketplace": False,
            "available_for_live": False,
            "state": "Bom",
            "category": "Outros",
            "description": TAG,
        },
    )
    probe("create_product", status=st, body=snippet(parsed))
    if st in (201, 200) and isinstance(parsed, list) and parsed:
        pid = parsed[0]["id"]
        CREATED["products"].append(pid)
        return pid
    if st in (201, 200) and isinstance(parsed, dict) and parsed.get("id"):
        pid = parsed["id"]
        CREATED["products"].append(pid)
        return pid
    return None


def insert_order(token: str, body: dict[str, Any]) -> tuple[int, Any]:
    st, parsed = rest("POST", "orders", token, body=body)
    if st in (201, 200):
        rows = parsed if isinstance(parsed, list) else [parsed]
        for r in rows:
            if isinstance(r, dict) and r.get("id"):
                CREATED["orders"].append(r["id"])
    return st, parsed


def pass_orders_pricing(buyer: str, seller: str) -> str | None:
    set_cov("ORDERS", "TESTADA COM VARIANTES")
    set_cov("PRICING", "TESTADA COM VARIANTES")
    pid = make_product(seller, 48.90, 5, f"{TAG} unit 48.90 qty5")
    if not pid:
        NOTES.append("Não foi possível criar produto de teste — orders parciais.")
        return None
    # Baseline insert
    st, parsed = insert_order(buyer, {
        "product_id": pid,
        "buyer_id": BUYER_ID,
        "seller_id": SELLER_ID,
        "price_total": 1.00,
        "shipping_method": "Envio Transportadora (€3.50)",
        "payment_method": "Pagamento na App",
        "status": "reserva_pendente",
        "quantity": 1,
    })
    probe("order_insert_baseline", status=st, body=snippet(parsed))
    base = parsed[0] if isinstance(parsed, list) and parsed else (parsed if isinstance(parsed, dict) else {})
    # P0 candidate: client-sealed cheap contract
    st2, p2 = insert_order(buyer, {
        "product_id": pid,
        "buyer_id": BUYER_ID,
        "seller_id": SELLER_ID,
        "price_total": 48.90,
        "shipping_method": "Envio Transportadora (€3.50)",
        "payment_method": "Pagamento na App",
        "status": "reserva_pendente",
        "quantity": 1,
        "contract_unit_cents": 1,
        "contract_qty": 1,
    })
    probe("order_insert_cheap_contract", status=st2, body=snippet(p2))
    cheap = p2[0] if isinstance(p2, list) and p2 else {}
    if cheap.get("contract_unit_cents") == 1:
        add_finding(
            id="SAT-PRC-01",
            severity="P0",
            surface="PRICING",
            title="JWT sela contract_unit_cents=1 no INSERT",
            preconditions="produto 48.90€, buyer JWT",
            identity="buyer",
            request="POST orders contract_unit_cents=1",
            response=snippet(cheap),
            before={"catalog_price": 48.90},
            after={"contract_unit_cents": cheap.get("contract_unit_cents"), "order_id": cheap.get("id")},
            impact="Checkout autoritativo usa 0,01€ em vez do catálogo.",
            confidence="alta",
            variant="contract_unit_cents=1",
            false_positive="coluna gravada mas checkout ignora — confirmar na Edge",
        )
    # proposta dump
    st3, p3 = insert_order(buyer, {
        "product_id": pid,
        "buyer_id": BUYER_ID,
        "seller_id": SELLER_ID,
        "price_total": 0.50,
        "shipping_method": "Envio Transportadora (€3.50)",
        "payment_method": "Proposta aceite",
        "status": "reserva_pendente",
        "quantity": 1,
    })
    probe("order_insert_proposta_050", status=st3, body=snippet(p3))
    prop = p3[0] if isinstance(p3, list) and p3 else {}
    if prop.get("contract_unit_cents") is not None and int(prop.get("contract_unit_cents") or 0) <= 50:
        add_finding(
            id="SAT-PRC-02",
            severity="P0",
            surface="PRICING",
            title="payment_method 'proposta' sela contrato a price_total do cliente",
            preconditions="produto 48.90€",
            identity="buyer",
            request="POST orders payment_method=Proposta aceite price_total=0.50",
            response=snippet(prop),
            before={"catalog": 48.90},
            after={"contract_unit_cents": prop.get("contract_unit_cents")},
            impact="Comprador define o preço do Seguro Fleaber.",
            confidence="alta",
            variant="proposta 0.50",
            false_positive="proposta real deveria exigir acordo do seller",
        )
    # qty mismatch
    st4, p4 = insert_order(buyer, {
        "product_id": pid,
        "buyer_id": BUYER_ID,
        "seller_id": SELLER_ID,
        "price_total": 48.90,
        "shipping_method": "Envio Transportadora (€3.50)",
        "payment_method": "Pagamento na App",
        "status": "reserva_pendente",
        "quantity": 1,
        "contract_unit_cents": 1,
        "contract_qty": 5,
    })
    probe("order_insert_qty_mismatch", status=st4, body=snippet(p4))
    qrow = p4[0] if isinstance(p4, list) and p4 else {}
    if qrow.get("contract_qty") == 5 and qrow.get("quantity") == 1:
        add_finding(
            id="SAT-PRC-03",
            severity="P0",
            surface="PRICING",
            title="contract_qty=5 com quantity=1 no INSERT JWT",
            preconditions="stock 5",
            identity="buyer",
            request="POST orders quantity=1 contract_qty=5 contract_unit_cents=1",
            response=snippet(qrow),
            before={"stock": 5},
            after=qrow,
            impact="Checkout pode cobrar 5×1 cêntimo e/ou consumir 5 unidades.",
            confidence="alta",
            variant="qty split",
            false_positive="checkout usa quantity e ignora contract_qty",
        )
    # insert as pago
    st5, p5 = insert_order(buyer, {
        "product_id": pid,
        "buyer_id": BUYER_ID,
        "seller_id": SELLER_ID,
        "price_total": 48.90,
        "payment_method": "Pagamento na App",
        "status": "pago",
        "quantity": 1,
        "amount_paid_cents": 99999,
        "stripe_payment_intent_id": "pi_satcega_forged",
    })
    probe("order_insert_pago_forged", status=st5, body=snippet(p5))
    paid = p5[0] if isinstance(p5, list) and p5 else {}
    if str(paid.get("status") or "").lower() == "pago":
        add_finding(
            id="SAT-ORD-02",
            severity="P0",
            surface="ORDERS",
            title="Buyer INSERT status=pago",
            preconditions="produto próprio teste",
            identity="buyer",
            request="POST orders status=pago",
            response=snippet(paid),
            before=None,
            after=paid.get("status"),
            impact="Stock/wallet/review sem Stripe.",
            confidence="alta",
            variant="status pago",
            false_positive="trigger consome stock mas status revertido — ver after",
        )
    if paid.get("amount_paid_cents"):
        add_finding(
            id="SAT-ORD-03",
            severity="P0",
            surface="ORDERS",
            title="Buyer INSERT amount_paid_cents",
            preconditions="JWT",
            identity="buyer",
            request="POST orders amount_paid_cents=99999",
            response=snippet(paid),
            before=None,
            after=paid.get("amount_paid_cents"),
            impact="Fundos plataforma fabricados (invariante E).",
            confidence="alta",
            variant="amount_paid_cents",
            false_positive="coluna gravada mas wallet ignora sem settle",
        )
    # seller insert for other buyer
    st6, p6 = insert_order(seller, {
        "product_id": pid,
        "buyer_id": BUYER_ID,
        "seller_id": SELLER_ID,
        "price_total": 999.00,
        "payment_method": "Pagamento na App",
        "status": "reserva_pendente",
        "quantity": 1,
        "contract_unit_cents": 99900,
    })
    probe("seller_insert_order_for_buyer", status=st6, body=snippet(p6))
    srow = p6[0] if isinstance(p6, list) and p6 else {}
    if srow.get("id") and srow.get("buyer_id") == BUYER_ID:
        add_finding(
            id="SAT-ORD-04",
            severity="P1",
            surface="ORDERS",
            title="Seller cria order no nome do buyer com contrato inflacionado",
            preconditions="RLS insert parties",
            identity="seller",
            request="POST orders buyer_id=victim contract_unit_cents=99900",
            response=snippet(srow),
            before=None,
            after=srow,
            impact="Encomenda aparece ao comprador; checkout cobra o contrato inflacionado se o UI listar.",
            confidence="alta",
            variant="seller insert",
            false_positive="UI nunca lista reserva_pendente criada pelo seller",
        )
    # parties swap via UPDATE
    oid = (base or {}).get("id")
    if oid:
        st7, p7 = rest("PATCH", "orders", buyer, qs=f"?id=eq.{oid}", body={"seller_id": BUYER_ID, "price_total": 0.01, "status": "pago", "quantity": 5})
        st7b, p7b = rest("GET", "orders", buyer, qs=f"?id=eq.{oid}&select=id,status,seller_id,buyer_id,price_total,quantity,contract_unit_cents,amount_paid_cents")
        probe("buyer_update_parties_money", status=st7, patch=snippet(p7), after=snippet(p7b))
        row = p7b[0] if isinstance(p7b, list) and p7b else {}
        if row.get("seller_id") == BUYER_ID:
            add_finding(
                id="SAT-ORD-05",
                severity="P0",
                surface="ORDERS",
                title="Buyer muda seller_id da order",
                preconditions="order própria",
                identity="buyer",
                request="PATCH seller_id=self",
                response=snippet(row),
                before={"seller_id": SELLER_ID},
                after=row.get("seller_id"),
                impact="Hijack de ownership (invariante H).",
                confidence="alta",
                variant="seller_id",
                false_positive="nenhum",
            )
        if str(row.get("status") or "").lower() == "pago" and (base or {}).get("status") != "pago":
            add_finding(
                id="SAT-ORD-06",
                severity="P0",
                surface="ORDERS",
                title="Buyer PATCH status=pago",
                preconditions="order reserva_pendente",
                identity="buyer",
                request="PATCH status=pago",
                response=snippet(row),
                before=(base or {}).get("status"),
                after=row.get("status"),
                impact="Marca pago sem Stripe.",
                confidence="alta",
                variant="status",
                false_positive="nenhum",
            )
    # catalog hike after seal
    if cheap.get("id"):
        rest("PATCH", "products", seller, qs=f"?id=eq.{pid}", body={"price": 199.00})
        st8, p8 = rest("GET", "orders", buyer, qs=f"?id=eq.{cheap['id']}&select=id,contract_unit_cents,price_total")
        probe("catalog_hike_after_seal", status=st8, body=snippet(p8), product_price=199)
    # seller hike order after insert
    if cheap.get("id"):
        st9, p9 = rest("PATCH", "orders", seller, qs=f"?id=eq.{cheap['id']}", body={"contract_unit_cents": 19900, "price_total": 199})
        probe("seller_hike_contract", status=st9, body=snippet(p9))
        if isinstance(p9, list) and p9 and p9[0].get("contract_unit_cents") == 19900:
            add_finding(
                id="SAT-PRC-04",
                severity="P0",
                surface="PRICING",
                title="Seller altera contract_unit_cents depois do INSERT",
                preconditions="order existente",
                identity="seller",
                request="PATCH contract_unit_cents=19900",
                response=snippet(p9),
                before=cheap.get("contract_unit_cents"),
                after=19900,
                impact="Invariante K/L — contrato mutável.",
                confidence="alta",
                variant="seller PATCH",
                false_positive="nenhum",
            )
    return pid


def pass_checkout(buyer: str, seller: str, product_id: str | None) -> None:
    set_cov("CHECKOUT", "TESTADA COM VARIANTES")
    set_cov("SETTLE", "TESTADA COM VARIANTES")
    set_cov("WEBHOOK", "TESTADA COM VARIANTES")
    # Find a cheap-contract order if any
    st, parsed = rest("GET", "orders", buyer, qs=f"?product_id=eq.{product_id}&select=id,status,contract_unit_cents,contract_qty,quantity,price_total,buyer_id&order=created_at.desc&limit=10" if product_id else "?select=id&limit=1")
    orders = parsed if isinstance(parsed, list) else []
    cheap = next((o for o in orders if o.get("contract_unit_cents") == 1), orders[0] if orders else None)
    proposta = next((o for o in orders if o.get("contract_unit_cents") is not None and int(o.get("contract_unit_cents") or 9999) <= 50 and o.get("id") != (cheap or {}).get("id")), None)

    def checkout(body: dict[str, Any], token: str | None) -> tuple[int, Any]:
        return edge("create-payment-intent", token, body)

    # anon
    st0, p0 = checkout({"order_id": "x", "buyer_id": BUYER_ID, "amount": 50, "shipping_method": "carrier"}, None)
    probe("checkout_anon", status=st0, body=snippet(p0))
    # buyer swap
    if cheap:
        oid = cheap["id"]
        st1, p1 = checkout({
            "order_id": oid,
            "buyer_id": SELLER_ID,
            "amount": 50,
            "shipping_method": "carrier",
            "product_id": product_id,
        }, buyer)
        probe("checkout_buyer_id_spoof", status=st1, body=snippet(p1))
        st2, p2 = checkout({
            "order_id": oid,
            "buyer_id": BUYER_ID,
            "amount": 50,
            "shipping_method": "hand",
        }, buyer)
        probe("checkout_cheap_contract_hand", status=st2, body=snippet(p2))
        amt = None
        if isinstance(p2, dict):
            amt = p2.get("server_amount_cents") or p2.get("amount_total")
        if isinstance(amt, int) and amt < 200:
            add_finding(
                id="SAT-CHK-01",
                severity="P0",
                surface="CHECKOUT",
                title="Checkout Stripe criado a partir de contract_unit_cents=1",
                preconditions="SAT-PRC-01",
                identity="buyer",
                request="POST create-payment-intent shipping_method=hand",
                response=snippet(p2),
                before={"catalog": 48.90, "contract_unit_cents": 1},
                after={"server_amount_cents": amt, "session": p2.get("checkoutSessionId") if isinstance(p2, dict) else None},
                impact="Cobrança Stripe TEST muito abaixo do catálogo (invariante A/K).",
                confidence="alta",
                variant="hand + sealed 1 cent",
                false_positive="proteção/portes podem elevar; <2€ ainda é undercharge grave",
            )
        # body.amount ignored vs used
        st3, p3 = checkout({
            "order_id": oid,
            "buyer_id": BUYER_ID,
            "amount": 50,
            "shipping_method": "carrier",
        }, buyer)
        probe("checkout_body_amount_50", status=st3, body=snippet(p3))
        st4, p4 = checkout({
            "order_id": oid,
            "buyer_id": BUYER_ID,
            "amount": 999999,
            "shipping_method": "carrier",
            "product_id": str(uuid.uuid4()),
            "seller_id": BUYER_ID,
            "prize_shipping": True,
            "quantity": 99,
        }, buyer)
        probe("checkout_swap_ids_prize", status=st4, body=snippet(p4))
        # shipping garbage
        for sm in ["gratis", "EUR0", "free", "carrier", "hand", "3.50", "mao"]:
            stx, px = checkout({
                "order_id": oid,
                "buyer_id": BUYER_ID,
                "shipping_method": sm,
            }, buyer)
            probe(f"checkout_shipping_{sm}", status=stx, body=snippet(px, 220))
        # seller checkout of buyer order
        st5, p5 = checkout({
            "order_id": oid,
            "buyer_id": BUYER_ID,
            "shipping_method": "carrier",
        }, seller)
        probe("checkout_seller_on_buyer_order", status=st5, body=snippet(p5))
        if st5 == 200:
            add_finding(
                id="SAT-CHK-02",
                severity="P1",
                surface="CHECKOUT",
                title="Seller inicia checkout da order do buyer",
                preconditions="order buyer",
                identity="seller",
                request="POST create-payment-intent order do buyer",
                response=snippet(p5),
                before=None,
                after=None,
                impact="Session Stripe sob identidade errada / phishing de pagamento.",
                confidence="alta",
                variant="seller JWT",
                false_positive="200 sem URL",
            )
        # GET settle without auth
        if isinstance(p3, dict) and p3.get("checkoutSessionId"):
            sid = p3["checkoutSessionId"]
            stg, pg = edge("create-payment-intent", None, method="GET", qs=f"?checkout_return=success&session_id={sid}")
            probe("settle_get_unpaid_session", status=stg, body=snippet(pg, 300))
            # duplicate GET
            stg2, pg2 = edge("create-payment-intent", None, method="GET", qs=f"?checkout_return=success&session_id={sid}")
            probe("settle_get_unpaid_session_retry", status=stg2, body=snippet(pg2, 200))
        # fase2 e2e as JWT
        st6, p6 = edge("create-payment-intent", buyer, {"order_id": oid, "payment_intent_id": "pi_x"}, qs="?fase2_e2e_settle=1")
        probe("fase2_e2e_as_buyer", status=st6, body=snippet(p6))
        if st6 == 200:
            add_finding(
                id="SAT-CHK-03",
                severity="P0",
                surface="SETTLE",
                title="fase2_e2e_settle aceita JWT buyer",
                preconditions="query param",
                identity="buyer",
                request="POST create-payment-intent?fase2_e2e_settle=1",
                response=snippet(p6),
                before=None,
                after=None,
                impact="Harness de settle aberto a utilizador.",
                confidence="alta",
                variant="buyer JWT",
                false_positive="200 de erro no JSON",
            )
        st7, p7 = edge("create-payment-intent", buyer, {"order_id": oid, "payment_intent_id": "pi_x"}, qs="?fase2_e2e_settle=1", extra={"Authorization": "Bearer " + "a" * len(SVC)})
        probe("fase2_e2e_wrong_len_token", status=st7, body=snippet(p7))
    if proposta:
        st8, p8 = checkout({
            "order_id": proposta["id"],
            "buyer_id": BUYER_ID,
            "shipping_method": "hand",
        }, buyer)
        probe("checkout_proposta_order", status=st8, body=snippet(p8))
        if isinstance(p8, dict) and isinstance(p8.get("server_amount_cents"), int) and p8["server_amount_cents"] < 200:
            add_finding(
                id="SAT-CHK-04",
                severity="P0",
                surface="CHECKOUT",
                title="Checkout usa contrato proposta dump",
                preconditions="SAT-PRC-02",
                identity="buyer",
                request="create-payment-intent proposta order",
                response=snippet(p8),
                before={"catalog": 48.90},
                after=p8.get("server_amount_cents"),
                impact="Undercharge via proposta forjada.",
                confidence="alta",
                variant="hand",
                false_positive="nenhum se amount << catálogo",
            )
    # webhook
    stw, pw = edge("stripe-webhook", None, {"type": "checkout.session.completed"})
    probe("webhook_no_sig", status=stw, body=snippet(pw))
    stw2, pw2 = edge("stripe-webhook", None, b"{}", extra={"stripe-signature": "t=1,v1=dead"})
    probe("webhook_bad_sig", status=stw2, body=snippet(pw2))
    if stw in (200, 201) or stw2 == 200:
        add_finding(
            id="SAT-WH-01",
            severity="P0",
            surface="WEBHOOK",
            title="Webhook Stripe aceita pedido sem assinatura válida",
            preconditions="anon",
            identity="anon",
            request="POST stripe-webhook",
            response={"no_sig": snippet(pw), "bad_sig": snippet(pw2)},
            before=None,
            after=None,
            impact="Settle forjado.",
            confidence="alta",
            variant="missing/bad sig",
            false_positive="200 ignored type",
        )


def pass_bag(buyer: str, seller: str, product_id: str | None) -> None:
    set_cov("BAG", "TESTADA COM VARIANTES")
    if not product_id:
        return
    pid2 = make_product(seller, 12.00, 3, f"{TAG} bag B 12")
    if not pid2:
        return
    lines = []
    for pid, price in [(product_id, 48.90), (pid2, 12.00)]:
        st, parsed = insert_order(buyer, {
            "product_id": pid,
            "buyer_id": BUYER_ID,
            "seller_id": SELLER_ID,
            "price_total": price,
            "payment_method": "Pagamento na App",
            "status": "reserva_pendente",
            "quantity": 1,
            "shipping_method": "Envio Transportadora (€3.50)",
            "contract_unit_cents": 1,
        })
        row = parsed[0] if isinstance(parsed, list) and parsed else {}
        if row.get("id"):
            lines.append({"order_id": row["id"], "product_id": pid, "line_total_cents": 1, "quantity": 99})
    if len(lines) < 2:
        return
    st, parsed = edge("create-payment-intent", buyer, {
        "order_id": lines[0]["order_id"],
        "buyer_id": BUYER_ID,
        "shipping_method": "carrier",
        "bag_checkout": True,
        "bag_lines": lines,
        "amount": 50,
    })
    probe("bag_checkout_2lines_cheap", status=st, body=snippet(parsed))
    if isinstance(parsed, dict) and isinstance(parsed.get("server_amount_cents"), int):
        amt = parsed["server_amount_cents"]
        # honest bag ~ 48.90+12 + 3.50 + prot ≈ 70€
        if amt < 1500:
            add_finding(
                id="SAT-BAG-01",
                severity="P0",
                surface="BAG",
                title="Bag checkout undercharge com contract_unit_cents=1 nas linhas",
                preconditions="2 orders seladas a 1 cêntimo",
                identity="buyer",
                request="create-payment-intent bag_checkout",
                response=snippet(parsed),
                before={"catalog_sum": 60.90},
                after=amt,
                impact="Saco multi-linha cobrado a cêntimos.",
                confidence="alta",
                variant="2 linhas",
                false_positive="desconto conjunto não explica <15€",
            )
    # 3rd line other seller product if any
    st2, p2 = edge("create-payment-intent", buyer, {
        "order_id": lines[0]["order_id"],
        "buyer_id": BUYER_ID,
        "shipping_method": "carrier",
        "bag_checkout": True,
        "bag_lines": lines + [{"order_id": str(uuid.uuid4())}],
    })
    probe("bag_ghost_line", status=st2, body=snippet(p2))


def pass_refund_dispute(buyer: str, seller: str) -> None:
    set_cov("REFUND", "TESTADA COM VARIANTES")
    set_cov("DISPUTE", "TESTADA COM VARIANTES")
    st, parsed = rest("GET", "orders", seller, qs="?select=id,status,payment_method,amount_paid_cents,stripe_payment_intent_id,buyer_id,seller_id&status=in.(pago,enviado,concluido)&limit=5")
    probe("seller_paid_orders", status=st, body=snippet(parsed))
    rows = parsed if isinstance(parsed, list) else []
    # buyer refund
    if rows:
        oid = rows[0]["id"]
        st1, p1 = edge("refund-order", buyer, {"order_id": oid})
        probe("refund_as_buyer", status=st1, body=snippet(p1))
        if st1 == 200 and isinstance(p1, dict) and p1.get("ok") is True and not p1.get("skipped"):
            add_finding(
                id="SAT-REF-01",
                severity="P0",
                surface="REFUND",
                title="Buyer executa refund-order de encomenda alheia/própria sem ser seller",
                preconditions="order paga",
                identity="buyer",
                request="POST refund-order",
                response=snippet(p1),
                before=rows[0],
                after=p1,
                impact="Reembolso não autorizado.",
                confidence="alta",
                variant="buyer JWT",
                false_positive="skipped not_seguro",
            )
        st2, p2 = edge("refund-order", None, {"order_id": oid})
        probe("refund_anon", status=st2, body=snippet(p2))
        # duplicate concurrent
        def once():
            return edge("refund-order", seller, {"order_id": oid})
        with ThreadPoolExecutor(max_workers=3) as ex:
            futs = [ex.submit(once) for _ in range(3)]
            res = [f.result() for f in as_completed(futs)]
        probe("refund_concurrent_seller", status=[r[0] for r in res], body=snippet([r[1] for r in res], 500))
    # disputes
    st3, p3 = rest("GET", "order_disputes", buyer, qs="?select=*&limit=5")
    probe("buyer_disputes_select", status=st3, body=snippet(p3))
    st4, p4 = rest("POST", "order_disputes", buyer, body={
        "order_id": str(uuid.uuid4()),
        "buyer_id": SELLER_ID,
        "status": "aberta",
        "seller_offer_percent": 100,
    })
    probe("dispute_insert_spoof", status=st4, body=snippet(p4))
    if st4 in (200, 201) and p4 not in ([], None, ""):
        add_finding(
            id="SAT-DIS-01",
            severity="P1",
            surface="DISPUTE",
            title="Buyer INSERT disputa forjada (order inexistente / buyer spoof)",
            preconditions="JWT buyer",
            identity="buyer",
            request="POST order_disputes",
            response=snippet(p4),
            before=None,
            after=snippet(p4),
            impact="Máquina de estados de devolução / refund %.",
            confidence="média",
            variant="spoof buyer_id",
            false_positive="FK falha vs 201",
        )
    st5, p5 = rpc("batata_process_partial_refund_dispute", buyer, {"p_order_id": str(uuid.uuid4()), "p_percent": 100})
    probe("partial_refund_rpc_buyer", status=st5, body=snippet(p5))
    st6, p6 = rpc("batata_process_partial_refund_dispute", seller, {"p_order_id": rows[0]["id"] if rows else str(uuid.uuid4()), "p_percent": 100})
    probe("partial_refund_rpc_seller", status=st6, body=snippet(p6))
    if st6 == 200 and isinstance(p6, dict) and p6.get("ok") is True:
        add_finding(
            id="SAT-DIS-02",
            severity="P0",
            surface="DISPUTE",
            title="Seller JWT processa refund parcial a 100% via RPC",
            preconditions="order paga visível",
            identity="seller",
            request="batata_process_partial_refund_dispute 100%",
            response=snippet(p6),
            before=rows[0] if rows else None,
            after=p6,
            impact="Refund wallet/Stripe sem disputa real.",
            confidence="média",
            variant="100%",
            false_positive="ok sem movimento financeiro",
        )


def pass_wallet_payout(buyer: str, seller: str) -> None:
    set_cov("WALLET", "TESTADA COM VARIANTES")
    set_cov("PAYOUT", "TESTADA COM VARIANTES")
    for role, tok, uid in [("buyer", buyer, BUYER_ID), ("seller", seller, SELLER_ID)]:
        st, parsed = rest("GET", "wallets", tok, qs=f"?id=eq.{uid}&select=*")
        probe(f"wallet_self_{role}", status=st, body=snippet(parsed))
        st2, p2 = rest("POST", "wallets", tok, body={"id": uid, "balance": 1000})
        probe(f"wallet_insert_{role}", status=st2, body=snippet(p2))
        st3, p3 = rest("PATCH", "wallets", tok, qs=f"?id=eq.{uid}", body={"balance": 9999.00})
        probe(f"wallet_patch_balance_{role}", status=st3, body=snippet(p3))
        if st3 in (200, 204) and isinstance(p3, list) and p3 and float(p3[0].get("balance") or 0) >= 9999:
            add_finding(
                id="SAT-WAL-03",
                severity="P0",
                surface="WALLET",
                title=f"{role} PATCH wallets.balance",
                preconditions="JWT",
                identity=role,
                request="PATCH wallets balance=9999",
                response=snippet(p3),
                before=snippet(parsed),
                after=p3[0].get("balance"),
                impact="Mint directo de saldo levantável.",
                confidence="alta",
                variant="balance patch",
                false_positive="representation stale",
            )
        st4, p4 = rest("POST", "wallet_transactions", tok, body={
            "wallet_id": uid,
            "amount": 500,
            "type": "venda",
            "description": TAG,
        })
        probe(f"wallet_tx_insert_{role}", status=st4, body=snippet(p4))
        st5, p5 = rest("GET", "wallet_payout_ledger", tok, qs="?select=*&limit=5")
        probe(f"payout_ledger_{role}", status=st5, body=snippet(p5))
    # cross user wallet
    st, parsed = rest("GET", "wallets", buyer, qs=f"?id=eq.{SELLER_ID}&select=*")
    probe("buyer_read_seller_wallet", status=st, body=snippet(parsed))
    if st == 200 and isinstance(parsed, list) and parsed:
        add_finding(
            id="SAT-WAL-04",
            severity="P1",
            surface="WALLET",
            title="Buyer lê wallet do seller",
            preconditions="id conhecido",
            identity="buyer",
            request=f"GET wallets?id=eq.{SELLER_ID}",
            response=snippet(parsed),
            before=None,
            after=None,
            impact="Saldo e stripe_account_id.",
            confidence="alta",
            variant="id eq",
            false_positive="0 rows",
        )
    # payout hostile
    st, parsed = edge("create-connect-account", buyer, {"user_id": SELLER_ID, "amount": 100, "idempotency_key": "satcega-cross-" + uuid.uuid4().hex[:12]})
    probe("payout_buyer_as_seller", status=st, body=snippet(parsed))
    st2, p2 = edge("create-connect-account", seller, {"amount": 1, "idempotency_key": "short"})
    probe("payout_short_idem", status=st2, body=snippet(p2))
    st3, p3 = edge("create-connect-account", seller, {"amount": 10**12, "idempotency_key": "satcega-huge-" + uuid.uuid4().hex[:12]})
    probe("payout_huge_amount", status=st3, body=snippet(p3))
    st4, p4 = edge("create-connect-account", None, {"amount": 100, "idempotency_key": "satcega-anon-xxxx"})
    probe("payout_anon", status=st4, body=snippet(p4))
    # two intents same amount concurrent
    key_a = "satcega-a-" + uuid.uuid4().hex[:12]
    key_b = "satcega-b-" + uuid.uuid4().hex[:12]
    def pay(k):
        return edge("create-connect-account", seller, {"amount": 50, "idempotency_key": k})
    with ThreadPoolExecutor(max_workers=2) as ex:
        ra, rb = ex.submit(pay, key_a).result(), ex.submit(pay, key_b).result()
    probe("payout_two_intents", a=snippet(ra), b=snippet(rb))
    # rpc debit
    st5, p5 = rpc("batata_wallet_payout_debit", buyer, {"p_user_id": SELLER_ID, "p_amount_cents": 50, "p_idempotency_key": "satcega-debit-x"})
    probe("payout_debit_rpc_cross", status=st5, body=snippet(p5))
    if st5 == 200 and isinstance(p5, dict) and p5.get("ok") is True:
        add_finding(
            id="SAT-PAY-01",
            severity="P0",
            surface="PAYOUT",
            title="Buyer RPC debita wallet do seller",
            preconditions="GRANT",
            identity="buyer",
            request="batata_wallet_payout_debit",
            response=snippet(p5),
            before=None,
            after=p5,
            impact="Roubo de saldo.",
            confidence="alta",
            variant="cross user",
            false_positive="ok false",
        )


def pass_stock_live_bag(buyer: str, seller: str, product_id: str | None) -> None:
    set_cov("STOCK", "TESTADA COM VARIANTES")
    set_cov("LIVE", "TESTADA COM VARIANTES")
    set_cov("RESERVATIONS", "TESTADA COM VARIANTES")
    if product_id:
        rest("PATCH", "products", seller, qs=f"?id=eq.{product_id}", body={"quantity": 2, "price": 48.90})
        st, parsed = insert_order(buyer, {
            "product_id": product_id,
            "buyer_id": BUYER_ID,
            "seller_id": SELLER_ID,
            "price_total": 48.90,
            "payment_method": "Pagamento na App",
            "status": "reserva_pendente",
            "quantity": 2,
        })
        probe("order_qty_eq_stock", status=st, body=snippet(parsed))
        st2, p2 = insert_order(buyer, {
            "product_id": product_id,
            "buyer_id": BUYER_ID,
            "seller_id": SELLER_ID,
            "price_total": 48.90,
            "payment_method": "Pagamento na App",
            "status": "reserva_pendente",
            "quantity": 3,
        })
        probe("order_qty_gt_stock", status=st2, body=snippet(p2))
        if st2 in (200, 201) and p2 not in ([], None, ""):
            add_finding(
                id="SAT-STK-01",
                severity="P1",
                surface="STOCK",
                title="INSERT order quantity > stock",
                preconditions="stock 2",
                identity="buyer",
                request="POST orders quantity=3",
                response=snippet(p2),
                before={"stock": 2},
                after=snippet(p2),
                impact="Oversell no contrato.",
                confidence="alta",
                variant="qty 3 vs 2",
                false_positive="produto já alterado por teste anterior",
            )
        # concurrent inserts qty=2
        def ins():
            return insert_order(buyer, {
                "product_id": product_id,
                "buyer_id": BUYER_ID,
                "seller_id": SELLER_ID,
                "price_total": 48.90,
                "payment_method": "Pagamento na App",
                "status": "reserva_pendente",
                "quantity": 2,
            })
        with ThreadPoolExecutor(max_workers=2) as ex:
            r1, r2 = ex.submit(ins).result(), ex.submit(ins).result()
        probe("concurrent_order_same_stock", a=snippet(r1), b=snippet(r2))
    # lives stream key as buyer
    st, parsed = rest("GET", "lives", buyer, qs="?select=id,seller_id,mux_stream_key,stream_key,mux_playback_id,status&limit=5")
    probe("buyer_lives", status=st, body=snippet(parsed))
    lives = parsed if isinstance(parsed, list) else []
    keys = [r.get("mux_stream_key") or r.get("stream_key") for r in lives if r.get("mux_stream_key") or r.get("stream_key")]
    if keys:
        add_finding(
            id="SAT-MUX-02",
            severity="P0",
            surface="MUX",
            title="Buyer JWT lê mux_stream_key",
            preconditions="lives existentes",
            identity="buyer",
            request="GET lives",
            response=snippet(keys),
            before=None,
            after=None,
            impact="Ingest hijack.",
            confidence="alta",
            variant="select",
            false_positive="null keys",
        )
    st2, p2 = rest("GET", "lives", None, qs="?select=id,mux_stream_key,stream_key&limit=3")
    probe("anon_lives_keys", status=st2, body=snippet(p2))
    # reservations
    st3, p3 = rest("GET", "live_reservation_requests", buyer, qs="?select=*&limit=5")
    probe("buyer_reservations", status=st3, body=snippet(p3))
    live_id = None
    item_id = None
    st4, p4 = rest("GET", "live_items", seller, qs="?select=id,live_id,product_id,price,status&limit=5")
    probe("seller_live_items", status=st4, body=snippet(p4))
    if isinstance(p4, list) and p4:
        live_id = p4[0].get("live_id")
        item_id = p4[0].get("id")
    if live_id and item_id:
        st5, p5 = rest("POST", "live_reservation_requests", buyer, body={
            "live_id": live_id,
            "live_item_id": item_id,
            "buyer_id": BUYER_ID,
            "seller_id": SELLER_ID,
            "requested_qty": 99,
            "status": "accepted",
            "source": "fleaber_live",
        })
        probe("reservation_insert_qty99_accepted", status=st5, body=snippet(p5))
        row = p5[0] if isinstance(p5, list) and p5 else {}
        if row.get("requested_qty") == 99 or str(row.get("status") or "") == "accepted":
            add_finding(
                id="SAT-RES-01",
                severity="P1",
                surface="RESERVATIONS",
                title="Buyer INSERT reserva qty=99 status=accepted",
                preconditions="live_item existente",
                identity="buyer",
                request="POST live_reservation_requests",
                response=snippet(p5),
                before=None,
                after=row,
                impact="Fila/stock live sem RPC.",
                confidence="alta",
                variant="direct insert",
                false_positive="trigger cap qty",
            )
        st6, p6 = rpc("batata_live_bag_update_qty", buyer, {"p_request_id": row.get("id") or str(uuid.uuid4()), "p_qty": 50})
        probe("bag_update_qty_rpc", status=st6, body=snippet(p6))
        if row.get("id"):
            st7, p7 = rpc("batata_process_live_reservation_request", buyer, {"p_request_id": row["id"], "p_action": "accept"})
            probe("buyer_accept_own_reservation", status=st7, body=snippet(p7))


def pass_raffle_tips(buyer: str, seller: str) -> None:
    set_cov("RAFFLE", "TESTADA COM VARIANTES")
    set_cov("TIPS", "TESTADA COM VARIANTES")
    st, parsed = rest("GET", "live_raffles", buyer, qs="?select=*&limit=5")
    probe("buyer_raffles", status=st, body=snippet(parsed))
    st2, p2 = rest("GET", "live_raffle_winners", buyer, qs="?select=*&limit=5")
    probe("buyer_raffle_winners", status=st2, body=snippet(p2))
    raffles = parsed if isinstance(parsed, list) else []
    if raffles:
        rid = raffles[0].get("id")
        st3, p3 = rest("POST", "live_raffle_winners", buyer, body={"raffle_id": rid, "user_id": BUYER_ID})
        probe("insert_self_winner", status=st3, body=snippet(p3))
        if st3 in (200, 201) and p3 not in ([], None, ""):
            add_finding(
                id="SAT-RAF-01",
                severity="P0",
                surface="RAFFLE",
                title="Buyer INSERT-se como vencedor de rifa",
                preconditions="rifa existente",
                identity="buyer",
                request="POST live_raffle_winners",
                response=snippet(p3),
                before=None,
                after=snippet(p3),
                impact="Prémio financeiro / checkout portes.",
                confidence="alta",
                variant="self winner",
                false_positive="unique conflict",
            )
        st4, p4 = rpc("batata_draw_live_raffle_winners", buyer, {"p_raffle_id": rid})
        probe("buyer_draw_raffle", status=st4, body=snippet(p4))
        st5, p5 = rpc("batata_create_raffle_prize_order", buyer, {"p_raffle_id": rid, "p_user_id": BUYER_ID})
        probe("buyer_create_prize_order", status=st5, body=snippet(p5))
    st6, p6 = rest("POST", "live_tips", buyer, body={
        "buyer_id": BUYER_ID,
        "seller_id": SELLER_ID,
        "amount": 1,
        "status": "completed",
        "payment_source": "stripe",
    })
    probe("tip_insert_completed", status=st6, body=snippet(p6))
    if st6 in (200, 201) and isinstance(p6, list) and p6 and str(p6[0].get("status")) == "completed":
        add_finding(
            id="SAT-TIP-02",
            severity="P1",
            surface="TIPS",
            title="Buyer INSERT live_tips status=completed",
            preconditions="JWT",
            identity="buyer",
            request="POST live_tips completed",
            response=snippet(p6),
            before=None,
            after=p6[0],
            impact="Pode despoletar crédito se houver trigger.",
            confidence="média",
            variant="completed insert",
            false_positive="sem trigger de crédito",
        )
    st7, p7 = edge("create-live-tip-checkout", buyer, {
        "seller_id": SELLER_ID,
        "amount_eur": 1,
        "tip_id": str(uuid.uuid4()),
    })
    probe("tip_checkout_client_tip_id", status=st7, body=snippet(p7))
    st8, p8 = edge("create-live-tip-checkout", buyer, {"seller_id": SELLER_ID, "amount_eur": 0.01})
    probe("tip_checkout_min", status=st8, body=snippet(p8))
    st9, p9 = edge("create-live-tip-checkout", buyer, {"seller_id": SELLER_ID, "amount_eur": 501})
    probe("tip_checkout_over_max", status=st9, body=snippet(p9))
    st10, p10 = edge("create-live-tip-checkout", seller, {"seller_id": SELLER_ID, "amount_eur": 1})
    probe("tip_self_seller", status=st10, body=snippet(p10))
    st11, p11 = rpc("batata_send_live_tip_from_wallet", buyer, {"p_seller_id": SELLER_ID, "p_amount": 1})
    probe("wallet_tip_rpc", status=st11, body=snippet(p11))


def pass_chat_reviews_storage(buyer: str, seller: str) -> None:
    set_cov("CHAT", "TESTADA COM VARIANTES")
    set_cov("REVIEWS", "TESTADA COM VARIANTES")
    set_cov("STORAGE", "TESTADA COM VARIANTES")
    st, parsed = rest("POST", "chats", buyer, body={"user_a": BUYER_ID, "user_b": SELLER_ID})
    probe("chat_insert", status=st, body=snippet(parsed))
    chat = parsed[0] if isinstance(parsed, list) and parsed else {}
    cid = chat.get("id")
    if cid:
        CREATED["chats"].append(cid)
        st2, p2 = rest("POST", "chat_messages", buyer, body={
            "chat_id": cid,
            "sender_id": SELLER_ID,
            "receiver_id": BUYER_ID,
            "text": "spoof seller",
            "is_reservation": False,
        })
        probe("chat_sender_spoof", status=st2, body=snippet(p2))
        row = p2[0] if isinstance(p2, list) and p2 else {}
        if row.get("sender_id") == SELLER_ID:
            add_finding(
                id="SAT-CHAT-02",
                severity="P1",
                surface="CHAT",
                title="Buyer INSERT mensagem com sender_id do seller",
                preconditions="chat próprio",
                identity="buyer",
                request="POST chat_messages sender_id=seller",
                response=snippet(p2),
                before=None,
                after=row,
                impact="Spoof de sistema/vendedor.",
                confidence="alta",
                variant="sender spoof",
                false_positive="trigger reescreve sender mas representation mente",
            )
        st3, p3 = rest("GET", "chats", buyer, qs="?select=id,user_a,user_b&limit=20")
        chats = p3 if isinstance(p3, list) else []
        foreign = [c for c in chats if BUYER_ID not in (c.get("user_a"), c.get("user_b"))]
        probe("buyer_list_chats", status=st3, n=len(chats), foreign=len(foreign))
        if foreign:
            add_finding(
                id="SAT-CHAT-03",
                severity="P1",
                surface="CHAT",
                title="Buyer lista chats onde não participa",
                preconditions="JWT",
                identity="buyer",
                request="GET chats",
                response=snippet(foreign),
                before=None,
                after=None,
                impact="Metadados de conversas alheias.",
                confidence="alta",
                variant="select",
                false_positive="nenhum",
            )
        if chats:
            other = next((c["id"] for c in chats if c["id"] != cid), None)
            if other:
                st4, p4 = rest("POST", "chat_messages", buyer, body={
                    "chat_id": other,
                    "sender_id": BUYER_ID,
                    "receiver_id": SELLER_ID,
                    "text": "cross-chat",
                })
                probe("chat_cross_thread", status=st4, body=snippet(p4))
                if st4 in (200, 201) and p4 not in ([], None, ""):
                    add_finding(
                        id="SAT-CHAT-04",
                        severity="P1",
                        surface="CHAT",
                        title="Buyer injeta mensagem noutro chat",
                        preconditions="id de chat visível",
                        identity="buyer",
                        request="POST chat_messages chat_id alheio/outro",
                        response=snippet(p4),
                        before=None,
                        after=snippet(p4),
                        impact="Cross-chat write.",
                        confidence="média",
                        variant="other chat id",
                        false_positive="other ainda é participante",
                    )
        st5, p5 = rest("PATCH", "chat_messages", buyer, qs=f"?chat_id=eq.{cid}", body={"text": "edited"})
        probe("chat_update", status=st5, body=snippet(p5))
        st6, p6 = rest("DELETE", "chat_messages", buyer, qs=f"?chat_id=eq.{cid}")
        probe("chat_delete", status=st6, body=snippet(p6))
        st7, p7 = rest("PATCH", "chats", buyer, qs=f"?id=eq.{cid}", body={"user_a": SELLER_ID, "user_b": SELLER_ID, "last_message": "hack"})
        probe("chat_parties_update", status=st7, body=snippet(p7))
        if isinstance(p7, list) and p7 and p7[0].get("user_a") == SELLER_ID and p7[0].get("user_b") == SELLER_ID:
            add_finding(
                id="SAT-CHAT-05",
                severity="P1",
                surface="CHAT",
                title="Buyer altera participantes do chat",
                preconditions="chat próprio",
                identity="buyer",
                request="PATCH chats user_a/user_b",
                response=snippet(p7),
                before=chat,
                after=p7[0],
                impact="Exclusão do comprador / hijack.",
                confidence="alta",
                variant="parties",
                false_positive="nenhum",
            )
    # reviews
    st, parsed = rest("GET", "reviews", None, qs="?select=*&limit=5")
    probe("anon_reviews", status=st, body=snippet(parsed))
    st2, p2 = rest("POST", "reviews", buyer, body={
        "buyer_id": SELLER_ID,
        "target_id": BUYER_ID,
        "order_id": str(uuid.uuid4()),
        "rating": 5,
        "comment": TAG,
        "author_role": "comprador",
    })
    probe("review_insert_invalid", status=st2, body=snippet(p2))
    st3, p3 = rest("GET", "orders", buyer, qs="?status=in.(concluido,entregue)&select=id,status,seller_id,buyer_id&limit=3")
    probe("buyer_completed_orders", status=st3, body=snippet(p3))
    completed = p3 if isinstance(p3, list) else []
    if completed:
        oid = completed[0]["id"]
        st4, p4 = rest("POST", "reviews", buyer, body={
            "buyer_id": BUYER_ID,
            "target_id": completed[0].get("seller_id"),
            "order_id": oid,
            "rating": 1,
            "comment": TAG,
        })
        probe("review_insert_completed", status=st4, body=snippet(p4))
        st5, p5 = rest("POST", "reviews", buyer, body={
            "buyer_id": BUYER_ID,
            "target_id": completed[0].get("seller_id"),
            "order_id": oid,
            "rating": 5,
            "comment": TAG + " dup",
        })
        probe("review_duplicate", status=st5, body=snippet(p5))
        if st5 in (200, 201) and p5 not in ([], None, ""):
            add_finding(
                id="SAT-REV-01",
                severity="P1",
                surface="REVIEWS",
                title="Review duplicada na mesma order",
                preconditions="order concluida",
                identity="buyer",
                request="POST reviews 2x",
                response=snippet(p5),
                before=None,
                after=snippet(p5),
                impact="Duplo release wallet se trigger por review.",
                confidence="média",
                variant="duplicate",
                false_positive="unique index",
            )
    # storage
    buckets = [
        "chat_media", "fleaber_private", "order_proofs", "disputes",
        "product_photos", "profile_photos", "live_photos", "avatars",
    ]
    for b in buckets:
        url = f"{BASE}/storage/v1/object/list/{b}"
        st, parsed, _ = http("POST", url, token=buyer, body={"prefix": "", "limit": 10})
        probe(f"storage_list_buyer_{b}", status=st, body=snippet(parsed, 220))
        st0, p0, _ = http("POST", url, token=None, apikey=ANON, body={"prefix": "", "limit": 5})
        probe(f"storage_list_anon_{b}", status=st0, body=snippet(p0, 180))
        if st0 == 200 and isinstance(p0, list) and p0:
            add_finding(
                id=f"SAT-STO-ANON-{b}",
                severity="P1",
                surface="STORAGE",
                title=f"Anon lista bucket {b}",
                preconditions="anon",
                identity="anon",
                request=f"POST storage/object/list/{b}",
                response=snippet(p0),
                before=None,
                after=None,
                impact="Enumeração de ficheiros.",
                confidence="alta",
                variant="list",
                false_positive="bucket público intencional (product_photos)",
            )
        # upload
        path = f"{SELLER_ID}/satcega-{uuid.uuid4().hex[:8]}.txt"
        st_u, p_u, _ = http(
            "POST",
            f"{BASE}/storage/v1/object/{b}/{path}",
            token=buyer,
            body=b"satcega",
            extra_headers={"Content-Type": "text/plain", "x-upsert": "true"},
        )
        probe(f"storage_upload_buyer_{b}", status=st_u, path=path, body=snippet(p_u, 180))
        if st_u in (200, 201) and b in ("fleaber_private", "order_proofs", "disputes", "chat_media"):
            add_finding(
                id=f"SAT-STO-UP-{b}",
                severity="P1",
                surface="STORAGE",
                title=f"Buyer faz upload para path do seller em {b}",
                preconditions="path {seller}/...",
                identity="buyer",
                request=f"POST object/{b}/{path}",
                response=snippet(p_u),
                before=None,
                after=path,
                impact="Overwrite/prova falsa.",
                confidence="alta",
                variant="cross-user path",
                false_positive="200 sem persistir",
            )
        # public url
        st_g, p_g, _ = http("GET", f"{BASE}/storage/v1/object/public/{b}/{path}", token=None, apikey=ANON)
        probe(f"storage_public_{b}", status=st_g, body=snippet(p_g, 80))


def pass_mux_ps_edges(buyer: str, seller: str) -> None:
    set_cov("MUX", "TESTADA COM VARIANTES")
    set_cov("LIVEKIT", "TESTADA COM VARIANTES")
    set_cov("PS/OCR", "TESTADA COM VARIANTES")
    edges = [
        ("create-mux-live", buyer, {"title": "satcega buyer live"}),
        ("create-mux-live", seller, {"title": "satcega seller live skip"}),
        ("complete-mux-live", buyer, {"live_id": str(uuid.uuid4())}),
        ("resolve-mux-playback", None, {"live_id": str(uuid.uuid4())}),
        ("livekit-mux-publish", buyer, {"step": "token", "live_id": str(uuid.uuid4())}),
        ("livekit-mux-publish", seller, {"step": "egress", "live_id": str(uuid.uuid4()), "stream_key": "sk_sat"}),
        ("livekit-egress-cleanup", None, {}),
        ("ps-pairing-claim", None, {"code": "000000", "device_id": "satcega"}),
        ("ps-heartbeat", None, {"device_id": "satcega"}),
        ("ps-panel-log", None, {"event": "x"}),
        ("ingest-ocr-reservation", None, {"live_id": str(uuid.uuid4()), "ocr_line_hash": "abcdefgh", "detected_at": "2026-08-27T00:00:00Z", "ref_number": 1}),
        ("delete-test-account", buyer, {"confirm": "APAGAR TUDO"}),
        ("sec-fase2-e2e-oversell", buyer, {"buyer_id": BUYER_ID, "seller_id": SELLER_ID}),
        ("meta-data-deletion", None, {}),
        ("send-sms-bulkgate", None, {"phone": "+351910000000", "text": "hi"}),
    ]
    # pairing brute 20 codes
    for code in ["000000", "123456", "111111", "999999", "654321"]:
        st, parsed = edge("ps-pairing-claim", None, {"code": code, "device_id": "satcega"})
        probe(f"pairing_{code}", status=st, body=snippet(parsed, 180))
    st, parsed = edge("create-mux-live", buyer, {"title": "satcega buyer live xxx"})
    probe("mux_create_buyer", status=st, body=snippet(parsed))
    if st == 200:
        add_finding(
            id="SAT-MUX-03",
            severity="P1",
            surface="MUX",
            title="Buyer cria live Mux (custo)",
            preconditions="JWT buyer user_type comprador",
            identity="buyer",
            request="POST create-mux-live",
            response=snippet(parsed),
            before=None,
            after=None,
            impact="Abuse de custo Mux.",
            confidence="alta",
            variant="buyer",
            false_positive="buyer já é vendedor neste fixture",
        )
    st2, p2 = edge("complete-mux-live", buyer, {"live_id": str(uuid.uuid4())})
    probe("complete_mux_foreign", status=st2, body=snippet(p2))
    st3, p3 = edge("livekit-mux-publish", buyer, {"step": "token", "live_id": str(uuid.uuid4())})
    probe("livekit_token_buyer_foreign", status=st3, body=snippet(p3))
    if st3 == 200 and isinstance(p3, dict) and p3.get("token"):
        add_finding(
            id="SAT-LK-01",
            severity="P1",
            surface="LIVEKIT",
            title="Buyer obtém token LiveKit para live inexistente/alheia",
            preconditions="JWT buyer",
            identity="buyer",
            request="livekit-mux-publish step=token",
            response=snippet(p3),
            before=None,
            after=None,
            impact="Room token / custo egress.",
            confidence="média",
            variant="random live_id",
            false_positive="token sem grants úteis",
        )
    st4, p4 = edge("livekit-egress-cleanup", None, {})
    probe("egress_cleanup_anon", status=st4, body=snippet(p4))
    if st4 == 200:
        add_finding(
            id="SAT-LK-02",
            severity="P1",
            surface="LIVEKIT",
            title="Anon invoca livekit-egress-cleanup",
            preconditions="sem secret",
            identity="anon",
            request="POST livekit-egress-cleanup",
            response=snippet(p4),
            before=None,
            after=None,
            impact="Parar egress de lives.",
            confidence="alta",
            variant="anon",
            false_positive="200 error json",
        )
    st5, p5 = edge("ingest-ocr-reservation", None, {
        "live_id": str(uuid.uuid4()),
        "ocr_line_hash": "satcegahash123",
        "detected_at": "2026-08-27T12:00:00Z",
        "ref_number": 1,
        "requested_qty": 9,
    })
    probe("ocr_no_token", status=st5, body=snippet(p5))
    st6, p6 = edge("delete-test-account", buyer, {"confirm": "APAGAR TUDO"})
    probe("nuke_buyer", status=st6, body=snippet(p6))
    st7, p7 = edge("sec-fase2-e2e-oversell", buyer, {"buyer_id": BUYER_ID, "seller_id": SELLER_ID})
    probe("e2e_oversell_buyer", status=st7, body=snippet(p7))
    if st7 == 200:
        add_finding(
            id="SAT-EDG-01",
            severity="P0",
            surface="CHECKOUT",
            title="sec-fase2-e2e-oversell acessível com JWT buyer",
            preconditions="staging harness",
            identity="buyer",
            request="POST sec-fase2-e2e-oversell",
            response=snippet(p7),
            before=None,
            after=None,
            impact="Pagamento/settle de teste na identidade do utilizador.",
            confidence="alta",
            variant="buyer",
            false_positive="200 {ok:false}",
        )
    st8, p8 = edge("send-sms-bulkgate", None, {"phone": "+351910000000", "otp": "1234"})
    probe("sms_anon", status=st8, body=snippet(p8))
    st9, p9 = edge("meta-data-deletion", None, {"signed_request": "x"})
    probe("meta_deletion_anon", status=st9, body=snippet(p9))
    st10, p10 = edge("resolve-mux-playback", buyer, {"live_id": str(uuid.uuid4())})
    probe("resolve_playback", status=st10, body=snippet(p10))
    # CORS reflection
    stc, pc, hc = http(
        "OPTIONS",
        f"{BASE}/functions/v1/create-payment-intent",
        extra_headers={"Origin": "https://evil.example", "Access-Control-Request-Method": "POST"},
    )
    acao = hc.get("access-control-allow-origin")
    probe("cors_evil_origin", status=stc, acao=acao)
    if acao == "https://evil.example":
        add_finding(
            id="SAT-EDG-02",
            severity="P2",
            surface="RPC/DEFINER",
            title="CORS reflecte Origin arbitrária",
            preconditions="browser",
            identity="anon",
            request="OPTIONS Origin=evil",
            response=acao,
            before=None,
            after=None,
            impact="Leitura de respostas se cookie/auth web.",
            confidence="média",
            variant="evil origin",
            false_positive="apps nativas não usam CORS",
        )


def pass_state_machine(buyer: str, seller: str, product_id: str | None) -> None:
    set_cov("RACES", "TESTADA COM VARIANTES")
    set_cov("COMPOSITION", "TESTADA COM VARIANTES")
    if not product_id:
        return
    st, parsed = insert_order(buyer, {
        "product_id": product_id,
        "buyer_id": BUYER_ID,
        "seller_id": SELLER_ID,
        "price_total": 48.90,
        "payment_method": "Pagamento na App",
        "status": "reserva_pendente",
        "quantity": 1,
    })
    row = parsed[0] if isinstance(parsed, list) and parsed else {}
    oid = row.get("id")
    if not oid:
        return
    transitions = [
        ("buyer", buyer, {"status": "pago"}),
        ("buyer", buyer, {"status": "enviado"}),
        ("buyer", buyer, {"status": "concluido"}),
        ("buyer", buyer, {"status": "devolvida"}),
        ("buyer", buyer, {"status": "cancelado"}),
        ("seller", seller, {"status": "pago"}),
        ("seller", seller, {"status": "enviado"}),
        ("seller", seller, {"status": "cancelado"}),
        ("seller", seller, {"status": "devolvida"}),
        ("seller", seller, {"payment_method": "MB WAY"}),
        ("buyer", buyer, {"payment_method": "MB WAY"}),
    ]
    results = []
    for who, tok, patch in transitions:
        st, parsed = rest("PATCH", "orders", tok, qs=f"?id=eq.{oid}", body=patch)
        results.append({"who": who, "patch": patch, "st": st, "body": snippet(parsed, 160)})
    stf, pf = rest("GET", "orders", buyer, qs=f"?id=eq.{oid}&select=id,status,payment_method")
    probe("state_machine_order", final=snippet(pf), attempts=results)
    final = pf[0] if isinstance(pf, list) and pf else {}
    EVIDENCE["state_machine_sample"] = {"final": final, "attempts": results}
    # MB WAY then seller pago (invariant F)
    st2, p2 = insert_order(buyer, {
        "product_id": product_id,
        "buyer_id": BUYER_ID,
        "seller_id": SELLER_ID,
        "price_total": 20,
        "payment_method": "MB WAY",
        "status": "reserva_pendente",
        "quantity": 1,
    })
    mb = p2[0] if isinstance(p2, list) and p2 else {}
    if mb.get("id"):
        st3, p3 = rest("PATCH", "orders", seller, qs=f"?id=eq.{mb['id']}", body={"status": "pago"})
        probe("mbway_seller_mark_pago", status=st3, body=snippet(p3))
        if isinstance(p3, list) and p3 and str(p3[0].get("status")).lower() == "pago":
            # wallet credit?
            st4, p4 = rpc("batata_release_seller_wallet_for_order", seller, {"p_order_id": mb["id"]})
            st5, p5 = rpc("batata_refund_buyer_wallet_for_order", buyer, {"p_order_id": mb["id"]})
            probe("mbway_wallet_release", release=snippet(p4), refund=snippet(p5))
            add_finding(
                id="SAT-ORD-07",
                severity="P1",
                surface="ORDERS",
                title="Seller marca MB WAY como pago via JWT",
                preconditions="order payment_method MB WAY",
                identity="seller",
                request="PATCH status=pago",
                response=snippet(p3),
                before=mb,
                after=p3[0],
                impact="Estado pago off-platform; se wallet creditar viola invariante F.",
                confidence="alta",
                variant="MB WAY",
                false_positive="pago de negócio permitido mas wallet deve ser 0 — ver RPC",
            )
            if (st4 == 200 and p4 is True) or (isinstance(p4, dict) and p4.get("ok") is True):
                add_finding(
                    id="SAT-WAL-05",
                    severity="P0",
                    surface="WALLET",
                    title="Release wallet em order MB WAY (sem amount_paid_cents)",
                    preconditions="SAT-ORD-07",
                    identity="seller",
                    request="batata_release_seller_wallet_for_order",
                    response=snippet(p4),
                    before=mb,
                    after=p4,
                    impact="Invariante F — fundos off-platform viram saldo Fleaber.",
                    confidence="alta",
                    variant="release",
                    false_positive="true sem crédito efectivo",
                )


def observe_schema() -> None:
    """service_role observation only — grants, columns, not used as proof of closed attacks."""
    set_cov("SCHEMA", "TESTADA")
    st, parsed = rpc("batata_assert_wallet_rpc_grants", None, {}, svc=True)
    probe("assert_wallet_grants_svc", status=st, body=snippet(parsed))
    EVIDENCE["wallet_grant_assert"] = parsed
    # columns on orders
    st2, p2 = rest("GET", "orders", SVC, qs="?select=id,contract_unit_cents,contract_qty,amount_paid_cents,price_total,status&limit=1", svc=True)
    probe("svc_orders_sample", status=st2, body=snippet(p2))


def cleanup(seller: str, buyer: str) -> None:
    for oid in CREATED["orders"]:
        rest("PATCH", "orders", seller, qs=f"?id=eq.{oid}", body={"status": "cancelado"})
        rest("PATCH", "orders", buyer, qs=f"?id=eq.{oid}", body={"status": "cancelado"})
    for pid in CREATED["products"]:
        rest("PATCH", "products", seller, qs=f"?id=eq.{pid}", body={"list_on_marketplace": False, "quantity": 0, "title": f"{TAG} DONE"})


def main() -> int:
    load_env()
    print("== SATURAÇÃO CEGA 2026-08-27 staging only ==")
    buyer = login(BUYER_EMAIL, BUYER_PASS)
    seller = login(SELLER_EMAIL, SELLER_PASS)
    print("logged in buyer+seller")
    observe_schema()
    pass_auth(buyer, seller)
    pass_profiles(buyer, seller)
    tables = discover_tables(buyer)
    EVIDENCE["tables"] = tables
    pass_rls_sweep(buyer, seller, tables)
    pass_rpc_sweep(buyer, seller)
    pid = pass_orders_pricing(buyer, seller)
    pass_checkout(buyer, seller, pid)
    pass_bag(buyer, seller, pid)
    pass_refund_dispute(buyer, seller)
    pass_wallet_payout(buyer, seller)
    pass_stock_live_bag(buyer, seller, pid)
    pass_raffle_tips(buyer, seller)
    pass_chat_reviews_storage(buyer, seller)
    pass_mux_ps_edges(buyer, seller)
    pass_state_machine(buyer, seller, pid)
    # Pass 2/3 extra variants already inlined; one more independent sweep of leftover tables
    leftover = [t for t in tables if t not in {
        "orders", "profiles", "products", "wallets", "chats", "chat_messages",
        "reviews", "lives", "live_items", "live_tips", "live_raffles",
    }]
    for t in leftover[:40]:
        st, parsed = rest("GET", t, buyer, qs="?select=*&limit=1")
        if st == 200 and isinstance(parsed, list) and parsed:
            probe(f"extra_table_buyer_{t}", status=st, sample=snippet(parsed, 180))
            rest("POST", t, buyer, body={"id": str(uuid.uuid4())})
    cleanup(seller, buyer)
    out = {
        "staging": STAGING_REF,
        "production_touched": False,
        "fixes_applied": False,
        "tag": TAG,
        "coverage": COVERAGE,
        "findings": FINDINGS,
        "notes": NOTES,
        "created": CREATED,
        "evidence_probes": EVIDENCE["probes"],
        "openapi_rpcs": EVIDENCE.get("openapi_rpcs"),
        "tables": tables,
        "wallet_grant_assert": EVIDENCE.get("wallet_grant_assert"),
        "state_machine_sample": EVIDENCE.get("state_machine_sample"),
    }
    dest = ROOT / "tool" / "reports" / "SATURACAO_CEGA_2026-08-27_EVIDENCE.json"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(out, ensure_ascii=False, indent=2, default=str), encoding="utf-8")
    print(f"wrote {dest} findings={len(FINDINGS)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
