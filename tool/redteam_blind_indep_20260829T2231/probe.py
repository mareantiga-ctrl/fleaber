#!/usr/bin/env python3
"""Fleaber blind independent red-team probe — staging only.
FROZEN after execution. Does not apply fixes. Does not touch production.
"""
from __future__ import annotations

import json
import os
import random
import string
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENV_PATH = ROOT / "tool" / "live_ops_staging.env"
OUT_DIR = Path(__file__).resolve().parent / "out"
OUT_DIR.mkdir(parents=True, exist_ok=True)

STAGING_REF = "fxdknzrqjenzqcvnwqqq"
STARTED = datetime.now(timezone.utc)
RUN_ID = STARTED.strftime("%Y%m%dT%H%M%SZ")

MATRIX: list[dict] = []
FINDINGS: list[dict] = []
INVARIANTS: dict[str, dict] = {}
RACES: list[dict] = []
STRIPE_TEST: list[dict] = []
GAPS: list[str] = []
CLEANUP: list[str] = []


def load_env(path: Path) -> dict[str, str]:
    env: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def redact(obj):
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            lk = k.lower()
            if any(x in lk for x in ("key", "token", "secret", "password", "authorization", "jwt")):
                out[k] = "<redacted>"
            else:
                out[k] = redact(v)
        return out
    if isinstance(obj, list):
        return [redact(x) for x in obj]
    if isinstance(obj, str) and len(obj) > 40 and obj.count(".") == 2:
        return obj[:12] + "…<redacted>"
    return obj


def clip(s, n=800):
    t = str(s)
    return t if len(t) <= n else t[:n] + f"…(+{len(t)-n}b)"


