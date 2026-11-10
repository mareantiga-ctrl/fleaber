#!/usr/bin/env python3
"""Fleaber independent blind AppSec probe — staging only. Does not fix anything.

Usage: python tool/sec_blind_indep_20260829.py
"""
from __future__ import annotations

import json
import os
import sys
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = ROOT / "tool" / "live_ops_staging.env"
OUT_DIR = ROOT / "tool" / "reports"
PROJECT = "fxdknzrqjenzqcvnwqqq"
STAMP = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
TAG = f"rtb29-{int(time.time())}"

SENSITIVE_TABLES = [
    "orders",
    "products",
    "profiles",
    "wallets",
    "wallet_transactions",
    "wallet_payout_ledger",
    "fleaber_commissions",
    "reviews",
    "chats",
    "chat_messages",
    "order_disputes",
    "live_reservation_requests",
    "live_items",
    "lives",
    "live_raffles",
    "live_raffle_winners",
    "live_raffle_tickets",
    "live_raffle_referral_links",
    "live_tips",
    "product_offers",
    "seller_bundle_discounts",
    "stripe_checkout_events",
    "ps_pairing",
    "ps_devices",
    "ps_ingest_audit",
    "order_return_shipments",
    "live_director_scripts",
    "live_director_runs",
    "hub_staff",
    "notifications",
]

EDGE_FNS = [
    "create-payment-intent",
    "create-live-tip-checkout",
    "create-connect-account",
    "refund-order",
    "stripe-webhook",
    "create-mux-live",
    "complete-mux-live",
    "livekit-mux-publish",
    "livekit-egress-cleanup",
    "delete-test-account",
    "ingest-ocr-reservation",
    "ps-pairing-claim",
    "ps-heartbeat",
    "ps-panel-log",
    "meta-data-deletion",
    "resolve-mux-playback",
    "sec-fase2-e2e-oversell",
    "send-sms-bulkgate",
]

FINANCIAL_RPC_CANDIDATES = [
    "batata_credit_wallet_once",
    "batata_debit_wallet_once",
    "batata_wallet_payout_debit",
    "batata_wallet_payout_finish",
    "batata_release_seller_wallet_for_order",
    "batata_refund_buyer_wallet_for_order",
    "batata_partial_refund_seller_wallet_for_order",
    "batata_finalize_stripe_order_refund",
    "batata_create_raffle_prize_order",
    "batata_award_live_raffle_tickets",
    "batata_generate_auto_feedback",
    "batata_lab_clear_fm_pending",
    "batata_lab_clear_all_fm_pending",
    "batata_ensure_wallet",
    "batata_ps_claim_pairing",
    "batata_ingest_ocr_reservation_v2",
    "batata_order_payment_confirmed",
    "batata_is_admin",
    "batata_assert_wallet_rpc_grants",
]


