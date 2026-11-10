#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""H10 117 — artigo comercial, chat_image, conjunto real, textos limpos."""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENV = ROOT / "tool" / "live_ops_production.env"
REP = ROOT / "tool" / "reports" / "fleahub_h10_mensagens_117_2026-10-26"

CHAT_ID = "84cd817c-9068-4d0b-960a-8d41110da40b"
MARIANA = "08c9dca8-3707-4ee5-9f43-b33293085d6a"
SHOP = "06ed6f36-acfb-4c36-a3cf-d77a0eeeb451"
MAIN = "b9aec2ff-56e3-4acd-9ff4-d6205ed1f40f"
TAG = "H10_TESTE_COMPLETO_20261026"


def load_env() -> tuple[str, str]:
    url = key = ""
    for line in ENV.read_text(encoding="utf-8").splitlines():
        if line.startswith("SUPABASE_URL="):
            url = line.split("=", 1)[1].strip()
        elif line.startswith("SUPABASE_SERVICE_ROLE_KEY="):
            key = line.split("=", 1)[1].strip()
    if not url or not key:
        raise SystemExit("missing SUPABASE_URL / SERVICE_ROLE_KEY")
    return url, key


class Sb:
    def __init__(self, url: str, key: str):
        self.url = url.rstrip("/")
        self.key = key

    def _req(
        self,
        method: str,
        path: str,
        body=None,
        *,
        prefer: str = "return=representation",
        content_type: str = "application/json",
        raw: bytes | None = None,
    ):
        headers = {
            "apikey": self.key,
            "Authorization": f"Bearer {self.key}",
            "Content-Type": content_type,
            "Prefer": prefer,
        }
        data = raw
        if body is not None and raw is None:
            data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        req = urllib.request.Request(
            self.url + path, data=data, headers=headers, method=method
        )
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                raw_body = resp.read()
                if not raw_body:
                    return None
                return json.loads(raw_body.decode("utf-8"))
        except urllib.error.HTTPError as e:
            err = e.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"{method} {path} -> {e.code}: {err}") from e

    def get(self, path: str):
        return self._req("GET", path, prefer="return=representation")

    def post(self, path: str, body, prefer="return=representation"):
        return self._req("POST", path, body, prefer=prefer)

    def patch(self, path: str, body, prefer="return=minimal"):
        return self._req("PATCH", path, body, prefer=prefer)

    def delete(self, path: str):
        return self._req("DELETE", path, prefer="return=minimal")

    def upload_private(self, storage_path: str, data: bytes, content_type: str):
        path = f"/storage/v1/object/fleaber_private/{storage_path}"
        headers = {
            "apikey": self.key,
            "Authorization": f"Bearer {self.key}",
            "Content-Type": content_type,
            "x-upsert": "true",
        }
        req = urllib.request.Request(
            self.url + path, data=data, headers=headers, method="POST"
        )
        with urllib.request.urlopen(req, timeout=90) as resp:
            return resp.read()