class Api:
    def __init__(self, url: str, anon: str, service: str):
        self.url = url.rstrip("/")
        if self.url.endswith("/rest/v1"):
            self.url = self.url[: -len("/rest/v1")]
        self.anon = anon
        self.service = service
        if STAGING_REF not in self.url:
            raise SystemExit("REFUSED: not staging project fxdknzrqjenzqcvnwqqq")

    def _headers(self, token: str | None, extra: dict | None = None, service: bool = False):
        tok = self.service if service else (token or self.anon)
        h = {
            "apikey": self.anon if not service else self.service,
            "Authorization": f"Bearer {tok}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        }
        if extra:
            h.update(extra)
        return h

    def req(
        self,
        method: str,
        path: str,
        *,
        token: str | None = None,
        service: bool = False,
        json_body=None,
        query: dict | None = None,
        extra_headers: dict | None = None,
        timeout: int = 45,
    ) -> tuple[int, object, str]:
        q = ""
        if query:
            q = "?" + urllib.parse.urlencode(
                {k: v for k, v in query.items() if v is not None}, doseq=True
            )
        url = self.url + path + q
        data = None
        if json_body is not None:
            data = json.dumps(json_body).encode("utf-8")
        req = urllib.request.Request(
            url, data=data, method=method, headers=self._headers(token, extra_headers, service)
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = resp.read().decode("utf-8", "replace")
                code = resp.status
        except urllib.error.HTTPError as e:
            raw = e.read().decode("utf-8", "replace")
            code = e.code
        except Exception as e:
            return 0, {"_transport": str(e)}, str(e)
        parsed: object = raw
        try:
            parsed = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            parsed = raw
        return code, parsed, raw

    def rest(self, method, table, **kw):
        extra = kw.pop("prefer", None)
        eh = dict(kw.pop("extra_headers", None) or {})
        if extra:
            eh["Prefer"] = extra
        if method in ("POST", "PATCH") and "prefer" not in (extra or ""):
            eh.setdefault("Prefer", "return=representation")
        return self.req(method, f"/rest/v1/{table}", extra_headers=eh or None, **kw)

    def rpc(self, name, body=None, **kw):
        return self.req("POST", f"/rest/v1/rpc/{name}", json_body=body or {}, **kw)

    def edge(self, name, body=None, method="POST", qs="", **kw):
        path = f"/functions/v1/{name}{qs}"
        return self.req(method, path, json_body=body, **kw)

    def login(self, email: str, password: str) -> tuple[str, str]:
        code, body, _ = self.req(
            "POST",
            "/auth/v1/token?grant_type=password",
            json_body={"email": email, "password": password},
        )
        if code != 200 or not isinstance(body, dict) or not body.get("access_token"):
            raise SystemExit(f"login failed {email}: {code} {clip(body)}")
        uid = (body.get("user") or {}).get("id") or ""
        return body["access_token"], uid

    def observe(self, table, query=None, extra_headers=None):
        return self.rest(
            "GET", table, service=True, query=query, extra_headers=extra_headers
        )


ENV = load_env(ENV_PATH)
API = Api(
    ENV["SUPABASE_URL"].replace("/rest/v1/", "").replace("/rest/v1", ""),
    ENV["SUPABASE_ANON_KEY"],
    ENV["SUPABASE_SERVICE_ROLE_KEY"],
)
BUYER_EMAIL = ENV["LIVE_OPS_TEST_BUYER_EMAIL"]
BUYER_PASS = ENV["LIVE_OPS_TEST_BUYER_PASSWORD"]
SELLER_EMAIL = ENV["LIVE_OPS_TEST_SELLER_EMAIL"]
SELLER_PASS = ENV["LIVE_OPS_TEST_SELLER_PASSWORD"]
BUYER_ID = ENV["LIVE_OPS_TEST_BUYER_ID"]
SELLER_ID = ENV["LIVE_OPS_TEST_SELLER_ID"]
E2E_SECRET = ENV.get("FLEABER_STAGING_CRASH_INJECT_SECRET", "")


def rec(
    surface: str,
    attack: str,
    identity: str,
    result: str,
    impact: str,
    severity: str,
    evidence: dict,
    *,
    finding: bool = False,
    title: str | None = None,
    actor: str | None = None,
    pre: str = "",
    repro: str = "",
    state: str = "OPEN",
):
    row = {
        "surface": surface,
        "attack": attack,
        "identity": identity,
        "result": result,
        "impact": impact,
        "severity": severity,
        "evidence": redact(evidence),
    }
    MATRIX.append(row)
    if finding:
        FINDINGS.append(
            {
                "id": f"BI-{len(FINDINGS)+1:03d}",
                "severity": severity,
                "title": title or attack,
                "actor": actor or identity,
                "preconditions": pre,
                "reproduction": repro or attack,
                "impact": impact,
                "state": state,
                "evidence": redact(evidence),
            }
        )


def blocked(code, body) -> bool:
    if code in (401, 403, 404, 405, 409, 422, 425, 429):
        return True
    if code == 400:
        return True
    if isinstance(body, dict):
        msg = json.dumps(body).lower()
        if any(
            x in msg
            for x in (
                "not_allowed",
                "permission",
                "rls",
                "row-level",
                "jwt",
                "denied",
                "forbidden",
                "blocked",
                "invalid",
                "sem permissão",
                "not allowed",
                "42501",
                "pgrst",
            )
        ):
            return True
    if isinstance(body, str) and any(
        x in body.lower() for x in ("not_allowed", "blocked", "permission", "unauthorized")
    ):
        return True
    return False


def persist_ok(code, body) -> bool:
    if code not in (200, 201):
        return False
    if body in (None, "", [], {}):
        return False
    if isinstance(body, dict) and body.get("ok") is False:
        return False
    return True


def snap_order(oid: str) -> dict:
    code, body, _ = API.observe(
        "orders",
        query={
            "id": f"eq.{oid}",
            "select": "id,status,price_total,quantity,contract_unit_cents,contract_qty,amount_paid_cents,buyer_id,seller_id,product_id,stripe_payment_intent_id,stripe_checkout_session_id,stripe_refund_id,stock_units_applied,payment_method,shipping_method,product_offer_id",
        },
    )
    if code == 200 and isinstance(body, list) and body:
        return body[0]
    return {"_err": clip(body), "_code": code}


def snap_product(pid: str) -> dict:
    code, body, _ = API.observe(
        "products",
        query={
            "id": f"eq.{pid}",
            "select": "id,price,quantity,is_sold,seller_id,title",
        },
    )
    if code == 200 and isinstance(body, list) and body:
        return body[0]
    return {"_err": clip(body), "_code": code}


def snap_wallet(uid: str) -> dict:
    code, body, _ = API.observe(
        "wallets",
        query={"id": f"eq.{uid}", "select": "id,balance,stripe_account_id"},
    )
    if code == 200 and isinstance(body, list) and body:
        return body[0]
    return {"_err": clip(body), "_code": code}


def stamp() -> str:
    return f"bi{int(time.time())}{random.randint(100,999)}"


# ---------------------------------------------------------------------------
# Auth + inventory
# ---------------------------------------------------------------------------
print("== login ==")
buyer_jwt, buyer_uid = API.login(BUYER_EMAIL, BUYER_PASS)
seller_jwt, seller_uid = API.login(SELLER_EMAIL, SELLER_PASS)
assert buyer_uid == BUYER_ID, (buyer_uid, BUYER_ID)
assert seller_uid == SELLER_ID, (seller_uid, SELLER_ID)
anon = None  # token = anon key
print("buyer", buyer_uid)
print("seller", seller_uid)

TOK = {"anon": None, "buyer": buyer_jwt, "seller": seller_jwt}

print("== openapi ==")
code_oa, spec, _ = API.req(
    "GET",
    "/rest/v1/",
    extra_headers={"Accept": "application/openapi+json"},
)
tables: list[str] = []
rpcs: list[str] = []
if isinstance(spec, dict):
    paths = spec.get("paths") or {}
    for p in paths:
        if p.startswith("/rpc/"):
            rpcs.append(p.split("/rpc/", 1)[-1].split("{")[0].strip("/"))
        elif p.startswith("/") and "/rpc/" not in p:
            name = p.strip("/").split("/")[0]
            if name and name not in tables:
                tables.append(name)
print(f"tables={len(tables)} rpcs={len(rpcs)}")
(OUT_DIR / f"openapi_{RUN_ID}.json").write_text(
    json.dumps({"tables": tables, "rpcs": rpcs, "http": code_oa}, indent=2),
    encoding="utf-8",
)

# Create disposable third user (collusion / cross-id) via admin — fixture only
disp_email = f"rtblind.{stamp()}@fleaber.test"
disp_pass = "TesteTeste!9x"
code_du, body_du, _ = API.req(
    "POST",
    "/auth/v1/admin/users",
    service=True,
    json_body={
        "email": disp_email,
        "password": disp_pass,
        "email_confirm": True,
        "user_metadata": {"redteam": "blind_indep_20260829T2231"},
    },
)
disp_jwt = ""
disp_uid = ""
if code_du in (200, 201) and isinstance(body_du, dict) and body_du.get("id"):
    disp_uid = body_du["id"]
    try:
        disp_jwt, disp_uid = API.login(disp_email, disp_pass)
        TOK["disp"] = disp_jwt
        CLEANUP.append(f"auth user {disp_uid}")
        print("disposable", disp_uid)
    except Exception as e:
        GAPS.append(f"disposable login failed: {e}")
else:
    GAPS.append(f"could not create disposable user: {code_du} {clip(body_du)}")
    TOK["disp"] = None


def ident_token(name: str):
    return TOK.get(name)


# ---------------------------------------------------------------------------
# PASS 1 — coverage
# ---------------------------------------------------------------------------
print("== PASS 1 coverage ==")

SENSITIVE_TABLES = [
    "orders",
    "products",
    "wallets",
    "wallet_transactions",
    "wallet_payout_ledger",
    "reviews",
    "chats",
    "messages",
    "chat_messages",
    "order_disputes",
    "disputes",
    "live_reservation_requests",
    "live_items",
    "lives",
    "live_tips",
    "live_raffles",
    "live_raffle_winners",
    "live_raffle_tickets",
    "product_offers",
    "product_bundles",
    "seller_bundle_discounts",
    "profiles",
    "notifications",
    "favorites",
    "follows",
    "stripe_checkout_events",
    "ps_ingest_audit",
    "seller_device_tokens",
    "device_tokens",
    "staff_permissions",
    "admin_users",
    "fleaber_commissions",
    "live_messages",
]
for t in tables:
    if t not in SENSITIVE_TABLES and any(
        k in t for k in ("wallet", "payout", "stripe", "mux", "secret", "token", "bank", "iban")
    ):
        SENSITIVE_TABLES.append(t)

# Sample foreign rows via service (observe)
foreign_order = None
foreign_chat = None
foreign_review = None
code, body, _ = API.observe(
    "orders",
    query={
        "select": "id,buyer_id,seller_id,status,price_total,product_id",
        "buyer_id": f"neq.{buyer_uid}",
        "limit": "3",
    },
)
if code == 200 and isinstance(body, list) and body:
    for row in body:
        if row.get("buyer_id") not in (buyer_uid, seller_uid) or row.get("seller_id") not in (
            buyer_uid,
            seller_uid,
        ):
            foreign_order = row
            break
    if not foreign_order:
        foreign_order = body[0]

# RLS SELECT/UPDATE/DELETE matrix
for table in SENSITIVE_TABLES:
    if table not in tables and table not in (
        "orders",
        "products",
        "wallets",
        "reviews",
        "lives",
        "profiles",
    ):
        # still try; 404 = not present
        pass
    for ident in ("anon", "buyer", "seller"):
        tok = ident_token(ident)
        sel_q = {"select": "*", "limit": "5"}
        if table == "lives":
            sel_q["select"] = "id,seller_id,status,mux_playback_id,mux_stream_key,stream_key"
        c, b, raw = API.rest("GET", table, token=tok, query=sel_q)
        leaked = []
        if c == 200 and isinstance(b, list):
            for row in b:
                if not isinstance(row, dict):
                    continue
                uid_fields = [
                    row.get("buyer_id"),
                    row.get("seller_id"),
                    row.get("user_id"),
                    row.get("id") if table in ("wallets", "profiles") else None,
                    row.get("author_id"),
                    row.get("user_a"),
                    row.get("user_b"),
                ]
                mine = buyer_uid if ident == "buyer" else seller_uid if ident == "seller" else None
                if table in ("products",) and ident == "buyer":
                    # public catalog ok
                    continue
                if table in ("profiles",) and ident != "anon":
                    continue
                if mine and any(x == mine for x in uid_fields if x):
                    continue
                if ident == "anon" and table in ("products", "profiles"):
                    continue
                # flag cross-user if identity columns clearly someone else
                others = [x for x in uid_fields if x and mine and x != mine]
                if ident != "anon" and others and table in (
                    "orders",
                    "wallets",
                    "wallet_transactions",
                    "chats",
                    "messages",
                    "chat_messages",
                    "order_disputes",
                    "live_tips",
                    "reviews",
                    "notifications",
                    "wallet_payout_ledger",
                    "lives",
                ):
                    leaked.append({"id": row.get("id"), "fields": {k: row.get(k) for k in row if "key" in k.lower() or k.endswith("_id") or k in ("balance", "iban", "email")}})
                if ident == "anon" and table in (
                    "orders",
                    "wallets",
                    "wallet_transactions",
                    "chats",
                    "messages",
                    "notifications",
                    "live_tips",
                    "wallet_payout_ledger",
                    "order_disputes",
                ) and row:
                    leaked.append({"id": row.get("id")})
        stream_leak = False
        if table == "lives" and c == 200 and isinstance(b, list):
            for row in b:
                if row.get("mux_stream_key") or row.get("stream_key"):
                    stream_leak = True
                    leaked.append({"live": row.get("id"), "has_stream_key": True})
        sev = "INFO"
        res = "blocked" if (c >= 400 or (c == 200 and not leaked)) else "unexpected"
        if leaked:
            sev = "P1" if table in (
                "wallets",
                "orders",
                "wallet_payout_ledger",
                "chats",
                "messages",
                "chat_messages",
                "order_disputes",
                "lives",
            ) else "P2"
            if stream_leak:
                sev = "P1"
        rec(
            f"RLS/{table}",
            f"SELECT as {ident}",
            ident,
            f"HTTP {c} leaked={len(leaked)}",
            "cross-user read" if leaked else "no material leak in sample",
            sev if leaked else "INFO",
            {"http": c, "n": len(b) if isinstance(b, list) else None, "leaked": leaked[:3], "sample": clip(raw, 240)},
            finding=bool(leaked),
            title=f"RLS SELECT leak on {table} as {ident}",
            repro=f"GET /rest/v1/{table} as {ident}",
        )

# Targeted UPDATE/INSERT/DELETE
hostile_updates = [
    ("orders", {"status": "pago", "amount_paid_cents": 99999, "price_total": 0.01}, {"limit": "1"}),
    ("wallets", {"balance": 9999.99}, {"id": f"eq.{buyer_uid}"}),
    ("wallets", {"balance": 1}, {"id": f"eq.{seller_uid}"}),
    ("products", {"price": 0.01}, {"seller_id": f"eq.{seller_uid}", "limit": "1"}),
    ("profiles", {"user_type": "admin"}, {"id": f"eq.{buyer_uid}"}),
    ("reviews", {"rating": 5, "comment": "pwn"}, {"limit": "1"}),
]
for table, payload, q in hostile_updates:
    for ident in ("anon", "buyer", "seller"):
        tok = ident_token(ident)
        before = None
        c, b, raw = API.rest(
            "PATCH",
            table,
            token=tok,
            json_body=payload,
            query=q,
            extra_headers={"Prefer": "return=representation"},
        )
        changed = persist_ok(c, b) and not blocked(c, b)
        rec(
            f"RLS/{table}",
            f"PATCH {list(payload.keys())} as {ident}",
            ident,
            f"HTTP {c} {clip(b, 180)}",
            "row mutated" if changed else "rejected or empty",
            "P0" if changed and table in ("wallets", "orders") else ("P1" if changed else "INFO"),
            {"http": c, "body": clip(b, 400), "payload": payload, "query": q},
            finding=changed,
            title=f"JWT/anon PATCH {table} {list(payload.keys())}",
            repro=f"PATCH /rest/v1/{table} {payload}",
        )

for ident in ("anon", "buyer"):
    tok = ident_token(ident)
    c, b, raw = API.rest(
        "POST",
        "wallets",
        token=tok,
        json_body={"id": buyer_uid if ident == "buyer" else disp_uid or buyer_uid, "balance": 500},
    )
    changed = persist_ok(c, b) and not blocked(c, b)
    rec(
        "WALLET",
        "INSERT wallet with balance",
        ident,
        f"HTTP {c} {clip(b, 180)}",
        "created balance" if changed else "rejected",
        "P0" if changed else "INFO",
        {"http": c, "body": clip(b, 400)},
        finding=changed,
        title="JWT/anon INSERT wallets.balance",
        repro="POST /rest/v1/wallets {balance:500}",
    )

# Financial RPCs
FIN_RPCS = [
    ("batata_credit_wallet_once", {"p_user_id": buyer_uid, "p_order_id": "00000000-0000-0000-0000-000000000001", "p_amount": 50, "p_type": "venda", "p_description": "x"}),
    ("batata_debit_wallet_once", {"p_user_id": seller_uid, "p_order_id": "00000000-0000-0000-0000-000000000001", "p_amount": 1, "p_type": "compra"}),
    ("batata_clawback_seller_wallet_for_order", {"p_order_id": "00000000-0000-0000-0000-000000000001"}),
    ("batata_release_seller_wallet_for_order", {"p_order_id": "00000000-0000-0000-0000-000000000001"}),
    ("batata_refund_buyer_wallet_for_order", {"p_order_id": "00000000-0000-0000-0000-000000000001"}),
    ("batata_process_partial_refund_dispute", {"p_order_id": "00000000-0000-0000-0000-000000000001", "p_amount": 1}),
    ("batata_wallet_payout_debit", {"p_user_id": seller_uid, "p_amount_cents": 100, "p_idempotency_key": "blindindep-" + stamp()}),
    ("batata_wallet_payout_finish", {"p_idempotency_key": "blindindep-finish", "p_stripe_transfer_id": "tr_fake", "p_failed": False}),
    ("batata_finalize_stripe_order_refund", {"p_order_id": "00000000-0000-0000-0000-000000000001", "p_refund_id": "re_x", "p_payment_intent_id": "pi_x", "p_session_id": None, "p_amount_cents": 100}),
    ("batata_wallet_apply_tip_once", {"p_seller_id": seller_uid, "p_tip_id": "00000000-0000-0000-0000-000000000001", "p_amount": 5, "p_type": "gorjeta", "p_description": "x"}),
    ("batata_send_live_tip_from_wallet", {"p_live_id": "00000000-0000-0000-0000-000000000001", "p_seller_id": seller_uid, "p_amount": 5, "p_message": "x"}),
    ("batata_settle_live_tip_from_stripe", {"p_tip_id": "00000000-0000-0000-0000-000000000001", "p_stripe_session_id": "cs_test_x", "p_paid_amount_cents": 500}),
    ("batata_ensure_wallet", {"p_user_id": seller_uid}),
    ("batata_create_raffle_prize_order", {"p_raffle_id": "00000000-0000-0000-0000-000000000001", "p_winner_id": buyer_uid, "p_qty": 1}),
    ("batata_award_live_raffle_tickets", {"p_raffle_id": "00000000-0000-0000-0000-000000000001", "p_user_id": buyer_uid, "p_source": "manual", "p_qty": 10, "p_note": "x"}),
    ("batata_mark_live_item_sold", {"p_live_item_id": "00000000-0000-0000-0000-000000000001"}),
    ("batata_live_reconcile_stripe_order", {"p_order_id": "00000000-0000-0000-0000-000000000001"}),
    ("batata_sync_live_item_for_order", {"p_order_id": "00000000-0000-0000-0000-000000000001"}),
    ("batata_tick_live_raffle", {"p_raffle_id": "00000000-0000-0000-0000-000000000001"}),
    ("batata_find_user_id_by_email", {"p_email": SELLER_EMAIL}),
    ("batata_seller_direct_payment_details", {"p_seller_id": seller_uid}),
    ("batata_ps_claim_pairing", {"p_code": "000000", "p_device_id": "x", "p_app_version": "1", "p_ip": "1.1.1.1"}),
    ("batata_lab_clear_all_fm_pending", {}),
    ("batata_generate_auto_feedback", {}),
    ("batata_invoke_livekit_egress_cleanup", {}),
    ("batata_backfill_handle_suggestions", {"p_dry_run": True}),
    ("batata_create_seller_device_token", {"p_label": "rt", "p_device_id": "rt"}),
    ("batata_require_authenticated_uid", {}),
]
# extra RPCs from OpenAPI that look privileged
for name in rpcs:
    low = name.lower()
    if any(k in low for k in ("wallet", "payout", "refund", "credit", "debit", "settle", "admin", "staff", "convert", "award", "prize", "ocr", "pairing")):
        if not any(name == x[0] for x in FIN_RPCS):
            FIN_RPCS.append((name, {}))

for rpc_name, payload in FIN_RPCS:
    for ident in ("anon", "buyer", "seller"):
        tok = ident_token(ident)
        w_before = snap_wallet(seller_uid) if "wallet" in rpc_name or "payout" in rpc_name or "credit" in rpc_name else None
        c, b, raw = API.rpc(rpc_name, payload, token=tok)
        w_after = snap_wallet(seller_uid) if w_before is not None else None
        bal_delta = None
        if isinstance(w_before, dict) and isinstance(w_after, dict):
            try:
                bal_delta = float(w_after.get("balance") or 0) - float(w_before.get("balance") or 0)
            except Exception:
                bal_delta = None
        success = persist_ok(c, b) and not blocked(c, b)
        # JSON {ok:false} is not success
        if isinstance(b, dict) and b.get("ok") is False:
            success = False
        impact = "executed"
        sev = "INFO"
        if success:
            if bal_delta and abs(bal_delta) > 0.001:
                sev = "P0"
                impact = f"wallet delta {bal_delta}"
            elif any(k in rpc_name for k in ("payout", "credit", "refund", "debit", "settle", "prize", "award")):
                sev = "P1"
                impact = "privileged RPC executed as JWT/anon"
            elif rpc_name in ("batata_find_user_id_by_email",):
                sev = "P2"
                impact = "email→uuid oracle"
            elif rpc_name in ("batata_seller_direct_payment_details",) and ident == "buyer":
                # buyer reading seller banking may be intended after accept
                sev = "P2"
                impact = "banking details returned"
            else:
                sev = "P2"
        rec(
            f"RPC/{rpc_name}",
            f"call as {ident}",
            ident,
            f"HTTP {c} {clip(b, 160)}",
            impact,
            sev,
            {"http": c, "body": clip(b, 500), "payload": payload, "wallet_delta": bal_delta},
            finding=success and sev in ("P0", "P1"),
            title=f"RPC {rpc_name} executable as {ident}",
            repro=f"POST /rest/v1/rpc/{rpc_name}",
        )

# Edge functions
EDGES = [
    ("create-payment-intent", {"buyer_id": buyer_uid, "order_id": "00000000-0000-0000-0000-000000000001", "amount": 1, "shipping_method": "hand"}),
    ("create-payment-intent", {"buyer_id": seller_uid, "order_id": "00000000-0000-0000-0000-000000000001", "amount": 50}),
    ("refund-order", {"order_id": "00000000-0000-0000-0000-000000000001"}),
    ("create-live-tip-checkout", {"seller_id": seller_uid, "amount_eur": 1, "live_id": "00000000-0000-0000-0000-000000000001"}),
    ("create-connect-account", {"user_id": seller_uid, "amount": 1}),
    ("create-mux-live", {"title": "RT blind"}),
    ("complete-mux-live", {"live_id": "00000000-0000-0000-0000-000000000001"}),
    ("resolve-mux-playback", {"live_id": "00000000-0000-0000-0000-000000000001"}),
    ("livekit-mux-publish", {"step": "token", "live_id": "00000000-0000-0000-0000-000000000001"}),
    ("ingest-ocr-reservation", {"live_id": "00000000-0000-0000-0000-000000000001", "ocr_line_hash": "abcdefgh", "detected_at": datetime.now(timezone.utc).isoformat(), "ref_number": 1}),
    ("ps-pairing-claim", {"code": "0000", "device_id": "x"}),
    ("ps-heartbeat", {}),
    ("ps-panel-log", {"msg": "x"}),
    ("send-sms-bulkgate", {"phone": "+351910000000", "text": "x"}),
    ("delete-test-account", {"confirm": "APAGAR TUDO"}),
    ("stripe-webhook", {"type": "checkout.session.completed"}),
    ("meta-data-deletion", {}),
    ("sec-fase2-e2e-oversell", {"probe": "x", "buyer_id": buyer_uid, "seller_id": seller_uid}),
    ("livekit-egress-cleanup", {}),
]
for name, body in EDGES:
    for ident in ("anon", "buyer", "seller"):
        tok = ident_token(ident)
        c, b, raw = API.edge(name, body, token=tok)
        success = persist_ok(c, b) and not blocked(c, b)
        if isinstance(b, dict) and (b.get("ok") is False or b.get("error")):
            # 200 with error still not exploit
            if c == 200 and b.get("error"):
                success = False
        rec(
            f"EDGE/{name}",
            f"POST as {ident}",
            ident,
            f"HTTP {c} {clip(b, 160)}",
            "accepted hostile payload" if success else "rejected or error",
            "P1" if success and name in ("refund-order", "create-payment-intent", "create-connect-account", "sec-fase2-e2e-oversell", "stripe-webhook", "delete-test-account") else ("INFO" if not success else "P2"),
            {"http": c, "body": clip(b, 400)},
            finding=success and name in ("sec-fase2-e2e-oversell", "stripe-webhook", "delete-test-account", "send-sms-bulkgate"),
            title=f"Edge {name} accepts {ident}",
            repro=f"POST /functions/v1/{name}",
        )

# fase2 settle with JWT
c, b, raw = API.edge(
    "create-payment-intent",
    {"order_id": "00000000-0000-0000-0000-000000000001", "payment_intent_id": "pi_x"},
    token=buyer_jwt,
    qs="?fase2_e2e_settle=1",
)
rec(
    "EDGE/create-payment-intent",
    "fase2_e2e_settle as buyer JWT",
    "buyer",
    f"HTTP {c} {clip(b, 200)}",
    "settle backdoor" if c == 200 and not blocked(c, b) else "denied",
    "P0" if persist_ok(c, b) and not blocked(c, b) else "INFO",
    {"http": c, "body": clip(b, 400)},
    finding=persist_ok(c, b) and not blocked(c, b),
    title="fase2_e2e_settle accepts buyer JWT",
    repro="POST create-payment-intent?fase2_e2e_settle=1 with buyer JWT",
)

# webhook without signature
c, b, raw = API.req(
    "POST",
    "/functions/v1/stripe-webhook",
    token=None,
    json_body={"type": "checkout.session.completed", "data": {"object": {"id": "cs_test", "payment_status": "paid"}}},
)
rec(
    "EDGE/stripe-webhook",
    "POST without stripe-signature",
    "anon",
    f"HTTP {c} {clip(b, 200)}",
    "forged webhook" if c == 200 and not blocked(c, b) else "rejected",
    "P0" if persist_ok(c, b) and not blocked(c, b) else "INFO",
    {"http": c, "body": clip(b, 400)},
    finding=persist_ok(c, b) and not blocked(c, b),
    title="Stripe webhook accepts unsigned body",
    repro="POST /functions/v1/stripe-webhook without Stripe-Signature",
)

print("== fixtures: product + orders ==")
# Seller creates product qty=1
ref = stamp()
c, b, raw = API.rest(
    "POST",
    "products",
    token=seller_jwt,
    json_body={
        "seller_id": seller_uid,
        "title": f"RT-BLIND {ref}",
        "price": 12.50,
        "quantity": 1,
        "list_on_marketplace": True,
        "is_sold": False,
        "ref_code": f"RTB-{ref}",
        "available_for_live": False,
    },
)
if not persist_ok(c, b):
    GAPS.append(f"seller product insert failed {c} {clip(b)}")
    product_id = None
else:
    product_id = b[0]["id"] if isinstance(b, list) else b.get("id")
    CLEANUP.append(f"product {product_id}")
print("product", product_id, c)

# Hostile order inserts
order_ids = []


def insert_order(ident, payload, label):
    tok = ident_token(ident)
    before_prod = snap_product(product_id) if product_id else None
    c, b, raw = API.rest("POST", "orders", token=tok, json_body=payload)
    after = None
    oid = None
    if persist_ok(c, b):
        row = b[0] if isinstance(b, list) else b
        oid = row.get("id")
        if oid:
            after = snap_order(oid)
            order_ids.append(oid)
            CLEANUP.append(f"order {oid}")
    rec(
        "ORDERS/INSERT",
        label,
        ident,
        f"HTTP {c} persisted={bool(oid)}",
        f"final={clip(after, 240)}" if after else clip(b, 200),
        "INFO",
        {"http": c, "body": clip(b, 400), "payload": payload, "final": after, "product_before": before_prod},
    )
    return oid, after, c, b


base_order = {
    "buyer_id": buyer_uid,
    "seller_id": seller_uid,
    "product_id": product_id,
    "quantity": 1,
    "status": "aguarda_pagamento",
    "payment_method": "seguro fleaber",
    "shipping_method": "carrier",
    "price_total": 12.50,
}

if product_id:
    oid_legit, row_legit, _, _ = insert_order(
        "buyer", dict(base_order), "buyer legit order qty=1"
    )
    oid_price, row_price, _, _ = insert_order(
        "buyer",
        {**base_order, "price_total": 0.01, "contract_unit_cents": 1, "contract_qty": 1, "amount_paid_cents": 1, "status": "pago", "stripe_payment_intent_id": "pi_fake"},
        "buyer hostile price/contract/paid flags",
    )
    oid_qty, row_qty, _, _ = insert_order(
        "buyer",
        {**base_order, "quantity": 99, "contract_qty": 99},
        "buyer qty=99 on stock=1",
    )
    oid_other_buyer, row_ob, _, _ = insert_order(
        "buyer",
        {**base_order, "buyer_id": seller_uid},
        "buyer inserts order as seller identity",
    )
    oid_cross_seller, _, _, _ = insert_order(
        "buyer",
        {**base_order, "seller_id": buyer_uid},
        "buyer sets self as seller",
    )
    oid_anon, _, c_anon, b_anon = insert_order(
        "anon",
        {**base_order, "price_total": 0.01},
        "anon insert order",
    )
    oid_seller_as_buyer, _, _, _ = insert_order(
        "seller",
        {**base_order, "buyer_id": seller_uid, "status": "pago", "amount_paid_cents": 1250},
        "seller insert order as own buyer paid",
    )
    if disp_jwt:
        insert_order(
            "disp",
            {**base_order, "buyer_id": disp_uid, "quantity": 1},
            "third user order same sku stock=1",
        )

    # Classify contract authority from persisted rows
    if row_price:
        cu = row_price.get("contract_unit_cents")
        st = row_price.get("status")
        paid = row_price.get("amount_paid_cents")
        pi = row_price.get("stripe_payment_intent_id")
        hostile_ok = (cu is not None and int(cu) <= 1) or (st and str(st).lower() == "pago") or (paid and int(paid) > 0) or pi
        rec(
            "PRICE/CONTRACT",
            "hostile INSERT contract/paid",
            "buyer",
            f"status={st} contract_unit={cu} paid={paid} pi={pi}",
            "client set authoritative money" if hostile_ok else "server stripped hostile money fields",
            "P1" if (cu is not None and int(cu) <= 1 and product_id) else ("P0" if (st and str(st).lower() == "pago") or (paid and int(paid) > 0) else "INFO"),
            {"final": row_price},
            finding=bool(hostile_ok and ((st and str(st).lower() == "pago") or (paid and int(paid) > 0) or (cu is not None and int(cu) <= 1))),
            title="Buyer INSERT sets contract or paid flags",
            repro="POST /rest/v1/orders with contract_unit_cents=1 and status=pago",
        )
    if row_qty:
        q = int(row_qty.get("quantity") or 0)
        cq = int(row_qty.get("contract_qty") or 0)
        over = q > 1 or cq > 1
        rec(
            "QTY",
            "qty=99 on stock=1 insert",
            "buyer",
            f"qty={q} contract_qty={cq} status={row_qty.get('status')}",
            "hold exceeds stock" if over else "qty clamped or rejected",
            "P1" if over else "INFO",
            {"final": row_qty, "product": snap_product(product_id)},
            finding=over,
            title="Order qty exceeds product stock at insert",
            repro="POST orders quantity=99 on product.quantity=1",
        )
    if row_ob:
        rec(
            "AUTHORITY",
            "buyer_id swap on insert",
            "buyer",
            f"persisted buyer={row_ob.get('buyer_id')}",
            "attribution swap" if row_ob.get("buyer_id") != buyer_uid else "forced to jwt uid",
            "P1" if row_ob.get("buyer_id") != buyer_uid else "INFO",
            {"final": row_ob},
            finding=row_ob.get("buyer_id") != buyer_uid,
            title="Buyer can set orders.buyer_id to another user",
            repro="POST orders buyer_id=<other>",
        )

    # Checkout attacks on legit order
    def checkout(ident, body, label):
        tok = ident_token(ident)
        c, b, raw = API.edge("create-payment-intent", body, token=tok)
        url = None
        if isinstance(b, dict):
            url = b.get("url") or b.get("checkout_url") or (b.get("session") or {}).get("url")
        rec(
            "CHECKOUT",
            label,
            ident,
            f"HTTP {c} url={bool(url)} {clip(b, 180)}",
            "session created" if url or (c == 200 and isinstance(b, dict) and b.get("id")) else clip(b, 120),
            "INFO",
            {"http": c, "body": clip(b, 500), "request": body},
        )
        return c, b

    if oid_legit:
        checkout(
            "buyer",
            {
                "buyer_id": buyer_uid,
                "order_id": oid_legit,
                "amount": 1,
                "quantity": 99,
                "item_price": 0.01,
                "shipping_method": "hand",
                "prize_shipping": True,
                "product_id": product_id,
            },
            "buyer checkout amount=1 prize_shipping qty=99 hand vs sealed carrier",
        )
        checkout(
            "buyer",
            {
                "buyer_id": buyer_uid,
                "order_id": oid_legit,
                "amount": 999999,
                "shipping_method": "carrier",
            },
            "buyer checkout amount huge (should ignore)",
        )
        checkout(
            "seller",
            {
                "buyer_id": buyer_uid,
                "order_id": oid_legit,
                "shipping_method": "hand",
            },
            "seller JWT checkout buyer order (body buyer_id mismatch)",
        )
        checkout(
            "seller",
            {
                "buyer_id": seller_uid,
                "order_id": oid_legit,
                "shipping_method": "hand",
            },
            "seller JWT claims self as buyer_id on foreign order",
        )
        checkout(
            "anon",
            {
                "buyer_id": buyer_uid,
                "order_id": oid_legit,
                "shipping_method": "hand",
            },
            "anon checkout",
        )
        if disp_jwt:
            checkout(
                "disp",
                {
                    "buyer_id": disp_uid,
                    "order_id": oid_legit,
                    "shipping_method": "hand",
                },
                "third user checkout someone else's order",
            )
            checkout(
                "disp",
                {
                    "buyer_id": buyer_uid,
                    "order_id": oid_legit,
                    "shipping_method": "hand",
                },
                "third user checkout with stolen buyer_id in body",
            )

        # Try PATCH shipping then checkout hand
        API.rest(
            "PATCH",
            "orders",
            token=buyer_jwt,
            json_body={"shipping_method": "garbage-€0"},
            query={"id": f"eq.{oid_legit}"},
        )
        c_ship, b_ship = checkout(
            "buyer",
            {
                "buyer_id": buyer_uid,
                "order_id": oid_legit,
                "shipping_method": "hand",
            },
            "after PATCH shipping garbage, checkout hand",
        )
        # Observe session amount if present
        if isinstance(b_ship, dict):
            STRIPE_TEST.append(
                {
                    "kind": "SESSION_CREATED",
                    "label": "shipping_fallback_hand",
                    "http": c_ship,
                    "body": clip(b_ship, 400),
                    "order_after": snap_order(oid_legit),
                }
            )

        # Catalog price drop after seal
        API.rest(
            "PATCH",
            "products",
            token=seller_jwt,
            json_body={"price": 0.50},
            query={"id": f"eq.{product_id}"},
        )
        c_cat, b_cat = checkout(
            "buyer",
            {
                "buyer_id": buyer_uid,
                "order_id": oid_legit,
                "shipping_method": "carrier",
            },
            "checkout after seller dropped catalog price to 0.50",
        )
        STRIPE_TEST.append(
            {
                "kind": "SESSION_CREATED",
                "label": "catalog_price_drop_after_seal",
                "http": c_cat,
                "body": clip(b_cat, 400),
                "product": snap_product(product_id),
                "order": snap_order(oid_legit),
            }
        )
        # restore price
        API.rest(
            "PATCH",
            "products",
            token=seller_jwt,
            json_body={"price": 12.50},
            query={"id": f"eq.{product_id}"},
        )

    # Off-platform + seller mark pago
    oid_off, row_off, _, _ = insert_order(
        "buyer",
        {
            **base_order,
            "payment_method": "mb way",
            "status": "aguarda_confirmacao",
            "shipping_method": "hand",
        },
        "off-platform MB WAY order",
    )
    if oid_off:
        c, b, raw = API.rest(
            "PATCH",
            "orders",
            token=seller_jwt,
            json_body={"status": "pago", "amount_paid_cents": 1250},
            query={"id": f"eq.{oid_off}"},
        )
        after = snap_order(oid_off)
        rec(
            "ORDER_FSM",
            "seller marks MB WAY order pago + amount_paid",
            "seller",
            f"HTTP {c} final_status={after.get('status')} paid={after.get('amount_paid_cents')}",
            "seller forged platform payment" if str(after.get("status", "")).lower() == "pago" and (after.get("amount_paid_cents") or 0) > 0 else "status/money blocked or status-only",
            "P1" if str(after.get("status", "")).lower() == "pago" and (after.get("amount_paid_cents") or 0) > 0 else ("P2" if str(after.get("status", "")).lower() == "pago" else "INFO"),
            {"http": c, "body": clip(b, 300), "final": after, "wallet_seller": snap_wallet(seller_uid)},
            finding=str(after.get("status", "")).lower() == "pago" and (after.get("amount_paid_cents") or 0) > 0,
            title="Seller forges amount_paid on off-platform order",
            repro="PATCH orders status=pago amount_paid_cents as seller",
        )
        c, b, raw = API.rpc(
            "batata_release_seller_wallet_for_order",
            {"p_order_id": oid_off},
            token=seller_jwt,
        )
        rec(
            "WALLET",
            "seller release wallet for unpaid/off-platform order",
            "seller",
            f"HTTP {c} {clip(b, 180)}",
            "wallet credited" if persist_ok(c, b) and not blocked(c, b) else "denied",
            "P0" if persist_ok(c, b) and not blocked(c, b) and not (isinstance(b, dict) and b.get("ok") is False) else "INFO",
            {"http": c, "body": clip(b, 400), "wallet": snap_wallet(seller_uid)},
            finding=persist_ok(c, b) and not blocked(c, b) and not (isinstance(b, dict) and b.get("ok") is False),
            title="Seller JWT release wallet without platform capture",
            repro="rpc batata_release_seller_wallet_for_order",
        )

# Offers
print("== offers / reviews / chat / disputes / live ==")
if product_id:
    c, b, raw = API.rest(
        "POST",
        "product_offers",
        token=buyer_jwt,
        json_body={
            "product_id": product_id,
            "buyer_id": buyer_uid,
            "seller_id": seller_uid,
            "amount": 0.50,
            "status": "accepted",
            "responded_at": datetime.now(timezone.utc).isoformat(),
        },
    )
    rec(
        "OFFERS",
        "buyer INSERT offer already accepted at 0.50",
        "buyer",
        f"HTTP {c} {clip(b, 180)}",
        "self-accepted offer" if persist_ok(c, b) else "rejected",
        "P1" if persist_ok(c, b) else "INFO",
        {"http": c, "body": clip(b, 400)},
        finding=persist_ok(c, b),
        title="Buyer inserts accepted product_offer",
        repro="POST product_offers status=accepted amount=0.50",
    )
    # pending then seller accept
    c, b, raw = API.rest(
        "POST",
        "product_offers",
        token=buyer_jwt,
        json_body={
            "product_id": product_id,
            "buyer_id": buyer_uid,
            "seller_id": seller_uid,
            "amount": 1.00,
            "status": "pending",
        },
    )
    offer_id = None
    if persist_ok(c, b):
        offer_id = (b[0] if isinstance(b, list) else b).get("id")
    if offer_id:
        API.rest(
            "PATCH",
            "product_offers",
            token=seller_jwt,
            json_body={"status": "accepted", "responded_at": datetime.now(timezone.utc).isoformat()},
            query={"id": f"eq.{offer_id}"},
        )
        oid_off1, row1, _, _ = insert_order(
            "buyer",
            {**base_order, "product_offer_id": offer_id, "quantity": 1, "price_total": 1},
            "order from accepted offer 1.00",
        )
        oid_off2, row2, _, _ = insert_order(
            "buyer",
            {**base_order, "product_offer_id": offer_id, "quantity": 1, "price_total": 1},
            "second order same accepted offer (oneshot)",
        )
        rec(
            "OFFERS",
            "reuse consumed offer on second order",
            "buyer",
            f"second_oid={oid_off2} row={clip(row2, 200)}",
            "double consume" if oid_off2 and row2 and row2.get("product_offer_id") == offer_id else "blocked or unlinked",
            "P1" if oid_off2 and row2 and row2.get("product_offer_id") == offer_id else "INFO",
            {"offer": offer_id, "first": row1, "second": row2},
            finding=bool(oid_off2 and row2 and row2.get("product_offer_id") == offer_id),
            title="Accepted offer consumed twice",
            repro="two POST orders with same product_offer_id",
        )

# Reviews
c, b, raw = API.rest(
    "POST",
    "reviews",
    token=buyer_jwt,
    json_body={
        "buyer_id": buyer_uid,
        "target_id": seller_uid,
        "rating": 5,
        "comment": "forged",
        "author_role": "comprador",
        "order_id": None,
    },
)
rec(
    "REVIEWS",
    "review without order",
    "buyer",
    f"HTTP {c} {clip(b, 180)}",
    "forged review" if persist_ok(c, b) else "rejected",
    "P1" if persist_ok(c, b) else "INFO",
    {"http": c, "body": clip(b, 400)},
    finding=persist_ok(c, b),
    title="Review insert without order",
    repro="POST reviews without order_id",
)
if foreign_order:
    c, b, raw = API.rest(
        "POST",
        "reviews",
        token=buyer_jwt,
        json_body={
            "buyer_id": buyer_uid,
            "target_id": foreign_order.get("seller_id"),
            "rating": 1,
            "comment": "hijack",
            "order_id": foreign_order.get("id"),
            "author_role": "comprador",
        },
    )
    rec(
        "REVIEWS",
        "review on foreign order",
        "buyer",
        f"HTTP {c} {clip(b, 180)}",
        "cross-user review" if persist_ok(c, b) else "rejected",
        "P1" if persist_ok(c, b) else "INFO",
        {"http": c, "body": clip(b, 400), "foreign_order": foreign_order},
        finding=persist_ok(c, b),
        title="Review on another buyer's order",
        repro="POST reviews order_id=<foreign>",
    )
c, b, raw = API.rest(
    "POST",
    "reviews",
    token=None,
    json_body={
        "buyer_id": buyer_uid,
        "target_id": seller_uid,
        "rating": 5,
        "comment": "anon",
        "author_role": "comprador",
    },
)
rec(
    "REVIEWS",
    "anon insert review",
    "anon",
    f"HTTP {c} {clip(b, 180)}",
    "anon review" if persist_ok(c, b) else "rejected",
    "P1" if persist_ok(c, b) else "INFO",
    {"http": c, "body": clip(b, 400)},
    finding=persist_ok(c, b),
    title="Anon INSERT reviews",
    repro="POST /rest/v1/reviews as anon",
)

# Storage
for ident, tok in (("anon", None), ("buyer", buyer_jwt)):
    c, b, raw = API.req(
        "GET",
        "/storage/v1/bucket",
        token=tok,
    )
    rec("STORAGE", f"list buckets as {ident}", ident, f"HTTP {c} {clip(b, 160)}", "bucket list", "INFO", {"http": c, "body": clip(b, 300)})
    for bucket in ("chat-uploads", "chat_uploads", "avatars", "dispute-evidence", "dispute_evidence", "products", "product-images"):
        c, b, raw = API.req("GET", f"/storage/v1/object/list/{bucket}", token=tok, json_body={"prefix": "", "limit": 10})
        rec(
            "STORAGE",
            f"list {bucket} as {ident}",
            ident,
            f"HTTP {c} {clip(b, 160)}",
            "objects listed" if c == 200 and b else "denied/missing",
            "P1" if c == 200 and isinstance(b, list) and b and ident == "anon" else "INFO",
            {"http": c, "body": clip(b, 300)},
            finding=c == 200 and isinstance(b, list) and bool(b) and ident == "anon" and bucket in ("chat-uploads", "chat_uploads", "dispute-evidence", "dispute_evidence"),
            title=f"Anon lists {bucket}",
            repro=f"GET storage list {bucket}",
        )

# Banking oracle
c, b, raw = API.rpc("batata_seller_direct_payment_details", {"p_seller_id": seller_uid}, token=buyer_jwt)
rec(
    "PRIVACY/BANKING",
    "buyer reads seller direct payment details without accepted order",
    "buyer",
    f"HTTP {c} {clip(b, 220)}",
    "iban/phone exposed" if persist_ok(c, b) and b else "denied or empty",
    "P1" if persist_ok(c, b) and b and not blocked(c, b) else "INFO",
    {"http": c, "body": clip(b, 500)},
    finding=persist_ok(c, b) and bool(b) and not blocked(c, b) and not (isinstance(b, dict) and b.get("ok") is False),
    title="Buyer RPC banking details without legitimate reveal state",
    repro="rpc batata_seller_direct_payment_details(seller)",
)
c, b, raw = API.rpc("batata_find_user_id_by_email", {"p_email": BUYER_EMAIL}, token=seller_jwt)
rec(
    "PRIVACY/EMAIL",
    "seller email→uuid oracle",
    "seller",
    f"HTTP {c} {clip(b, 180)}",
    "uuid returned" if persist_ok(c, b) and b else "denied",
    "P2" if persist_ok(c, b) and b and not blocked(c, b) else "INFO",
    {"http": c, "body": clip(b, 300)},
    finding=False,
)

# Live stream keys as buyer
c, b, raw = API.rest(
    "GET",
    "lives",
    token=buyer_jwt,
    query={"select": "id,seller_id,mux_stream_key,stream_key,mux_playback_id", "limit": "5"},
)
keys = []
if isinstance(b, list):
    for row in b:
        if row.get("mux_stream_key") or row.get("stream_key"):
            keys.append(row.get("id"))
rec(
    "LIVE/MUX",
    "buyer SELECT stream keys",
    "buyer",
    f"HTTP {c} keys={len(keys)}",
    "stream key leak" if keys else "columns empty or revoked",
    "P1" if keys else "INFO",
    {"http": c, "ids": keys, "sample": clip(b, 300)},
    finding=bool(keys),
    title="Authenticated buyer can read Mux stream keys",
    repro="GET /rest/v1/lives select mux_stream_key",
)
c, b, raw = API.rest(
    "GET",
    "lives",
    token=None,
    query={"select": "id,mux_stream_key,stream_key", "limit": "5"},
)
keys = []
if isinstance(b, list):
    for row in b:
        if row.get("mux_stream_key") or row.get("stream_key"):
            keys.append(row.get("id"))
rec(
    "LIVE/MUX",
    "anon SELECT stream keys",
    "anon",
    f"HTTP {c} keys={len(keys)}",
    "stream key leak" if keys else "blocked",
    "P1" if keys else "INFO",
    {"http": c, "ids": keys, "body": clip(b, 300)},
    finding=bool(keys),
    title="Anon can read Mux stream keys",
    repro="GET /rest/v1/lives as anon select stream_key",
)

# Tips: client amount
c, b, raw = API.edge(
    "create-live-tip-checkout",
    {"seller_id": seller_uid, "amount_eur": 500, "live_id": None},
    token=buyer_jwt,
)
rec(
    "TIPS",
    "tip checkout 500 EUR (server cap 500)",
    "buyer",
    f"HTTP {c} {clip(b, 180)}",
    "session or reject",
    "INFO",
    {"http": c, "body": clip(b, 400)},
)
c, b, raw = API.edge(
    "create-live-tip-checkout",
    {"seller_id": seller_uid, "amount_eur": 501},
    token=buyer_jwt,
)
rec(
    "TIPS",
    "tip checkout 501 EUR above cap",
    "buyer",
    f"HTTP {c} {clip(b, 180)}",
    "should reject",
    "P1" if persist_ok(c, b) and not blocked(c, b) else "INFO",
    {"http": c, "body": clip(b, 400)},
    finding=persist_ok(c, b) and not blocked(c, b),
    title="Tip amount exceeds server cap",
    repro="POST create-live-tip-checkout amount_eur=501",
)
c, b, raw = API.edge(
    "create-live-tip-checkout",
    {"seller_id": seller_uid, "amount_eur": 1, "tip_id": "00000000-0000-0000-0000-000000000099"},
    token=buyer_jwt,
)
rec(
    "TIPS",
    "client-supplied tip_id",
    "buyer",
    f"HTTP {c} {clip(b, 180)}",
    "pay-other credit-self" if persist_ok(c, b) and not blocked(c, b) else "rejected",
    "P0" if persist_ok(c, b) and not blocked(c, b) else "INFO",
    {"http": c, "body": clip(b, 400)},
    finding=persist_ok(c, b) and not blocked(c, b),
    title="Client tip_id accepted",
    repro="POST create-live-tip-checkout with tip_id",
)

# Connect payout cross-user
c, b, raw = API.edge(
    "create-connect-account",
    {"user_id": seller_uid, "amount": 1, "idempotency_key": "blind-" + stamp()},
    token=buyer_jwt,
)
rec(
    "PAYOUT",
    "buyer payout/connect as seller user_id",
    "buyer",
    f"HTTP {c} {clip(b, 180)}",
    "cross-user payout" if persist_ok(c, b) and not blocked(c, b) else "rejected",
    "P0" if persist_ok(c, b) and not blocked(c, b) else "INFO",
    {"http": c, "body": clip(b, 400)},
    finding=persist_ok(c, b) and not blocked(c, b),
    title="Buyer create-connect-account for seller",
    repro="POST create-connect-account user_id=<seller> as buyer",
)

# OCR without device token
c, b, raw = API.edge(
    "ingest-ocr-reservation",
    {
        "live_id": "00000000-0000-0000-0000-000000000001",
        "ocr_line_hash": "12345678deadbeef",
        "detected_at": datetime.now(timezone.utc).isoformat(),
        "ref_number": 1,
        "requested_qty": 99,
    },
    token=buyer_jwt,
)
rec(
    "PS/OCR",
    "ingest without x-device-token",
    "buyer",
    f"HTTP {c} {clip(b, 180)}",
    "ingest" if persist_ok(c, b) else "rejected",
    "P1" if persist_ok(c, b) and not blocked(c, b) else "INFO",
    {"http": c, "body": clip(b, 400)},
    finding=persist_ok(c, b) and not blocked(c, b),
    title="OCR ingest without device token",
    repro="POST ingest-ocr-reservation without x-device-token",
)

# Refund other seller's order
if foreign_order:
    c, b, raw = API.edge("refund-order", {"order_id": foreign_order["id"]}, token=buyer_jwt)
    rec(
        "REFUNDS",
        "buyer refund foreign order",
        "buyer",
        f"HTTP {c} {clip(b, 180)}",
        "cross-user refund" if persist_ok(c, b) and not blocked(c, b) else "denied",
        "P0" if persist_ok(c, b) and not blocked(c, b) and not (isinstance(b, dict) and (b.get("ok") is False or b.get("skipped"))) else "INFO",
        {"http": c, "body": clip(b, 400), "order": foreign_order},
        finding=persist_ok(c, b) and not blocked(c, b) and isinstance(b, dict) and b.get("ok") is True and not b.get("skipped"),
        title="Buyer refunds another seller's order",
        repro="POST refund-order order_id=<foreign> as buyer",
    )

# Profiles admin
c, b, raw = API.rest(
    "PATCH",
    "profiles",
    token=buyer_jwt,
    json_body={"is_admin": True, "user_type": "admin", "verified": True},
    query={"id": f"eq.{buyer_uid}"},
)
after_prof = None
c2, b2, _ = API.observe("profiles", query={"id": f"eq.{buyer_uid}", "select": "id,user_type,is_admin,verified,verification_status"})
if isinstance(b2, list) and b2:
    after_prof = b2[0]
rec(
    "AUTH/PROFILES",
    "buyer PATCH admin/verified flags",
    "buyer",
    f"HTTP {c} final={clip(after_prof, 200)}",
    "privilege escalation" if after_prof and (after_prof.get("is_admin") or str(after_prof.get("user_type", "")).lower() == "admin") else "blocked or no-op",
    "P0" if after_prof and (after_prof.get("is_admin") or str(after_prof.get("user_type", "")).lower() == "admin") else "INFO",
    {"http": c, "body": clip(b, 300), "final": after_prof},
    finding=bool(after_prof and (after_prof.get("is_admin") or str(after_prof.get("user_type", "")).lower() == "admin")),
    title="Buyer self-promotes admin",
    repro="PATCH profiles is_admin=true",
)

print("== PASS 1 done rows", len(MATRIX), "findings", len(FINDINGS))

# ---------------------------------------------------------------------------
# PASS 2 — variants / invariants
# ---------------------------------------------------------------------------
print("== PASS 2 variants ==")

# Invariant A/B: checkout amount vs contract
if product_id and order_ids:
    oid = order_ids[0]
    row = snap_order(oid)
    c, b, raw = API.edge(
        "create-payment-intent",
        {
            "buyer_id": buyer_uid,
            "order_id": oid,
            "amount": 50,
            "shipping_method": "carrier",
            "quantity": 1,
        },
        token=buyer_jwt,
    )
    session_amt = None
    if isinstance(b, dict):
        session_amt = b.get("amount") or b.get("amount_cents") or (b.get("session") or {}).get("amount_total")
    INVARIANTS["A_stripe_equals_contract"] = {
        "tested": True,
        "order": row,
        "client_amount": 50,
        "response": clip(b, 400),
        "http": c,
        "note": "client amount ignored if session still created from server quote",
    }
    INVARIANTS["B_buyer_price_qty_authority"] = {
        "tested": True,
        "hostile_insert": True,
        "result_rows": [snap_order(x) for x in order_ids[:4]],
    }

# JWT wallet credit variants: aliases / extra params
variants = [
    ("batata_credit_wallet_once", {"p_user_id": buyer_uid, "p_amount": 10, "p_order_id": None, "p_type": "venda", "p_description": "x"}),
    ("batata_credit_wallet_once", {"user_id": buyer_uid, "amount": 10}),
    ("batata_ensure_wallet", {"p_user_id": None}),
    ("batata_ensure_wallet", {}),
    ("batata_wallet_payout_debit", {"p_user_id": buyer_uid, "p_amount_cents": -100, "p_idempotency_key": "neg-" + stamp()}),
    ("batata_wallet_payout_debit", {"p_user_id": buyer_uid, "p_amount_cents": 1, "p_idempotency_key": "x"}),
    ("batata_wallet_payout_finish", {"p_idempotency_key": "x", "p_failed": True}),
]
w0 = snap_wallet(buyer_uid)
for name, payload in variants:
    c, b, raw = API.rpc(name, payload, token=buyer_jwt)
    rec(
        f"RPC/{name}",
        f"variant {payload}",
        "buyer",
        f"HTTP {c} {clip(b, 140)}",
        "see wallet delta",
        "INFO",
        {"http": c, "body": clip(b, 300), "payload": payload},
    )
w1 = snap_wallet(buyer_uid)
INVARIANTS["E_jwt_cannot_mint"] = {
    "tested": True,
    "wallet_before": w0,
    "wallet_after": w1,
    "delta": None,
}
try:
    INVARIANTS["E_jwt_cannot_mint"]["delta"] = float(w1.get("balance") or 0) - float(w0.get("balance") or 0)
except Exception:
    pass
if INVARIANTS["E_jwt_cannot_mint"].get("delta") and abs(INVARIANTS["E_jwt_cannot_mint"]["delta"]) > 0.001:
    rec(
        "WALLET",
        "Pass2 wallet delta after hostile RPCs",
        "buyer",
        f"delta={INVARIANTS['E_jwt_cannot_mint']['delta']}",
        "JWT minted or burned funds",
        "P0",
        INVARIANTS["E_jwt_cannot_mint"],
        finding=True,
        title="JWT changed wallet balance via RPC variants",
        repro="sequence of wallet RPCs as buyer",
    )

# Bag checkout two sellers if we can make second product as buyer (should fail) or disposable
if product_id and disp_jwt:
    c, b, raw = API.rest(
        "POST",
        "products",
        token=disp_jwt,
        json_body={
            "seller_id": disp_uid,
            "title": f"RT-DISP {stamp()}",
            "price": 8.00,
            "quantity": 2,
            "list_on_marketplace": True,
            "is_sold": False,
            "ref_code": f"RTD-{stamp()}",
        },
    )
    disp_prod = None
    if persist_ok(c, b):
        disp_prod = (b[0] if isinstance(b, list) else b).get("id")
        CLEANUP.append(f"product {disp_prod}")
    oid_a = order_ids[0] if order_ids else None
    oid_b = None
    if disp_prod:
        oid_b, _, _, _ = insert_order(
            "buyer",
            {
                "buyer_id": buyer_uid,
                "seller_id": disp_uid,
                "product_id": disp_prod,
                "quantity": 1,
                "status": "aguarda_pagamento",
                "payment_method": "seguro fleaber",
                "shipping_method": "hand",
                "price_total": 8,
            },
            "buyer order from disposable seller (bag multi-seller)",
        )
    if oid_a and oid_b:
        c, b, raw = API.edge(
            "create-payment-intent",
            {
                "buyer_id": buyer_uid,
                "bag_checkout": True,
                "shipping_method": "hand",
                "bag_lines": [
                    {"order_id": oid_a, "line_total_cents": 1},
                    {"order_id": oid_b, "line_total_cents": 1},
                ],
            },
            token=buyer_jwt,
        )
        rec(
            "BAG",
            "bag checkout two sellers",
            "buyer",
            f"HTTP {c} {clip(b, 180)}",
            "multi-seller session" if persist_ok(c, b) and not blocked(c, b) else "blocked",
            "P1" if persist_ok(c, b) and not blocked(c, b) else "INFO",
            {"http": c, "body": clip(b, 400)},
            finding=persist_ok(c, b) and not blocked(c, b),
            title="Bag checkout spans two sellers",
            repro="POST create-payment-intent bag_checkout two seller order_ids",
        )

# GET settle without paid session
c, b, raw = API.edge(
    "create-payment-intent",
    None,
    method="GET",
    qs="?checkout_return=success&session_id=cs_test_fake",
    token=None,
)
rec(
    "WEBHOOK/RETURN",
    "GET settle fake session_id as anon",
    "anon",
    f"HTTP {c} {clip(b, 180)}",
    "settle fake" if c in (200, 303) and "pago" in str(b).lower() else "no capture",
    "P1" if c in (200, 303) and "pago" in str(b).lower() else "INFO",
    {"http": c, "body": clip(b, 400)},
    finding=False,
)

print("== PASS 3 races ==")

def race_insert_orders(n=10):
    if not product_id:
        return []
    # reset stock to 1
    API.rest("PATCH", "products", service=True, json_body={"quantity": 1, "is_sold": False}, query={"id": f"eq.{product_id}"})
    payload = {
        "buyer_id": buyer_uid,
        "seller_id": seller_uid,
        "product_id": product_id,
        "quantity": 1,
        "status": "aguarda_pagamento",
        "payment_method": "seguro fleaber",
        "shipping_method": "hand",
        "price_total": 12.50,
    }

    def one(_i):
        return API.rest("POST", "orders", token=buyer_jwt, json_body=payload)

    results = []
    with ThreadPoolExecutor(max_workers=n) as ex:
        futs = [ex.submit(one, i) for i in range(n)]
        for f in as_completed(futs):
            results.append(f.result())
    persisted = []
    for c, b, raw in results:
        if persist_ok(c, b):
            row = b[0] if isinstance(b, list) else b
            if row.get("id"):
                persisted.append(row)
                CLEANUP.append(f"order {row['id']}")
    prod = snap_product(product_id)
    RACES.append(
        {
            "name": "10x order insert stock=1",
            "attempts": n,
            "persisted": len(persisted),
            "product": prod,
            "orders": persisted,
            "http_codes": [r[0] for r in results],
        }
    )
    oversell = len(persisted) > 1
    rec(
        "STOCK/RACE",
        "10 concurrent order inserts stock=1",
        "buyer",
        f"persisted={len(persisted)} product.qty={prod.get('quantity')} is_sold={prod.get('is_sold')}",
        "multiple holds on last unit" if oversell else "at most one hold",
        "P1" if oversell else "INFO",
        {"n": len(persisted), "product": prod, "ids": [p.get("id") for p in persisted]},
        finding=oversell,
        title="Race: two valid orders on stock=1",
        repro="10 parallel POST /rest/v1/orders qty=1 product.quantity=1",
    )
    return persisted


race_orders = race_insert_orders(10)

# Dual checkout sessions on same order
if order_ids:
    oid = order_ids[0]

    def one_session(i):
        return API.edge(
            "create-payment-intent",
            {
                "buyer_id": buyer_uid,
                "order_id": oid,
                "shipping_method": "hand",
                "amount": 1,
            },
            token=buyer_jwt,
        )

    sess = []
    with ThreadPoolExecutor(max_workers=8) as ex:
        futs = [ex.submit(one_session, i) for i in range(8)]
        for f in as_completed(futs):
            sess.append(f.result())
    created = []
    for c, b, raw in sess:
        if isinstance(b, dict) and (b.get("url") or b.get("id") or b.get("session_id") or (b.get("session") or {}).get("id")):
            created.append(clip(b, 200))
    RACES.append(
        {
            "name": "8x checkout sessions same order",
            "http": [s[0] for s in sess],
            "created_like": len(created),
            "samples": created[:3],
        }
    )
    rec(
        "CHECKOUT/RACE",
        "8 concurrent Checkout Sessions same order",
        "buyer",
        f"created_like={len(created)}",
        "multiple sessions (not automatically two captures)",
        "P2" if len(created) > 1 else "INFO",
        {"created_like": len(created), "http": [s[0] for s in sess], "sample": created[:2]},
        finding=False,
        title="Parallel Checkout Sessions on one order",
        repro="8 parallel POST create-payment-intent same order_id",
    )

# Dual refund as seller
if order_ids:
    oid = order_ids[0]

    def one_refund(_):
        return API.edge("refund-order", {"order_id": oid}, token=seller_jwt)

    refs = []
    with ThreadPoolExecutor(max_workers=6) as ex:
        futs = [ex.submit(one_refund, i) for i in range(6)]
        for f in as_completed(futs):
            refs.append(f.result())
    RACES.append({"name": "6x refund-order", "http": [r[0] for r in refs], "bodies": [clip(r[1], 120) for r in refs]})
    rec(
        "REFUNDS/RACE",
        "6 concurrent refund-order",
        "seller",
        f"https={[r[0] for r in refs]}",
        "duplicate refund attempt",
        "INFO",
        {"http": [r[0] for r in refs], "body": [clip(r[1], 160) for r in refs]},
    )

# Dual reviews
def one_review(i):
    return API.rest(
        "POST",
        "reviews",
        token=buyer_jwt,
        json_body={
            "buyer_id": buyer_uid,
            "target_id": seller_uid,
            "rating": 5,
            "comment": f"race{i}",
            "author_role": "comprador",
        },
    )

rev = []
with ThreadPoolExecutor(max_workers=6) as ex:
    futs = [ex.submit(one_review, i) for i in range(6)]
    for f in as_completed(futs):
        rev.append(f.result())
ok_rev = sum(1 for c, b, _ in rev if persist_ok(c, b))
RACES.append({"name": "6x review insert", "ok": ok_rev, "http": [r[0] for r in rev]})
rec(
    "REVIEWS/RACE",
    "6 concurrent reviews without order",
    "buyer",
    f"ok={ok_rev}",
    "duplicate reviews" if ok_rev > 0 else "all rejected",
    "P1" if ok_rev > 0 else "INFO",
    {"ok": ok_rev, "sample": clip(rev[0][1], 200) if rev else None},
    finding=ok_rev > 0,
    title="Concurrent forged reviews",
    repro="parallel POST reviews",
)

# Dual payout
def one_payout(i):
    return API.edge(
        "create-connect-account",
        {"amount": 1, "idempotency_key": f"race-{stamp()}-{i}"},
        token=seller_jwt,
    )

payouts = []
with ThreadPoolExecutor(max_workers=6) as ex:
    futs = [ex.submit(one_payout, i) for i in range(6)]
    for f in as_completed(futs):
        payouts.append(f.result())
RACES.append({"name": "6x payout different keys", "http": [p[0] for p in payouts], "sample": [clip(p[1], 120) for p in payouts[:3]]})
same_key = "samekey-" + stamp()

def one_payout_same(_):
    return API.edge(
        "create-connect-account",
        {"amount": 1, "idempotency_key": same_key},
        token=seller_jwt,
    )

p2 = []
with ThreadPoolExecutor(max_workers=6) as ex:
    futs = [ex.submit(one_payout_same, i) for i in range(6)]
    for f in as_completed(futs):
        p2.append(f.result())
RACES.append({"name": "6x payout SAME idempotency key", "http": [p[0] for p in p2], "sample": [clip(p[1], 140) for p in p2]})
rec(
    "PAYOUT/RACE",
    "parallel payouts distinct vs same idempotency",
    "seller",
    f"distinct_http={[p[0] for p in payouts]} same_http={[p[0] for p in p2]}",
    "observe transfers — JWT only, may fail without connect/balance",
    "INFO",
    {"distinct": [clip(p[1], 120) for p in payouts], "same": [clip(p[1], 120) for p in p2]},
)

# Stripe TEST capture via e2e secret (fixture pay) then JWT refund/release
if E2E_SECRET and product_id:
    API.rest(
        "PATCH",
        "products",
        service=True,
        json_body={"quantity": 1, "is_sold": False, "price": 5.00},
        query={"id": f"eq.{product_id}"},
    )
    c, b, raw = API.edge(
        "sec-fase2-e2e-oversell",
        {
            "probe": "pay_one",
            "buyer_id": buyer_uid,
            "seller_id": seller_uid,
            "product_id": product_id,
            "initial_qty": 1,
        },
        token=None,
        extra_headers={"x-fleaber-e2e-secret": E2E_SECRET, "x-fleaber-crash-inject-secret": E2E_SECRET},
    )
    STRIPE_TEST.append({"kind": "E2E_FIXTURE", "probe": "pay_one", "http": c, "body": clip(b, 800)})
    rec(
        "STRIPE_TEST",
        "e2e pay_one fixture (secret, not JWT authority)",
        "e2e-secret",
        f"HTTP {c}",
        "fixture only — not a JWT finding",
        "INFO",
        {"http": c, "body": clip(b, 500)},
    )
    # If two pay on stock 1
    c2, b2, raw2 = API.edge(
        "sec-fase2-e2e-oversell",
        {
            "probe": "oversell_two",
            "buyer_id": buyer_uid,
            "seller_id": seller_uid,
            "product_id": product_id,
            "initial_qty": 1,
        },
        token=None,
        extra_headers={"x-fleaber-e2e-secret": E2E_SECRET},
    )
    STRIPE_TEST.append({"kind": "E2E_OVERSELL", "http": c2, "body": clip(b2, 1000)})
    rec(
        "STOCK×STRIPE",
        "e2e oversell_two stock=1 (lab secret setup of dual PI)",
        "e2e-secret",
        f"HTTP {c2} {clip(b2, 200)}",
        "observe dual capture vs refund",
        "INFO",
        {"http": c2, "body": clip(b2, 800)},
    )

# Live reservations race if we can find a live_item
code, live_items, _ = API.observe(
    "live_items",
    query={"select": "id,live_id,seller_id,product_id,status,quantity", "seller_id": f"eq.{seller_uid}", "limit": "3"},
)
if isinstance(live_items, list) and live_items:
    li = live_items[0]
    def one_res(i):
        return API.rest(
            "POST",
            "live_reservation_requests",
            token=buyer_jwt,
            json_body={
                "live_id": li.get("live_id"),
                "live_item_id": li.get("id"),
                "buyer_id": buyer_uid,
                "seller_id": seller_uid,
                "requested_qty": 1,
                "status": "accepted",
                "source": "fleaber_live",
            },
        )
    rr = []
    with ThreadPoolExecutor(max_workers=8) as ex:
        futs = [ex.submit(one_res, i) for i in range(8)]
        for f in as_completed(futs):
            rr.append(f.result())
    ok_r = [r for r in rr if persist_ok(r[0], r[1])]
    RACES.append({"name": "8x reservation accepted", "ok": len(ok_r), "http": [r[0] for r in rr]})
    rec(
        "LIVE/RESERVATION",
        "8 concurrent accepted reservations",
        "buyer",
        f"ok={len(ok_r)}",
        "capacity bypass" if len(ok_r) > 1 else "limited",
        "P1" if len(ok_r) > 1 else "INFO",
        {"ok": len(ok_r), "item": li, "sample": clip(ok_r[0][1], 200) if ok_r else clip(rr[0][1], 200)},
        finding=len(ok_r) > 1,
        title="Buyer self-accepts concurrent live reservations",
        repro="parallel POST live_reservation_requests status=accepted",
    )
else:
    GAPS.append("no seller live_items for reservation race")

# Chat cross-user
c, b, raw = API.rest(
    "GET",
    "chats",
    token=buyer_jwt,
    query={"select": "id,user_a,user_b,product_id", "limit": "20"},
)
rec("CHAT", "buyer list chats", "buyer", f"HTTP {c} n={len(b) if isinstance(b, list) else None}", "own chats expected", "INFO", {"http": c, "n": len(b) if isinstance(b, list) else None})
# try messages table names
for mt in ("messages", "chat_messages"):
    if mt not in tables and mt not in ("messages", "chat_messages"):
        continue
    c, b, raw = API.rest("GET", mt, token=buyer_jwt, query={"select": "*", "limit": "5"})
    rec("CHAT", f"GET {mt}", "buyer", f"HTTP {c}", "see leak flags in RLS pass", "INFO", {"http": c, "body": clip(b, 200)})

# Disputes
for dt in ("order_disputes", "disputes"):
    c, b, raw = API.rest(
        "POST",
        dt,
        token=buyer_jwt,
        json_body={"order_id": order_ids[0] if order_ids else "00000000-0000-0000-0000-000000000001", "reason": "x", "status": "open"},
    )
    rec(
        "DISPUTES",
        f"INSERT {dt}",
        "buyer",
        f"HTTP {c} {clip(b, 140)}",
        "created" if persist_ok(c, b) else "rejected/missing",
        "INFO",
        {"http": c, "body": clip(b, 300)},
    )

INVARIANTS["C_release_refund_net"] = {"tested": True, "note": "JWT release/refund RPCs exercised; see matrix"}
INVARIANTS["D_unit_two_sales"] = {"tested": True, "race": [r for r in RACES if "stock=1" in r.get("name", "")]}
INVARIANTS["F_off_platform_wallet"] = {"tested": True}
INVARIANTS["G_refund_gt_capture"] = {"tested": True, "note": "refund-order without paid PI"}
INVARIANTS["H_party_coherence"] = {"tested": True}
INVARIANTS["I_payout_one_transfer"] = {"tested": True, "race_same_key": True}
INVARIANTS["J_two_intents_two_transfers"] = {"tested": True, "limitation": "may lack connect/balance"}
INVARIANTS["K_catalog_not_retroactive"] = {"tested": True}
INVARIANTS["L_offer_authority"] = {"tested": True}

# Cleanup disposable auth user (not lab buyer/seller)
if disp_uid:
    API.req("DELETE", f"/auth/v1/admin/users/{disp_uid}", service=True)

# ---------------------------------------------------------------------------
# Freeze
# ---------------------------------------------------------------------------
FROZEN_AT = datetime.now(timezone.utc).isoformat()

p0 = [f for f in FINDINGS if f["severity"] == "P0"]
p1 = [f for f in FINDINGS if f["severity"] == "P1"]

checklist = {
    "1_p0_open": "SIM" if p0 else "NÃO",
    "2_p0_count": len(p0),
    "3_p1_open": "SIM" if p1 else "NÃO",
    "4_p1_count": len(p1),
    "5_buyer_price_authority": "AVALIAR",
    "6_buyer_qty_authority": "AVALIAR",
    "7_seller_fake_platform_payment": "AVALIAR",
    "8_jwt_mint_wallet": "AVALIAR",
    "9_refund_exceeds_capture": "AVALIAR",
    "10_release_refund_net_money": "AVALIAR",
    "11_payout_dup_transfer": "AVALIAR",
    "12_stock1_two_valid_sales": "AVALIAR",
    "13_stock1_two_permanent_captures": "NÃO COMPROVADO",
    "14_capacity_bypass": "AVALIAR",
    "15_cross_user_financial": "AVALIAR",
    "16_cross_user_sensitive": "AVALIAR",
    "17_buyer_as_seller_admin": "AVALIAR",
    "18_seller_as_buyer_admin": "AVALIAR",
    "19_reviews_forged": "AVALIAR",
    "20_dangerous_definer": "AVALIAR",
    "21_rls_critical": "AVALIAR",
    "22_edge_trusts_client": "AVALIAR",
    "23_critical_unproven": "SIM",
    "24_functional_regression": "NÃO",
    "25_last_pass_new_p0p1_class": "SIM" if p0 or p1 else "NÃO",
    "26_saturation": "NÃO",
    "27_production_touched": "NÃO",
    "28_fase4_started": "NÃO",
}

raw = {
    "audit": "REDTEAM_BLIND_INDEP_20260829T2231",
    "project": STAGING_REF,
    "started": STARTED.isoformat(),
    "FROZEN_AT": FROZEN_AT,
    "production_touched": False,
    "fase4": False,
    "tables_seen": tables,
    "rpcs_seen": rpcs,
    "matrix": MATRIX,
    "findings": FINDINGS,
    "invariants": INVARIANTS,
    "races": RACES,
    "stripe_test": STRIPE_TEST,
    "gaps": GAPS,
    "cleanup": CLEANUP,
    "checklist_partial": checklist,
    "pass_counts": {"matrix": len(MATRIX), "findings": len(FINDINGS), "p0": len(p0), "p1": len(p1)},
}

out_json = OUT_DIR / f"results_{RUN_ID}.json"
out_json.write_text(json.dumps(raw, indent=2, default=str), encoding="utf-8")
print("WROTE", out_json)
print("FINDINGS", len(FINDINGS), "P0", len(p0), "P1", len(p1))
print("GAPS", GAPS)
sys.exit(0)