def load_env(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        t = line.strip()
        if not t or t.startswith("#") or "=" not in t:
            continue
        k, v = t.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def req(
    method: str,
    url: str,
    headers: dict[str, str],
    body: Any = None,
    timeout: int = 45,
) -> dict[str, Any]:
    data = None
    hdrs = dict(headers)
    if body is not None:
        if isinstance(body, (dict, list)):
            data = json.dumps(body).encode("utf-8")
            hdrs.setdefault("Content-Type", "application/json")
        elif isinstance(body, str):
            data = body.encode("utf-8")
        else:
            data = body
    r = Request(url, data=data, headers=hdrs, method=method)
    try:
        with urlopen(r, timeout=timeout) as resp:
            raw = resp.read()
            text = raw.decode("utf-8", errors="replace")
            parsed: Any
            try:
                parsed = json.loads(text) if text else None
            except json.JSONDecodeError:
                parsed = text[:2000]
            return {
                "http": resp.status,
                "body": parsed,
                "text": text[:4000],
                "headers": dict(resp.headers),
            }
    except HTTPError as e:
        raw = e.read()
        text = raw.decode("utf-8", errors="replace")
        try:
            parsed = json.loads(text) if text else None
        except json.JSONDecodeError:
            parsed = text[:2000]
        return {
            "http": e.code,
            "body": parsed,
            "text": text[:4000],
            "headers": dict(e.headers),
        }
    except URLError as e:
        return {"http": 0, "body": None, "text": str(e), "headers": {}}


class Probe:
    def __init__(self, env: dict[str, str]) -> None:
        self.env = env
        raw = env["SUPABASE_URL"].strip().rstrip("/")
        for suffix in ("/rest/v1", "/auth/v1", "/functions/v1"):
            if raw.endswith(suffix):
                raw = raw[: -len(suffix)].rstrip("/")
        self.base = raw
        if PROJECT not in self.base:
            raise SystemExit("REFUSED: not staging project")
        self.anon = env["SUPABASE_ANON_KEY"]
        self.svc = env["SUPABASE_SERVICE_ROLE_KEY"]
        self.buyer_id = env["LIVE_OPS_TEST_BUYER_ID"]
        self.seller_id = env["LIVE_OPS_TEST_SELLER_ID"]
        self.buyer_jwt = ""
        self.seller_jwt = ""
        self.matrix: list[dict[str, Any]] = []
        self.findings: list[dict[str, Any]] = []
        self.notes: list[str] = []
        self.inventory: dict[str, Any] = {}
        self.cleanup: list[tuple[str, str]] = []
        self.created_ids: dict[str, str] = {}

    def H(self, token: str, prefer: str = "return=representation") -> dict[str, str]:
        h = {
            "apikey": self.anon if token != self.svc else self.svc,
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        }
        if prefer:
            h["Prefer"] = prefer
        return h

    def rest(self, method: str, path: str, token: str, body: Any = None, prefer: str | None = None) -> dict[str, Any]:
        h = self.H(token)
        if prefer:
            h["Prefer"] = prefer
        return req(method, f"{self.base}/rest/v1/{path}", h, body)

    def rpc(self, name: str, token: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        return req("POST", f"{self.base}/rest/v1/rpc/{name}", self.H(token), params or {})

    def edge(self, name: str, token: str, body: Any, method: str = "POST", qs: str = "") -> dict[str, Any]:
        url = f"{self.base}/functions/v1/{name}{qs}"
        h = {
            "apikey": self.anon,
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        }
        return req(method, url, h, body)

    def sign_in(self, email: str, password: str) -> str:
        r = req(
            "POST",
            f"{self.base}/auth/v1/token?grant_type=password",
            {"apikey": self.anon, "Content-Type": "application/json"},
            {"email": email, "password": password},
        )
        if r["http"] != 200 or not isinstance(r["body"], dict):
            raise SystemExit(f"login failed {email} {r['http']} {r['text'][:200]}")
        tok = r["body"].get("access_token") or ""
        if not tok:
            raise SystemExit(f"no access_token for {email}")
        return tok

    def rec(self, surface: str, attack: str, ident: str, result: str, impact: str, sev: str, evidence: Any) -> None:
        self.matrix.append(
            {
                "surface": surface,
                "attack": attack,
                "identity": ident,
                "result": result,
                "impact": impact,
                "severity": sev,
                "evidence": evidence,
            }
        )

    def finding(
        self,
        fid: str,
        sev: str,
        title: str,
        actor: str,
        pre: str,
        repro: str,
        impact: str,
        evidence: Any,
    ) -> None:
        self.findings.append(
            {
                "id": fid,
                "severity": sev,
                "title": title,
                "actor": actor,
                "preconditions": pre,
                "reproduction": repro,
                "impact": impact,
                "state": "OPEN",
                "evidence": evidence,
            }
        )

    def observe(self, table: str, filt: str, cols: str = "*") -> Any:
        return self.rest("GET", f"{table}?select={cols}&{filt}&limit=5", self.svc)

    def login(self) -> None:
        self.buyer_jwt = self.sign_in(
            self.env["LIVE_OPS_TEST_BUYER_EMAIL"],
            self.env["LIVE_OPS_TEST_BUYER_PASSWORD"],
        )
        self.seller_jwt = self.sign_in(
            self.env["LIVE_OPS_TEST_SELLER_EMAIL"],
            self.env["LIVE_OPS_TEST_SELLER_PASSWORD"],
        )
        bu = req("GET", f"{self.base}/auth/v1/user", self.H(self.buyer_jwt, prefer=""))
        su = req("GET", f"{self.base}/auth/v1/user", self.H(self.seller_jwt, prefer=""))
        bid = (bu.get("body") or {}).get("id") if isinstance(bu.get("body"), dict) else None
        sid = (su.get("body") or {}).get("id") if isinstance(su.get("body"), dict) else None
        if bid != self.buyer_id or sid != self.seller_id:
            raise SystemExit(f"identity mismatch buyer={bid} seller={sid}")
        self.notes.append("login_ok staging lab buyer/seller")

    # ---------- inventory ----------
    def pass1_inventory(self) -> None:
        spec = req(
            "GET",
            f"{self.base}/rest/v1/",
            {
                **self.H(self.anon),
                "Accept": "application/openapi+json",
            },
        )
        paths = []
        tables = []
        rpcs = []
        if isinstance(spec.get("body"), dict):
            paths = list((spec["body"].get("paths") or {}).keys())
            for p in paths:
                if p.startswith("/rpc/"):
                    rpcs.append(p[5:])
                elif p.startswith("/") and p.count("/") == 1:
                    tables.append(p[1:])
        self.inventory = {
            "openapi_http": spec["http"],
            "table_count": len(tables),
            "rpc_count": len(rpcs),
            "tables": sorted(tables),
            "rpcs": sorted(rpcs),
        }
        self.rec(
            "SCHEMA",
            "openapi_inventory",
            "anon",
            f"http={spec['http']} tables={len(tables)} rpcs={len(rpcs)}",
            "map attack surface",
            "INFO",
            {"tables_sample": tables[:40], "rpc_sample": rpcs[:40]},
        )

    def jwt_alg_none(self) -> None:
        import base64

        def b64(obj: dict) -> str:
            return base64.urlsafe_b64encode(json.dumps(obj, separators=(",", ":")).encode()).decode().rstrip("=")

        forged = b64({"alg": "none", "typ": "JWT"}) + "." + b64(
            {
                "role": "service_role",
                "iss": "supabase",
                "sub": self.buyer_id,
                "aud": "authenticated",
            }
        ) + "."
        r = self.rest("GET", "wallets?select=id,balance&limit=3", forged)
        self.rec(
            "AUTH",
            "jwt_alg_none_service_role_claim",
            "forged",
            f"http={r['http']}",
            "privilege escalation if wallets readable",
            "P0" if r["http"] == 200 and r.get("body") else "INFO",
            {"http": r["http"], "body": r["body"] if r["http"] != 200 else "REDACTED_IF_EMPTY"},
        )
        if r["http"] == 200 and r.get("body"):
            self.finding(
                "RTB-AUTH-01",
                "P0",
                "JWT alg=none accepted as service_role",
                "unauthenticated forger",
                "none",
                "GET /wallets with alg=none + role=service_role",
                "full data/privilege compromise",
                {"http": r["http"]},
            )

    def rls_sweep(self) -> None:
        idents = {"anon": self.anon, "buyer": self.buyer_jwt, "seller": self.seller_jwt}
        tables = self.inventory.get("tables") or SENSITIVE_TABLES
        for table in SENSITIVE_TABLES:
            if tables and table not in tables and table not in SENSITIVE_TABLES:
                continue
            for name, tok in idents.items():
                g = self.rest("GET", f"{table}?select=*&limit=3", tok)
                leaked = False
                rows = g.get("body") if isinstance(g.get("body"), list) else []
                if g["http"] == 200 and rows:
                    if table in {
                        "wallets",
                        "wallet_transactions",
                        "wallet_payout_ledger",
                        "chats",
                        "chat_messages",
                        "order_disputes",
                        "ps_pairing",
                        "ps_devices",
                    }:
                        # own rows may be OK; flag foreign IDs
                        leaked = self._has_foreign(table, rows, name)
                    if table == "lives":
                        for row in rows:
                            if isinstance(row, dict) and row.get("mux_stream_key"):
                                leaked = True
                                self.finding(
                                    "RTB-PRIV-LIVEKEY",
                                    "P1",
                                    "mux_stream_key readable via PostgREST",
                                    name,
                                    "any live row",
                                    f"GET lives as {name}",
                                    "stream hijack / ingest",
                                    {"id": row.get("id")},
                                )
                self.rec(
                    "RLS",
                    f"SELECT {table}",
                    name,
                    f"http={g['http']} n={len(rows) if isinstance(rows, list) else 0} leak={leaked}",
                    "cross-user read" if leaked else "read scope",
                    "P1" if leaked else "INFO",
                    {"http": g["http"], "n": len(rows) if isinstance(rows, list) else 0, "err": _err(g)},
                )

    def _has_foreign(self, table: str, rows: list, ident: str) -> bool:
        mine = self.buyer_id if ident == "buyer" else self.seller_id if ident == "seller" else None
        if not mine:
            return bool(rows)
        for row in rows:
            if not isinstance(row, dict):
                continue
            ids = {row.get("id"), row.get("buyer_id"), row.get("seller_id"), row.get("wallet_id"), row.get("user_id")}
            if ident == "buyer" and row.get("seller_id") == mine:
                continue
            if mine not in ids and row.get("id") != mine:
                # chats: participant columns
                if table in ("chats", "chat_messages"):
                    if mine in {row.get("participant_1"), row.get("participant_2"), row.get("sender_id")}:
                        continue
                return True
        return False

    def privilege_and_money_cols(self) -> None:
        # user_type admin promotion
        before = self.rest("GET", f"profiles?id=eq.{self.buyer_id}&select=id,user_type,phone_verified_at", self.buyer_jwt)
        orig = None
        if isinstance(before.get("body"), list) and before["body"]:
            orig = before["body"][0].get("user_type")
        patch = self.rest(
            "PATCH",
            f"profiles?id=eq.{self.buyer_id}",
            self.buyer_jwt,
            {"user_type": "admin"},
        )
        after = self.observe("profiles", f"id=eq.{self.buyer_id}", "id,user_type")
        after_type = None
        if isinstance(after.get("body"), list) and after["body"]:
            after_type = after["body"][0].get("user_type")
        promoted = str(after_type).lower() in {"admin", "admim", "administrador", "administracao"}
        self.rec(
            "AUTH/PROFILES",
            "PATCH user_type=admin",
            "buyer",
            f"http={patch['http']} persisted={after_type} orig={orig}",
            "admin bypass if persisted",
            "P0" if promoted else "INFO",
            {"http": patch["http"], "err": _err(patch), "persisted": after_type},
        )
        if promoted:
            self.finding(
                "RTB-AUTH-02",
                "P0",
                "Buyer JWT can set profiles.user_type=admin",
                "buyer",
                "own profile row",
                "PATCH profiles user_type=admin",
                "batata_is_admin() true; wallet/release/admin RLS",
                {"persisted": after_type},
            )
            # restore via service_role (cleanup, not exploit)
            self.rest("PATCH", f"profiles?id=eq.{self.buyer_id}", self.svc, {"user_type": orig or "comprador"})
        else:
            # restore if echo
            if orig and after_type != orig:
                self.rest("PATCH", f"profiles?id=eq.{self.buyer_id}", self.svc, {"user_type": orig})

        for col, val in [
            ("phone_verified_at", datetime.now(timezone.utc).isoformat()),
            ("is_verified", True),
            ("trust_score", 99),
            ("risk_score", 0),
        ]:
            r = self.rest("PATCH", f"profiles?id=eq.{self.buyer_id}", self.buyer_jwt, {col: val})
            self.rec(
                "AUTH/PROFILES",
                f"PATCH {col}",
                "buyer",
                f"http={r['http']}",
                "reputation/trust spoof",
                "INFO",
                {"err": _err(r), "http": r["http"]},
            )

        # wallets
        w_ins = self.rest(
            "POST",
            "wallets",
            self.buyer_jwt,
            {"id": self.buyer_id, "balance": 99999.12, "stripe_account_id": "acct_hostile"},
        )
        w_upd = self.rest("PATCH", f"wallets?id=eq.{self.buyer_id}", self.buyer_jwt, {"balance": 88888})
        w_obs = self.observe("wallets", f"id=eq.{self.buyer_id}", "id,balance,stripe_account_id")
        bal = None
        if isinstance(w_obs.get("body"), list) and w_obs["body"]:
            bal = w_obs["body"][0].get("balance")
        minted = False
        try:
            minted = float(bal or 0) >= 80000
        except (TypeError, ValueError):
            minted = False
        self.rec(
            "WALLET",
            "INSERT/PATCH balance",
            "buyer",
            f"ins={w_ins['http']} upd={w_upd['http']} bal={bal}",
            "create funds",
            "P0" if minted else "INFO",
            {"ins": _err(w_ins), "upd": _err(w_upd), "bal": bal},
        )
        if minted:
            self.finding(
                "RTB-WAL-01",
                "P0",
                "JWT minted wallet balance",
                "buyer",
                "own wallet",
                "POST/PATCH wallets.balance",
                "arbitrary Fleaber funds",
                {"balance": bal},
            )

        wt = self.rest(
            "POST",
            "wallet_transactions",
            self.buyer_jwt,
            {
                "wallet_id": self.buyer_id,
                "amount": 50,
                "type": "venda",
                "description": f"{TAG}-forged-ledger",
                "order_id": str(uuid.uuid4()),
            },
        )
        self.rec(
            "LEDGER",
            "INSERT wallet_transactions",
            "buyer",
            f"http={wt['http']}",
            "forged ledger",
            "P1" if wt["http"] in (200, 201) else "INFO",
            {"err": _err(wt)},
        )
        if wt["http"] in (200, 201):
            self.finding(
                "RTB-LED-01",
                "P1",
                "JWT can insert wallet_transactions",
                "buyer",
                "none",
                "POST wallet_transactions",
                "forged ledger / possible balance trigger",
                {"http": wt["http"], "body": wt.get("body")},
            )

    def rpc_hostile(self) -> None:
        names = list(FINANCIAL_RPC_CANDIDATES)
        live_rpcs = self.inventory.get("rpcs") or []
        for n in live_rpcs:
            if n.startswith("batata_") and n not in names:
                names.append(n)
        for ident, tok in [("anon", self.anon), ("buyer", self.buyer_jwt), ("seller", self.seller_jwt)]:
            for fn in FINANCIAL_RPC_CANDIDATES:
                params: dict[str, Any] = {}
                if "order" in fn or fn.endswith("_for_order"):
                    params = {"p_order_id": str(uuid.uuid4())}
                elif fn == "batata_credit_wallet_once":
                    params = {
                        "p_wallet_id": self.buyer_id,
                        "p_order_id": str(uuid.uuid4()),
                        "p_amount": 12.34,
                        "p_type": "venda",
                        "p_description": TAG,
                    }
                elif fn == "batata_wallet_payout_debit":
                    params = {
                        "p_user_id": self.seller_id,
                        "p_amount_cents": 100,
                        "p_idempotency_key": TAG + "debit",
                    }
                elif fn == "batata_is_admin":
                    params = {}
                elif fn == "batata_ensure_wallet":
                    params = {"p_user_id": self.buyer_id}
                r = self.rpc(fn, tok, params)
                interesting = r["http"] not in (401, 403, 404) and not _denied(r)
                self.rec(
                    "RPC",
                    fn,
                    ident,
                    f"http={r['http']} {str(_err(r))[:80]}",
                    "privileged execute" if r["http"] in (200, 201) else "denied/missing",
                    "P1" if interesting and fn.startswith("batata_credit") and r["http"] == 200 else "INFO",
                    {"http": r["http"], "err": _err(r), "body": _clip(r.get("body"))},
                )
                if fn == "batata_credit_wallet_once" and r["http"] == 200 and r.get("body") is True:
                    self.finding(
                        "RTB-RPC-CREDIT",
                        "P0",
                        "JWT executed batata_credit_wallet_once",
                        ident,
                        "EXECUTE grant",
                        "rpc batata_credit_wallet_once",
                        "mint wallet funds",
                        r,
                    )

    def edge_hostile(self) -> None:
        fake_order = str(uuid.uuid4())
        payloads = {
            "create-payment-intent": {
                "buyer_id": self.buyer_id,
                "seller_id": self.seller_id,
                "order_id": fake_order,
                "amount": 1,
                "quantity": 1,
                "item_price": 0.01,
                "shipping": 0,
                "protection_fee": 0,
                "shipping_method": "hand",
            },
            "create-live-tip-checkout": {
                "live_id": str(uuid.uuid4()),
                "seller_id": self.seller_id,
                "amount_eur": 1,
            },
            "create-connect-account": {
                "user_id": self.seller_id,
                "amount": 100,
                "idempotency_key": TAG + "payout",
            },
            "refund-order": {"order_id": fake_order},
            "stripe-webhook": {"type": "checkout.session.completed"},
            "create-mux-live": {"title": "hostile stream"},
            "complete-mux-live": {"live_id": str(uuid.uuid4())},
            "livekit-mux-publish": {"step": "token", "live_id": str(uuid.uuid4())},
            "livekit-egress-cleanup": {},
            "delete-test-account": {"confirm": "APAGAR TUDO"},
            "ingest-ocr-reservation": {
                "live_id": str(uuid.uuid4()),
                "ocr_line_hash": "abcdefghijkl",
                "detected_at": datetime.now(timezone.utc).isoformat(),
                "ref_number": 1,
            },
            "ps-pairing-claim": {"code": "000000", "device_id": "rtb"},
            "ps-heartbeat": {"live_id": str(uuid.uuid4()), "device_id": "rtb"},
            "ps-panel-log": {"live_id": str(uuid.uuid4()), "message": "x"},
            "meta-data-deletion": {},
            "resolve-mux-playback": {"live_id": str(uuid.uuid4())},
            "sec-fase2-e2e-oversell": {"probe": "x", "buyer_id": self.buyer_id, "seller_id": self.seller_id},
            "send-sms-bulkgate": {"phone": "+351910000000", "otp": "000000"},
        }
        for fn, body in payloads.items():
            for ident, tok in [("anon", self.anon), ("buyer", self.buyer_jwt), ("seller", self.seller_jwt)]:
                r = self.edge(fn, tok, body)
                self.rec(
                    "EDGE",
                    fn,
                    ident,
                    f"http={r['http']}",
                    "unauth invoke" if ident == "anon" and r["http"] not in (401, 403) else "invoke",
                    "INFO",
                    {"http": r["http"], "err": _err(r), "body": _clip(r.get("body"))},
                )
        # GET settle without paying
        rget = self.edge(
            "create-payment-intent",
            self.anon,
            None,
            method="GET",
            qs="?checkout_return=success&session_id=cs_test_fake",
        )
        self.rec(
            "EDGE",
            "GET settle fake session",
            "anon",
            f"http={rget['http']}",
            "unauthenticated settle",
            "INFO",
            {"http": rget["http"], "text": rget.get("text", "")[:300]},
        )
        rfase = self.edge(
            "create-payment-intent",
            self.buyer_jwt,
            {"order_id": fake_order, "payment_intent_id": "pi_fake"},
            qs="?fase2_e2e_settle=1",
        )
        self.rec(
            "EDGE",
            "fase2_e2e_settle JWT",
            "buyer",
            f"http={rfase['http']}",
            "internal settle with user JWT",
            "P0" if rfase["http"] == 200 else "INFO",
            {"http": rfase["http"], "body": _clip(rfase.get("body"))},
        )
        if rfase["http"] == 200:
            self.finding(
                "RTB-EDGE-E2E",
                "P0",
                "fase2_e2e_settle callable with buyer JWT",
                "buyer",
                "verify_jwt=false",
                "POST create-payment-intent?fase2_e2e_settle=1",
                "internal settle authority",
                rfase,
            )

    # ---------- fixtures + financial ----------
    def fixture_product(self, qty: int = 3, price: float = 7.5, title: str | None = None) -> str | None:
        title = title or f"{TAG} item {qty}"
        r = self.rest(
            "POST",
            "products",
            self.seller_jwt,
            {
                "seller_id": self.seller_id,
                "title": title,
                "price": price,
                "quantity": qty,
                "list_on_marketplace": True,
                "is_sold": False,
                "ref_code": f"RTB-{TAG}-{uuid.uuid4().hex[:8]}",
            },
        )
        row = _row(r)
        pid = row.get("id") if row else None
        if not pid:
            # service_role fixture fallback
            r2 = self.rest(
                "POST",
                "products",
                self.svc,
                {
                    "seller_id": self.seller_id,
                    "title": title + " svc",
                    "price": price,
                    "quantity": qty,
                    "list_on_marketplace": True,
                    "is_sold": False,
                    "ref_code": f"RTB-S-{TAG}-{uuid.uuid4().hex[:8]}",
                },
            )
            row = _row(r2)
            pid = row.get("id") if row else None
            self.notes.append(f"product insert seller_jwt={r['http']} svc={r2['http']}")
        if pid:
            self.cleanup.append(("products", f"id=eq.{pid}"))
        return pid

    def fixture_order(
        self,
        product_id: str,
        qty: int = 1,
        extra: dict[str, Any] | None = None,
        token: str | None = None,
    ) -> dict[str, Any] | None:
        body = {
            "buyer_id": self.buyer_id,
            "seller_id": self.seller_id,
            "product_id": product_id,
            "quantity": qty,
            "status": "reserva_pendente",
            "payment_method": "Seguro Fleaber",
            "shipping_method": "hand",
            "price_total": 0.01,
        }
        if extra:
            body.update(extra)
        r = self.rest("POST", "orders", token or self.buyer_jwt, body)
        row = _row(r)
        if row and row.get("id"):
            self.cleanup.append(("orders", f"id=eq.{row['id']}"))
            return {"insert_http": r["http"], "row": row, "err": None}
        return {"insert_http": r["http"], "row": None, "err": _err(r), "body": r.get("body")}

    def attack_orders_and_checkout(self) -> None:
        pid = self.fixture_product(qty=5, price=12.0)
        if not pid:
            self.notes.append("FAIL fixture product")
            return
        self.created_ids["product"] = pid

        # hostile insert: paid + stripe + low price + high qty
        hostile = self.fixture_order(
            pid,
            qty=99,
            extra={
                "status": "pago",
                "amount_paid_cents": 1,
                "stripe_payment_intent_id": "pi_hostile",
                "price_total": 0.01,
                "contract_unit_cents": 1,
                "contract_qty": 99,
                "payment_method": "Seguro Fleaber",
            },
        )
        row = (hostile or {}).get("row")
        self.rec(
            "ORDERS",
            "INSERT paid+stripe+qty99+price0.01",
            "buyer",
            f"http={hostile['insert_http'] if hostile else 0} status={row.get('status') if row else None} "
            f"paid={row.get('amount_paid_cents') if row else None} unit={row.get('contract_unit_cents') if row else None} qty={row.get('quantity') if row else None}",
            "client authority over money/qty",
            "P0"
            if row
            and str(row.get("status")).lower() == "pago"
            and (row.get("amount_paid_cents") or 0)
            else "INFO",
            hostile,
        )
        if row and str(row.get("status")).lower() == "pago" and row.get("amount_paid_cents"):
            self.finding(
                "RTB-ORD-01",
                "P0",
                "Buyer JWT insert order already paid with Stripe IDs",
                "buyer",
                "product exists",
                "POST orders status=pago amount_paid_cents=1",
                "fake capture / stock / wallet path",
                row,
            )

        # legit pending order then mutate
        o1 = self.fixture_order(pid, qty=1)
        oid = (o1 or {}).get("row", {}) or {}
        oid = oid.get("id")
        if oid:
            self.created_ids["order"] = oid
            obs = self.observe(
                "orders",
                f"id=eq.{oid}",
                "id,status,quantity,contract_unit_cents,contract_qty,price_total,amount_paid_cents,stripe_payment_intent_id,buyer_id,seller_id,product_id",
            )
            sealed = _row(obs) or (o1 or {}).get("row")
            self.rec(
                "PRICE/CONTRACT",
                "INSERT seal vs client price_total",
                "buyer",
                f"client_price=0.01 sealed_unit={sealed.get('contract_unit_cents') if sealed else None} qty={sealed.get('quantity') if sealed else None} status={sealed.get('status') if sealed else None}",
                "contract authority",
                "INFO",
                sealed,
            )
            # try mutate qty/price/status/stripe
            for patch, label in [
                ({"quantity": 50, "contract_qty": 50}, "qty"),
                ({"contract_unit_cents": 1, "price_total": 0.01}, "price"),
                ({"status": "pago"}, "status_pago"),
                ({"stripe_payment_intent_id": "pi_x", "amount_paid_cents": 1}, "stripe"),
                ({"buyer_id": self.seller_id}, "swap_buyer"),
                ({"seller_id": self.buyer_id}, "swap_seller"),
                ({"product_id": str(uuid.uuid4())}, "swap_product"),
                ({"status": "premio_rifa", "live_raffle_id": str(uuid.uuid4())}, "premio"),
            ]:
                pr = self.rest("PATCH", f"orders?id=eq.{oid}", self.buyer_jwt, patch)
                after = _row(self.observe("orders", f"id=eq.{oid}", ",".join(["id"] + list(patch.keys()))))
                self.rec(
                    "ORDER FSM",
                    f"PATCH {label}",
                    "buyer",
                    f"http={pr['http']} after={after}",
                    "mutate authoritative fields",
                    "INFO",
                    {"err": _err(pr), "after": after},
                )

            # seller marks platform order paid
            sp = self.rest("PATCH", f"orders?id=eq.{oid}", self.seller_jwt, {"status": "pago"})
            after_s = _row(self.observe("orders", f"id=eq.{oid}", "id,status,amount_paid_cents,stock_units_applied"))
            fake_paid = after_s and str(after_s.get("status")).lower() == "pago"
            self.rec(
                "ORDER FSM",
                "seller PATCH status=pago on Seguro Fleaber unpaid",
                "seller",
                f"http={sp['http']} status={after_s.get('status') if after_s else None}",
                "falsify platform payment",
                "P1" if fake_paid else "INFO",
                {"err": _err(sp), "after": after_s},
            )
            if fake_paid:
                self.finding(
                    "RTB-ORD-02",
                    "P1",
                    "Seller can mark unpaid platform order as pago",
                    "seller",
                    "order Seguro Fleaber unpaid",
                    "PATCH orders status=pago",
                    "stock consume / logistics without capture",
                    after_s,
                )

            # checkout with hostile client amounts
            for ident, tok, extra in [
                (
                    "buyer",
                    self.buyer_jwt,
                    {
                        "buyer_id": self.buyer_id,
                        "order_id": oid,
                        "amount": 50,
                        "item_price": 0.5,
                        "quantity": 1,
                        "shipping": 0,
                        "protection_fee": 0,
                        "shipping_method": "hand",
                        "prize_shipping": False,
                    },
                ),
                (
                    "buyer_prize_spoof",
                    self.buyer_jwt,
                    {
                        "buyer_id": self.buyer_id,
                        "order_id": oid,
                        "shipping_method": "carrier",
                        "prize_shipping": True,
                    },
                ),
                (
                    "buyer_foreign_order",
                    self.buyer_jwt,
                    {
                        "buyer_id": self.buyer_id,
                        "order_id": str(uuid.uuid4()),
                        "shipping_method": "hand",
                    },
                ),
                (
                    "seller_pays_buyer_order",
                    self.seller_jwt,
                    {
                        "buyer_id": self.buyer_id,
                        "order_id": oid,
                        "shipping_method": "hand",
                    },
                ),
                (
                    "anon",
                    self.anon,
                    {
                        "buyer_id": self.buyer_id,
                        "order_id": oid,
                        "shipping_method": "hand",
                    },
                ),
            ]:
                er = self.edge("create-payment-intent", tok, extra)
                amt = None
                if isinstance(er.get("body"), dict):
                    amt = er["body"].get("amount_total") or er["body"].get("amount")
                self.rec(
                    "CHECKOUT",
                    f"create-payment-intent {ident}",
                    ident,
                    f"http={er['http']} amount={amt} err={str(_err(er))[:100]}",
                    "session price vs contract",
                    "INFO",
                    {"http": er["http"], "body": _clip(er.get("body")), "text": (er.get("text") or "")[:400]},
                )

            # shipping aliases
            for method in [
                "hand",
                "HAND",
                " hand ",
                "carrier",
                "€0",
                "free",
                "entrega em mão (€0.00)",
                "Envio transportadora (€3.50)",
                "ctt",
            ]:
                er = self.edge(
                    "create-payment-intent",
                    self.buyer_jwt,
                    {
                        "buyer_id": self.buyer_id,
                        "order_id": oid,
                        "shipping_method": method,
                    },
                )
                amt = None
                if isinstance(er.get("body"), dict):
                    amt = er["body"].get("amount_total") or er["body"].get("amount")
                self.rec(
                    "CHECKOUT",
                    f"shipping_method={method!r}",
                    "buyer",
                    f"http={er['http']} amount={amt}",
                    "shipping undercharge",
                    "INFO",
                    {"http": er["http"], "amount": amt, "err": _err(er)},
                )

        # seller product price drop after order (invariant K)
        if oid and pid:
            sealed_before = _row(
                self.observe("orders", f"id=eq.{oid}", "contract_unit_cents,quantity")
            )
            self.rest("PATCH", f"products?id=eq.{pid}", self.seller_jwt, {"price": 1.0})
            er = self.edge(
                "create-payment-intent",
                self.buyer_jwt,
                {
                    "buyer_id": self.buyer_id,
                    "order_id": oid,
                    "shipping_method": "hand",
                },
            )
            amt = None
            if isinstance(er.get("body"), dict):
                amt = er["body"].get("amount_total") or er["body"].get("amount")
            self.rec(
                "CATALOG×CHECKOUT",
                "seller drops catalog price after order insert",
                "seller+buyer",
                f"sealed={sealed_before} session_amount={amt} http={er['http']}",
                "retroactive contract change",
                "P1"
                if isinstance(amt, (int, float)) and sealed_before and amt < int(sealed_before.get("contract_unit_cents") or 0)
                else "INFO",
                {"sealed": sealed_before, "amount": amt, "err": _err(er)},
            )
            self.rest("PATCH", f"products?id=eq.{pid}", self.svc, {"price": 12.0})

        # off-platform collusion wallet
        o2 = self.fixture_order(
            pid,
            qty=1,
            extra={"payment_method": "MB WAY", "status": "reserva_pendente"},
        )
        oid2 = ((o2 or {}).get("row") or {}).get("id")
        if oid2:
            self.rest("PATCH", f"orders?id=eq.{oid2}", self.seller_jwt, {"status": "pago"})
            paid = _row(self.observe("orders", f"id=eq.{oid2}", "id,status,stock_units_applied,amount_paid_cents"))
            self.rest("PATCH", f"orders?id=eq.{oid2}", self.seller_jwt, {"status": "enviado"})
            self.rest("PATCH", f"orders?id=eq.{oid2}", self.buyer_jwt, {"status": "concluido"})
            fin = _row(
                self.observe(
                    "orders",
                    f"id=eq.{oid2}",
                    "id,status,stock_units_applied,wallet_release_processed_at,amount_paid_cents",
                )
            )
            rel = self.rpc("batata_release_seller_wallet_for_order", self.buyer_jwt, {"p_order_id": oid2})
            w = _row(self.observe("wallets", f"id=eq.{self.seller_id}", "id,balance"))
            self.rec(
                "WALLET×OFF-PLATFORM",
                "MB WAY pago→concluido→release",
                "seller+buyer collusion",
                f"order={fin} release={_clip(rel.get('body'))} http={rel['http']} wallet={w}",
                "mint Fleaber balance without platform capture",
                "P0"
                if rel["http"] == 200 and rel.get("body") is True
                else "INFO",
                {"order": fin, "release": _clip(rel.get("body")), "wallet": w, "paid_after_seller": paid},
            )
            if rel["http"] == 200 and rel.get("body") is True:
                self.finding(
                    "RTB-WAL-OFF",
                    "P0",
                    "Off-platform collusion released seller wallet funds",
                    "buyer+seller",
                    "MB WAY order marked pago by seller",
                    "status pago→enviado→concluido then rpc release",
                    "wallet credit without Stripe capture",
                    {"order": fin, "release": rel.get("body")},
                )

        # cross-user checkout seller_id mismatch in body (should fail)
        if oid:
            er = self.edge(
                "create-payment-intent",
                self.buyer_jwt,
                {
                    "buyer_id": self.buyer_id,
                    "seller_id": self.buyer_id,
                    "order_id": oid,
                    "product_id": pid,
                    "shipping_method": "hand",
                },
            )
            self.rec(
                "AUTHORITY",
                "checkout seller_id swapped in body",
                "buyer",
                f"http={er['http']}",
                "party swap",
                "INFO",
                {"err": _err(er), "body": _clip(er.get("body"))},
            )

    def offers_reviews_chat_disputes(self) -> None:
        pid = self.created_ids.get("product") or self.fixture_product(qty=2, price=9.0, title=f"{TAG} offer")
        if not pid:
            return
        # buyer creates accepted offer
        off = self.rest(
            "POST",
            "product_offers",
            self.buyer_jwt,
            {
                "product_id": pid,
                "buyer_id": self.buyer_id,
                "seller_id": self.seller_id,
                "amount": 1.0,
                "status": "accepted",
                "offered_by": "buyer",
                "responded_at": datetime.now(timezone.utc).isoformat(),
            },
        )
        orow = _row(off)
        self.rec(
            "OFFERS",
            "INSERT offer already accepted amount=1",
            "buyer",
            f"http={off['http']} status={orow.get('status') if orow else None} amount={orow.get('amount') if orow else None}",
            "self-accept discount",
            "P1" if orow and str(orow.get("status")).lower() == "accepted" else "INFO",
            {"err": _err(off), "row": orow},
        )
        oid_off = orow.get("id") if orow else None
        if oid_off:
            self.cleanup.append(("product_offers", f"id=eq.{oid_off}"))
            acc = self.rest("PATCH", f"product_offers?id=eq.{oid_off}", self.buyer_jwt, {"status": "accepted", "amount": 0.5})
            after = _row(self.observe("product_offers", f"id=eq.{oid_off}", "id,status,amount,responded_at"))
            self.rec(
                "OFFERS",
                "buyer self-accept",
                "buyer",
                f"http={acc['http']} after={after}",
                "unauthorized accept",
                "P1" if after and str(after.get("status")).lower() == "accepted" and after.get("responded_at") else "INFO",
                {"err": _err(acc), "after": after},
            )
            # checkout via offer
            o = self.fixture_order(pid, qty=1, extra={"product_offer_id": oid_off, "price_total": 1})
            row = (o or {}).get("row")
            self.rec(
                "OFFERS×ORDER",
                "order with spoof/pending offer id",
                "buyer",
                f"http={(o or {}).get('insert_http')} unit={row.get('contract_unit_cents') if row else None} offer={row.get('product_offer_id') if row else None}",
                "discount without accept",
                "INFO",
                o,
            )

        # reviews
        rev = self.rest(
            "POST",
            "reviews",
            self.buyer_jwt,
            {
                "order_id": self.created_ids.get("order") or str(uuid.uuid4()),
                "buyer_id": self.seller_id,
                "target_id": self.seller_id,
                "stars": 5,
                "comment": f"{TAG} forged",
                "author_role": "vendedor",
                "is_automatic": True,
            },
        )
        self.rec(
            "REVIEWS",
            "INSERT forged role/target/no legitimate tx",
            "buyer",
            f"http={rev['http']}",
            "fake reputation",
            "P1" if rev["http"] in (200, 201) else "INFO",
            {"err": _err(rev), "body": _clip(rev.get("body"))},
        )
        if rev["http"] in (200, 201):
            self.finding(
                "RTB-REV-01",
                "P1",
                "Review inserted without legitimate completed paid order",
                "buyer",
                "any order id",
                "POST reviews",
                "reputation fraud",
                rev,
            )

        # chat insert other thread
        ch = self.rest("GET", "chats?select=id,buyer_id,seller_id&limit=20", self.buyer_jwt)
        rows = ch.get("body") if isinstance(ch.get("body"), list) else []
        foreign = None
        for row in rows:
            if isinstance(row, dict) and self.buyer_id not in {row.get("buyer_id"), row.get("seller_id")}:
                foreign = row
                break
        self.rec(
            "CHAT",
            "SELECT chats",
            "buyer",
            f"http={ch['http']} n={len(rows)} foreign={bool(foreign)}",
            "cross-user chat metadata",
            "P1" if foreign else "INFO",
            {"n": len(rows), "foreign": foreign},
        )
        if foreign:
            self.finding(
                "RTB-CHAT-01",
                "P1",
                "Buyer can SELECT foreign chats",
                "buyer",
                "knows table",
                "GET chats",
                "cross-user conversation metadata",
                foreign,
            )
            msg = self.rest(
                "POST",
                "chat_messages",
                self.buyer_jwt,
                {
                    "chat_id": foreign.get("id"),
                    "sender_id": self.buyer_id,
                    "content": TAG,
                },
            )
            self.rec(
                "CHAT",
                "INSERT message into foreign chat",
                "buyer",
                f"http={msg['http']}",
                "cross-user write",
                "P1" if msg["http"] in (200, 201) else "INFO",
                {"err": _err(msg)},
            )

        # disputes
        d = self.rest(
            "POST",
            "order_disputes",
            self.buyer_jwt,
            {
                "order_id": self.created_ids.get("order") or str(uuid.uuid4()),
                "buyer_id": self.buyer_id,
                "seller_id": self.seller_id,
                "status": "resolvida",
                "seller_refund_percent": 100,
                "admin_resolution": "full_refund",
            },
        )
        self.rec(
            "DISPUTES",
            "INSERT dispute already resolved 100%",
            "buyer",
            f"http={d['http']}",
            "self-resolve refund",
            "INFO",
            {"err": _err(d), "body": _clip(d.get("body"))},
        )

        # storage
        buckets = req(
            "GET",
            f"{self.base}/storage/v1/bucket",
            self.H(self.buyer_jwt, prefer=""),
        )
        self.rec(
            "STORAGE",
            "LIST buckets",
            "buyer",
            f"http={buckets['http']}",
            "bucket enum",
            "INFO",
            {"http": buckets["http"], "body": _clip(buckets.get("body"))},
        )
        if isinstance(buckets.get("body"), list):
            for b in buckets["body"][:8]:
                name = b.get("name") if isinstance(b, dict) else None
                if not name:
                    continue
                ls = req(
                    "POST",
                    f"{self.base}/storage/v1/object/list/{name}",
                    {**self.H(self.buyer_jwt, prefer=""), "Content-Type": "application/json"},
                    {"prefix": "", "limit": 10},
                )
                self.rec(
                    "STORAGE",
                    f"list {name}",
                    "buyer",
                    f"http={ls['http']}",
                    "object leakage",
                    "INFO",
                    {"http": ls["http"], "n": len(ls.get("body") or []) if isinstance(ls.get("body"), list) else None, "err": _err(ls)},
                )

    def live_reservations(self) -> None:
        # create a disposable live + item via seller/service
        live = self.rest(
            "POST",
            "lives",
            self.seller_jwt,
            {
                "seller_id": self.seller_id,
                "title": f"{TAG} live",
                "status": "ended",
                "is_active": False,
            },
        )
        lrow = _row(live)
        lid = lrow.get("id") if lrow else None
        if not lid:
            live = self.rest(
                "POST",
                "lives",
                self.svc,
                {
                    "seller_id": self.seller_id,
                    "vendedor_id": self.seller_id,
                    "title": f"{TAG} live svc",
                    "status": "ended",
                    "is_active": False,
                },
            )
            lrow = _row(live)
            lid = lrow.get("id") if lrow else None
        if not lid:
            self.notes.append(f"live insert failed {live['http']} {_err(live)}")
            return
        self.cleanup.append(("lives", f"id=eq.{lid}"))
        item = self.rest(
            "POST",
            "live_items",
            self.seller_jwt,
            {
                "live_id": lid,
                "seller_id": self.seller_id,
                "title": f"{TAG} li",
                "price": 5.0,
                "quantity": 1,
                "status": "available",
            },
        )
        irow = _row(item)
        iid = irow.get("id") if irow else None
        if not iid:
            item = self.rest(
                "POST",
                "live_items",
                self.svc,
                {
                    "live_id": lid,
                    "seller_id": self.seller_id,
                    "title": f"{TAG} li svc",
                    "price": 5.0,
                    "quantity": 1,
                    "qty": 1,
                    "status": "available",
                },
            )
            irow = _row(item)
            iid = irow.get("id") if irow else None
        if not iid:
            self.notes.append(f"live_item insert failed {item['http']} {_err(item)}")
            return
        self.cleanup.append(("live_items", f"id=eq.{iid}"))

        # buyer insert accepted (should force pending)
        bacc = self.rest(
            "POST",
            "live_reservation_requests",
            self.buyer_jwt,
            {
                "live_id": lid,
                "live_item_id": iid,
                "buyer_id": self.buyer_id,
                "seller_id": self.seller_id,
                "requested_qty": 1,
                "status": "accepted",
            },
        )
        brow = _row(bacc)
        self.rec(
            "LIVE RESERVATIONS",
            "buyer INSERT status=accepted stock=1",
            "buyer",
            f"http={bacc['http']} status={brow.get('status') if brow else None}",
            "capacity bypass",
            "P1" if brow and str(brow.get("status")).lower() in {"accepted", "converted"} else "INFO",
            {"err": _err(bacc), "row": brow},
        )
        if brow and brow.get("id"):
            self.cleanup.append(("live_reservation_requests", f"id=eq.{brow['id']}"))
            # buyer convert
            conv = self.rest(
                "PATCH",
                f"live_reservation_requests?id=eq.{brow['id']}",
                self.buyer_jwt,
                {"status": "converted", "requested_qty": 9},
            )
            after = _row(self.observe("live_reservation_requests", f"id=eq.{brow['id']}", "id,status,requested_qty"))
            self.rec(
                "LIVE RESERVATIONS",
                "buyer PATCH converted qty=9",
                "buyer",
                f"http={conv['http']} after={after}",
                "capacity consume",
                "P1" if after and str(after.get("status")).lower() == "converted" else "INFO",
                {"err": _err(conv), "after": after},
            )

        # seller double-consume: two accepted qty=1 on stock=1
        def seller_accept(i: int) -> dict[str, Any]:
            return self.rest(
                "POST",
                "live_reservation_requests",
                self.seller_jwt,
                {
                    "live_id": lid,
                    "live_item_id": iid,
                    "buyer_id": self.buyer_id,
                    "seller_id": self.seller_id,
                    "requested_qty": 1,
                    "status": "accepted",
                    "external_display_name": f"{TAG}-{i}",
                },
            )

        r1 = seller_accept(1)
        r2 = seller_accept(2)
        rows = []
        for rr in (r1, r2):
            row = _row(rr)
            if row and row.get("id"):
                self.cleanup.append(("live_reservation_requests", f"id=eq.{row['id']}"))
                rows.append(row)
        ok = [x for x in rows if str(x.get("status")).lower() in {"accepted", "converted"}]
        self.rec(
            "LIVE RESERVATIONS",
            "seller two accepted inserts stock=1",
            "seller",
            f"http={[r1['http'], r2['http']]} accepted_n={len(ok)}",
            "oversell capacity",
            "P1" if len(ok) >= 2 else "INFO",
            {"r1": _clip(r1.get("body")), "r2": _clip(r2.get("body")), "err1": _err(r1), "err2": _err(r2)},
        )
        if len(ok) >= 2:
            self.finding(
                "RTB-RES-01",
                "P1",
                "Two accepted reservations on live item qty=1",
                "seller",
                "live_item quantity=1",
                "two POST live_reservation_requests status=accepted",
                "oversell / double capacity",
                ok,
            )

        # race 10x converted
        # first ensure one pending then race accept
        pend = self.rest(
            "POST",
            "live_reservation_requests",
            self.buyer_jwt,
            {
                "live_id": lid,
                "live_item_id": iid,
                "buyer_id": self.buyer_id,
                "seller_id": self.seller_id,
                "requested_qty": 1,
                "status": "pending",
            },
        )
        prow = _row(pend)
        if prow and prow.get("id"):
            self.cleanup.append(("live_reservation_requests", f"id=eq.{prow['id']}"))

        def race_acc(i: int) -> dict[str, Any]:
            return self.rest(
                "POST",
                "live_reservation_requests",
                self.seller_jwt,
                {
                    "live_id": lid,
                    "live_item_id": iid,
                    "buyer_id": self.buyer_id,
                    "seller_id": self.seller_id,
                    "requested_qty": 1,
                    "status": "converted",
                    "external_display_name": f"{TAG}-race-{i}-{uuid.uuid4().hex[:6]}",
                },
            )

        results = []
        with ThreadPoolExecutor(max_workers=10) as ex:
            futs = [ex.submit(race_acc, i) for i in range(10)]
            for f in as_completed(futs):
                results.append(f.result())
        consumed = []
        for rr in results:
            row = _row(rr)
            if row and str(row.get("status")).lower() in {"accepted", "converted"}:
                consumed.append(row)
                if row.get("id"):
                    self.cleanup.append(("live_reservation_requests", f"id=eq.{row['id']}"))
        self.rec(
            "RACE",
            "10x seller INSERT converted stock=1",
            "seller",
            f"consumed={len(consumed)} https={[r['http'] for r in results]}",
            "double capacity",
            "P1" if len(consumed) > 1 else "INFO",
            {"consumed": len(consumed), "errs": [_err(r) for r in results]},
        )
        if len(consumed) > 1:
            self.finding(
                "RTB-RES-RACE",
                "P1",
                "Race: multiple converted reservations on qty=1",
                "seller",
                "live_item qty=1",
                "10 concurrent POST converted",
                "oversell",
                {"n": len(consumed)},
            )

        # stream key select
        sk = self.rest("GET", f"lives?id=eq.{lid}&select=id,mux_stream_key,mux_playback_id", self.buyer_jwt)
        srow = _row(sk)
        has_key = bool(srow and srow.get("mux_stream_key"))
        self.rec(
            "PRIVACY/MUX",
            "SELECT mux_stream_key",
            "buyer",
            f"http={sk['http']} has_key={has_key}",
            "stream key leak",
            "P1" if has_key else "INFO",
            {"row_keys": list(srow.keys()) if srow else None},
        )

    def stock_order_race(self) -> None:
        pid = self.fixture_product(qty=1, price=8.0, title=f"{TAG} stock1")
        if not pid:
            return

        def mk_order(i: int) -> dict[str, Any]:
            return self.rest(
                "POST",
                "orders",
                self.buyer_jwt,
                {
                    "buyer_id": self.buyer_id,
                    "seller_id": self.seller_id,
                    "product_id": pid,
                    "quantity": 1,
                    "status": "reserva_pendente",
                    "payment_method": "Seguro Fleaber",
                    "shipping_method": "hand",
                },
            )

        results = []
        with ThreadPoolExecutor(max_workers=8) as ex:
            futs = [ex.submit(mk_order, i) for i in range(8)]
            for f in as_completed(futs):
                results.append(f.result())
        orders = []
        for rr in results:
            row = _row(rr)
            if row and row.get("id"):
                orders.append(row)
                self.cleanup.append(("orders", f"id=eq.{row['id']}"))
        self.rec(
            "STOCK×ORDERS",
            "8 concurrent orders qty=1 on product stock=1",
            "buyer",
            f"created={len(orders)} https={[r['http'] for r in results]}",
            "two valid sales possible if both checkout",
            "INFO",
            {"created": len(orders), "errs": [_err(r) for r in results if r["http"] not in (200, 201)]},
        )
        # two checkouts concurrent
        sessions = []
        if len(orders) >= 2:

            def ck(oid: str) -> dict[str, Any]:
                return self.edge(
                    "create-payment-intent",
                    self.buyer_jwt,
                    {
                        "buyer_id": self.buyer_id,
                        "order_id": oid,
                        "shipping_method": "hand",
                    },
                )

            with ThreadPoolExecutor(max_workers=2) as ex:
                futs = [ex.submit(ck, orders[0]["id"]), ex.submit(ck, orders[1]["id"])]
                for f in as_completed(futs):
                    sessions.append(f.result())
            ok_sess = [s for s in sessions if s["http"] in (200, 201) and isinstance(s.get("body"), dict) and (s["body"].get("url") or s["body"].get("session_id") or s["body"].get("id"))]
            self.rec(
                "STOCK×STRIPE",
                "2 concurrent Checkout Sessions stock=1",
                "buyer",
                f"ok_sessions={len(ok_sess)} http={[s['http'] for s in sessions]}",
                "two sessions ≠ two captures; still economic risk if both payable",
                "P1" if len(ok_sess) >= 2 else "INFO",
                {"bodies": [_clip(s.get("body")) for s in sessions], "errs": [_err(s) for s in sessions]},
            )
            # store urls for optional stripe complete
            for s in sessions:
                if isinstance(s.get("body"), dict):
                    url = s["body"].get("url")
                    if url:
                        self.created_ids.setdefault("checkout_urls", "")
                        self.notes.append(f"CHECKOUT_URL {url}")

        # seller off-platform double pago on two orders stock=1
        mb_orders = []
        for i in range(2):
            o = self.fixture_order(
                pid,
                1,
                extra={"payment_method": "MB WAY", "status": "reserva_pendente"},
            )
            row = (o or {}).get("row")
            if row:
                mb_orders.append(row)

        def mark_pago(oid: str) -> dict[str, Any]:
            return self.rest("PATCH", f"orders?id=eq.{oid}", self.seller_jwt, {"status": "pago"})

        if len(mb_orders) >= 2:
            with ThreadPoolExecutor(max_workers=2) as ex:
                futs = [ex.submit(mark_pago, mb_orders[0]["id"]), ex.submit(mark_pago, mb_orders[1]["id"])]
                pay_res = [f.result() for f in as_completed(futs)]
            after = self.observe(
                "orders",
                f"id=in.({mb_orders[0]['id']},{mb_orders[1]['id']})",
                "id,status,stock_units_applied,quantity",
            )
            prod = _row(self.observe("products", f"id=eq.{pid}", "id,quantity"))
            paid_n = 0
            if isinstance(after.get("body"), list):
                paid_n = sum(1 for x in after["body"] if str(x.get("status")).lower() == "pago")
            stock_neg = False
            try:
                stock_neg = float(prod.get("quantity") or 0) < 0
            except (TypeError, ValueError):
                pass
            self.rec(
                "STOCK×MBWAY",
                "2 concurrent seller pago on stock=1",
                "seller",
                f"paid_n={paid_n} product_qty={prod} http={[p['http'] for p in pay_res]}",
                "two valid sales / negative stock",
                "P1" if paid_n >= 2 or stock_neg else "INFO",
                {"orders": after.get("body"), "product": prod, "errs": [_err(p) for p in pay_res]},
            )
            if paid_n >= 2:
                self.finding(
                    "RTB-STK-01",
                    "P1",
                    "Two MB WAY orders marked pago on product stock=1",
                    "seller",
                    "product quantity=1, two unpaid MB WAY orders",
                    "concurrent PATCH status=pago",
                    "oversell of last unit",
                    {"paid_n": paid_n, "product": prod, "orders": after.get("body")},
                )

    def payout_and_tips_refunds(self) -> None:
        # payout amount > balance
        r = self.edge(
            "create-connect-account",
            self.seller_jwt,
            {"amount": 99999999, "idempotency_key": TAG + "huge", "user_id": self.seller_id},
        )
        self.rec(
            "PAYOUT",
            "withdraw more than balance",
            "seller",
            f"http={r['http']}",
            "overdraw",
            "INFO",
            {"err": _err(r), "body": _clip(r.get("body"))},
        )
        # payout other user
        r2 = self.edge(
            "create-connect-account",
            self.buyer_jwt,
            {"amount": 100, "idempotency_key": TAG + "xuser", "user_id": self.seller_id},
        )
        self.rec(
            "PAYOUT",
            "buyer payout to seller user_id",
            "buyer",
            f"http={r2['http']}",
            "identity swap",
            "INFO",
            {"err": _err(r2), "body": _clip(r2.get("body"))},
        )
        # dual keys same amount race (may no-op if no balance)
        def po(i: int) -> dict[str, Any]:
            return self.edge(
                "create-connect-account",
                self.seller_jwt,
                {"amount": 100, "idempotency_key": f"{TAG}-pay-{i}-{uuid.uuid4().hex[:8]}"},
            )

        races = []
        with ThreadPoolExecutor(max_workers=4) as ex:
            futs = [ex.submit(po, i) for i in range(4)]
            for f in as_completed(futs):
                races.append(f.result())
        self.rec(
            "PAYOUT RACE",
            "4 concurrent payouts different keys amount=100",
            "seller",
            f"http={[x['http'] for x in races]}",
            "duplicate transfer",
            "INFO",
            {"bodies": [_clip(x.get("body")) for x in races], "errs": [_err(x) for x in races]},
        )

        # refund other seller's order
        oid = self.created_ids.get("order")
        if oid:
            rb = self.edge("refund-order", self.buyer_jwt, {"order_id": oid})
            rs = self.edge("refund-order", self.seller_jwt, {"order_id": oid})
            self.rec(
                "REFUNDS",
                "refund-order unpaid",
                "buyer then seller",
                f"buyer={rb['http']} seller={rs['http']}",
                "unauthorized refund",
                "INFO",
                {"buyer": _clip(rb.get("body")), "seller": _clip(rs.get("body"))},
            )

        # tips
        t = self.edge(
            "create-live-tip-checkout",
            self.buyer_jwt,
            {"seller_id": self.seller_id, "amount_eur": 0.5, "live_id": str(uuid.uuid4())},
        )
        self.rec(
            "TIPS",
            "tip checkout tiny amount / fake live",
            "buyer",
            f"http={t['http']}",
            "unbounded tip / missing live",
            "INFO",
            {"err": _err(t), "body": _clip(t.get("body"))},
        )

        # pairing brute
        pair = self.edge("ps-pairing-claim", self.anon, {"code": "123456", "device_id": "rtb"})
        leaked_secret = False
        if isinstance(pair.get("body"), dict):
            b = pair["body"]
            leaked_secret = any(k in b for k in ("device_token", "service_role", "anon_key"))
        self.rec(
            "PS/OCR",
            "pairing claim 123456",
            "anon",
            f"http={pair['http']} leak={leaked_secret} keys={list(pair.get('body').keys()) if isinstance(pair.get('body'), dict) else None}",
            "device token / supabase url leak",
            "P1" if leaked_secret else "INFO",
            {"body": _clip(pair.get("body"))},
        )

        # mux as buyer
        mux = self.edge("create-mux-live", self.buyer_jwt, {"title": f"{TAG} hijack"})
        self.rec(
            "MUX",
            "buyer create-mux-live",
            "buyer",
            f"http={mux['http']}",
            "buyer acts as seller/broadcaster",
            "P1" if mux["http"] in (200, 201) and isinstance(mux.get("body"), dict) and mux["body"].get("stream_key") else "INFO",
            {"err": _err(mux), "body_keys": list(mux.get("body").keys()) if isinstance(mux.get("body"), dict) else None},
        )
        if mux["http"] in (200, 201) and isinstance(mux.get("body"), dict) and mux["body"].get("stream_key"):
            self.finding(
                "RTB-MUX-01",
                "P1",
                "Buyer JWT obtained Mux stream key",
                "buyer",
                "create-mux-live verify_jwt",
                "POST create-mux-live as buyer",
                "unauthorized broadcast / cost",
                {"keys": list(mux["body"].keys())},
            )

    def products_rls(self) -> None:
        # buyer update seller product
        pid = self.created_ids.get("product")
        if not pid:
            return
        r = self.rest("PATCH", f"products?id=eq.{pid}", self.buyer_jwt, {"price": 0.5, "quantity": 999})
        after = _row(self.observe("products", f"id=eq.{pid}", "id,price,quantity,seller_id"))
        changed = False
        if after:
            try:
                changed = float(after.get("price") or 0) == 0.5 or int(after.get("quantity") or 0) == 999
            except (TypeError, ValueError):
                changed = False
        self.rec(
            "PRODUCTS",
            "buyer PATCH seller product price/qty",
            "buyer",
            f"http={r['http']} after={after}",
            "catalog hijack",
            "P1" if changed else "INFO",
            {"err": _err(r), "after": after},
        )
        if changed:
            self.finding(
                "RTB-PRD-01",
                "P1",
                "Buyer modified seller product price/qty",
                "buyer",
                "known product UUID",
                "PATCH products",
                "economic catalog hijack",
                after,
            )
            self.rest("PATCH", f"products?id=eq.{pid}", self.svc, {"price": 12.0, "quantity": 5})

    def cleanup_safe(self) -> None:
        # best-effort; service_role observation/cleanup only
        for table, filt in reversed(self.cleanup):
            try:
                self.rest("DELETE", f"{table}?{filt}", self.svc)
            except Exception:
                pass


def _row(r: dict[str, Any] | None) -> dict[str, Any] | None:
    if not r:
        return None
    b = r.get("body")
    if isinstance(b, list) and b and isinstance(b[0], dict):
        return b[0]
    if isinstance(b, dict) and b.get("id"):
        return b
    return None


def _err(r: dict[str, Any]) -> Any:
    b = r.get("body")
    if isinstance(b, dict):
        return b.get("message") or b.get("error") or b.get("hint") or {k: b[k] for k in list(b)[:6]}
    if isinstance(b, str):
        return b[:200]
    return r.get("text", "")[:200]


def _clip(body: Any, n: int = 800) -> Any:
    try:
        s = json.dumps(body, default=str)
    except TypeError:
        s = str(body)
    if len(s) > n:
        return s[:n] + "…"
    if isinstance(body, (dict, list, str, int, float, bool)) or body is None:
        return body
    return s


def _denied(r: dict[str, Any]) -> bool:
    e = str(_err(r)).lower()
    return any(
        x in e
        for x in (
            "permission",
            "denied",
            "not allowed",
            "unauthorized",
            "42501",
            "jwt",
            "row-level",
            "rls",
            "execute",
        )
    )


def main() -> int:
    env = load_env(ENV_PATH)
    p = Probe(env)
    p.login()
    print("PASS1 inventory/auth/rls/rpc/edge", flush=True)
    p.pass1_inventory()
    p.jwt_alg_none()
    p.rls_sweep()
    p.privilege_and_money_cols()
    p.rpc_hostile()
    p.edge_hostile()
    print("PASS1 orders/checkout", flush=True)
    p.attack_orders_and_checkout()
    print("PASS2 offers/reviews/chat/products", flush=True)
    p.offers_reviews_chat_disputes()
    p.products_rls()
    print("PASS3 live/races/payout", flush=True)
    p.live_reservations()
    p.stock_order_race()
    p.payout_and_tips_refunds()
    p.cleanup_safe()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    raw_path = OUT_DIR / f"RT_BLIND_INDEP_20260829_RAW.json"
    payload = {
        "frozen_at": datetime.now(timezone.utc).isoformat(),
        "project": PROJECT,
        "tag": TAG,
        "inventory": p.inventory,
        "findings": p.findings,
        "matrix": p.matrix,
        "notes": p.notes,
        "created_ids": {k: v for k, v in p.created_ids.items() if k != "checkout_urls"},
    }
    raw_path.write_text(json.dumps(payload, indent=2, default=str), encoding="utf-8")
    print(f"WROTE {raw_path}", flush=True)
    print(f"FINDINGS {len(p.findings)} MATRIX {len(p.matrix)}", flush=True)
    for f in p.findings:
        print(f"  {f['severity']} {f['id']} {f['title']}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