def fj(obj: dict) -> str:
    return "FLEABER_JSON_V1:" + json.dumps(obj, ensure_ascii=False, separators=(",", ":"))


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def main() -> int:
    url, key = load_env()
    sb = Sb(url, key)
    REP.mkdir(parents=True, exist_ok=True)
    print(f"=== H10 117 polish chat={CHAT_ID} ===")

    img_main = (
        "https://images.unsplash.com/photo-1551028719-00167b16eac5"
        "?auto=format&fit=crop&w=800&q=80"
    )
    sb.patch(
        f"/rest/v1/products?id=eq.{MAIN}",
        {
            "title": "Casaco de ganga Levi's azul — tamanho M",
            "price": 42.0,
            "description": (
                "Casaco de ganga Levi's em azul clássico, tamanho M. "
                "Usado com cuidado, sem rasgões. Ideal para meia-estação. "
                "Entrega combinada na conversa."
            ),
            "state": "Muito bom",
            "image_urls": [img_main],
            "quantity": 1,
            "is_sold": False,
            "list_on_marketplace": True,
        },
    )
    print(f"main_product_updated={MAIN}")

    p2 = sb.post(
        "/rest/v1/products",
        {
            "seller_id": SHOP,
            "title": "Camisola knit bege — tamanho S",
            "price": 18.5,
            "ref_code": "H10BND2",
            "description": f"Camisola de malha bege, leve, tamanho S. Seed {TAG}",
            "state": "Bom",
            "image_urls": [
                "https://images.unsplash.com/photo-1434389677669-e08b4cac3105"
                "?auto=format&fit=crop&w=800&q=80"
            ],
            "list_on_marketplace": True,
            "available_for_live": False,
            "is_sold": False,
            "quantity": 1,
        },
    )
    p3 = sb.post(
        "/rest/v1/products",
        {
            "seller_id": SHOP,
            "title": "Cachecol de lã cinzento",
            "price": 12.0,
            "ref_code": "H10BND3",
            "description": f"Cachecol de lã cinzento, macio. Seed {TAG}",
            "state": "Bom",
            "image_urls": [
                "https://images.unsplash.com/photo-1601924994987-69e26d50dc26"
                "?auto=format&fit=crop&w=800&q=80"
            ],
            "list_on_marketplace": True,
            "available_for_live": False,
            "is_sold": False,
            "quantity": 1,
        },
    )
    p2_id = p2[0]["id"]
    p3_id = p3[0]["id"]
    print(f"bundle_products={p2_id},{p3_id}")

    subtotal = 42.0 + 18.5 + 12.0
    discount = 7.25
    total = round(subtotal - discount, 2)
    bundle = sb.post(
        "/rest/v1/product_bundles",
        {
            "seller_id": SHOP,
            "buyer_id": MARIANA,
            "chat_id": CHAT_ID,
            "product_ids": [MAIN, p2_id, p3_id],
            "subtotal_eur": subtotal,
            "discount_pct": round((discount / subtotal) * 100, 1),
            "discount_eur": discount,
            "total_eur": total,
            "status": "pending",
        },
    )
    bundle_id = bundle[0]["id"]
    print(f"bundle_id={bundle_id}")

    tech = sb.get(
        "/rest/v1/chat_messages?chat_id=eq."
        + CHAT_ID
        + "&text=like.*Conjunto*demonstracao*&select=id"
    ) or []
    for m in tech:
        sb.delete(f"/rest/v1/chat_messages?id=eq.{m['id']}")

    now = datetime.now(timezone.utc)
    bundle_msg = sb.post(
        "/rest/v1/chat_messages",
        {
            "sender_id": MARIANA,
            "receiver_id": SHOP,
            "chat_id": CHAT_ID,
            "text": fj(
                {
                    "kind": "bundle_proposal",
                    "bundle_id": bundle_id,
                    "product_ids": [MAIN, p2_id, p3_id],
                    "product_quantities": {
                        MAIN: 1,
                        p2_id: 1,
                        p3_id: 1,
                    },
                    "seller_id": SHOP,
                    "buyer_id": MARIANA,
                    "subtotal_eur": subtotal,
                    "discount_pct": round((discount / subtotal) * 100, 1),
                    "discount_eur": discount,
                    "total_eur": total,
                    "request_mode": "price_proposal",
                    "v": 1,
                    "proposal_ts": iso(now),
                }
            ),
            "is_read": False,
            "is_reservation": False,
            "created_at": iso(now - timedelta(minutes=3)),
        },
    )
    print(f"bundle_msg={bundle_msg[0]['id']}")

    url_msgs = (
        sb.get(
            "/rest/v1/chat_messages?chat_id=eq."
            + CHAT_ID
            + "&text=like.*picsum.photos*&select=id"
        )
        or []
    )
    for m in url_msgs:
        sb.delete(f"/rest/v1/chat_messages?id=eq.{m['id']}")

    img_url = (
        "https://images.unsplash.com/photo-1523381216712-77745c48ceeb"
        "?auto=format&fit=crop&w=640&q=70"
    )
    with urllib.request.urlopen(img_url, timeout=60) as resp:
        img_bytes = resp.read()
    storage_path = (
        f"chat_uploads/{MARIANA}/{CHAT_ID}/h10_117_"
        f"{datetime.now().strftime('%Y%m%d%H%M%S')}.jpg"
    )
    chat_image_ok = False
    chat_image_msg_id = None
    try:
        sb.upload_private(storage_path, img_bytes, "image/jpeg")
        print(f"uploaded={storage_path}")
        img_msg = sb.post(
            "/rest/v1/chat_messages",
            {
                "sender_id": MARIANA,
                "receiver_id": SHOP,
                "chat_id": CHAT_ID,
                "text": fj({"kind": "chat_image", "path": storage_path, "url": "", "v": 2}),
                "is_read": False,
                "is_reservation": False,
                "created_at": iso(now - timedelta(minutes=2)),
            },
        )
        chat_image_msg_id = img_msg[0]["id"]
        chat_image_ok = True
        print(f"chat_image_msg={chat_image_msg_id}")
    except Exception as e:
        print(f"WARN chat_image failed: {e}")

    replacements = [
        (
            "Texto%20longo%20de%20teste",
            "Olá! Queria confirmar que o balão acomoda várias linhas sem partir "
            "o layout. Preciso de ver o preço, o envio, a protecção Fleaber e o "
            "prazo de reserva no mesmo ecrã, com scroll confortável até ao fim "
            "da conversa.",
        ),
        (
            "Mensagem%20final%20do%20vendedor",
            "Mensagem do vendedor: o histórico desta conversa está pronto para revisão visual.",
        ),
        (
            "Ola!%20Queria%20ver",
            "Olá! Tenho interesse neste casaco de ganga. Ainda está disponível?",
        ),
        (
            "Ola!%20Podes%20reservar",
            "Olá! Sim, podes reservar ou fazer uma proposta — responde aqui na conversa.",
        ),
    ]
    for like, text in replacements:
        rows = (
            sb.get(
                f"/rest/v1/chat_messages?chat_id=eq.{CHAT_ID}&text=like.*{like}*&select=id"
            )
            or []
        )
        for m in rows:
            sb.patch(f"/rest/v1/chat_messages?id=eq.{m['id']}", {"text": text})

    sys_rows = (
        sb.get(
            f"/rest/v1/chat_messages?chat_id=eq.{CHAT_ID}&text=like.*fleaber_res*&select=id,text"
        )
        or []
    )
    for m in sys_rows:
        clean = m["text"].replace("[H10_TESTE_COMPLETO_20261026] ", "")
        clean = clean.replace(
            "Artigo A - camisola azul",
            "Casaco de ganga Levi's azul — tamanho M",
        )
        if clean != m["text"]:
            sb.patch(f"/rest/v1/chat_messages?id=eq.{m['id']}", {"text": clean})

    for kind, title in (
        (
            "pending_expired",
            "O prazo do pedido de reserva expirou.",
        ),
        (
            "guaranteed_expired",
            "A reserva garantida expirou.",
        ),
    ):
        rows = (
            sb.get(
                f"/rest/v1/chat_messages?chat_id=eq.{CHAT_ID}&text=like.*{kind}*&select=id"
            )
            or []
        )
        full_kind = (
            "pending_expired_buyer_notice"
            if kind.startswith("pending")
            else "guaranteed_expired_buyer_notice"
        )
        for m in rows:
            sb.patch(
                f"/rest/v1/chat_messages?id=eq.{m['id']}",
                {"text": fj({"kind": full_kind, "title": title})},
            )

    sb.patch(
        f"/rest/v1/chats?id=eq.{CHAT_ID}",
        {
            "last_message": "Proposta de conjunto · 3 artigos",
            "last_message_time": iso(now),
            "product_id": MAIN,
        },
    )

    msgs = sb.get(
        f"/rest/v1/chat_messages?chat_id=eq.{CHAT_ID}&select=id&order=created_at.asc"
    ) or []
    inventory = {
        "chat_id": CHAT_ID,
        "main_product_id": MAIN,
        "main_product_title": "Casaco de ganga Levi's azul — tamanho M",
        "bundle_id": bundle_id,
        "bundle_product_ids": [MAIN, p2_id, p3_id],
        "chat_image_ok": chat_image_ok,
        "chat_image_msg_id": chat_image_msg_id,
        "chat_image_path": storage_path if chat_image_ok else None,
        "message_count": len(msgs),
        "tag": TAG,
        "account": "mareantiga@gmail.com",
        "shop_id": SHOP,
    }
    (REP / "INVENTARIO_DADOS_TESTE.json").write_text(
        json.dumps(inventory, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps(inventory, ensure_ascii=False))
    print("=== DONE 117 polish ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
