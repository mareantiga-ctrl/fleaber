#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from __future__ import annotations

import json
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path
import importlib.util

spec = importlib.util.spec_from_file_location(
    "h10", Path(__file__).with_name("h10_fix_117_polish.py")
)
h10 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h10)

url, key = h10.load_env()
sb = h10.Sb(url, key)
CHAT_ID = h10.CHAT_ID
MARIANA = h10.MARIANA
SHOP = h10.SHOP
MAIN = h10.MAIN
REP = h10.REP

img_candidates = [
    "https://picsum.photos/seed/h10fleaber117/640/480.jpg",
    "https://images.unsplash.com/photo-1541099649105-f69ad21f3246?auto=format&fit=crop&w=640&q=70",
    "https://images.unsplash.com/photo-1551028719-00167b16eac5?auto=format&fit=crop&w=640&q=70",
]
img_bytes = None
for u in img_candidates:
    try:
        req = urllib.request.Request(u, headers={"User-Agent": "FleaberH10/1.0"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            img_bytes = resp.read()
        print("downloaded", u, len(img_bytes))
        break
    except Exception as e:
        print("fail", u, e)

chat_image_ok = False
storage_path = None
chat_image_msg_id = None
now = datetime.now(timezone.utc)
if img_bytes:
    storage_path = (
        f"chat_uploads/{MARIANA}/{CHAT_ID}/h10_117_"
        f"{datetime.now().strftime('%Y%m%d%H%M%S')}.jpg"
    )
    try:
        sb.upload_private(storage_path, img_bytes, "image/jpeg")
        print("uploaded", storage_path)
        img_msg = sb.post(
            "/rest/v1/chat_messages",
            {
                "sender_id": MARIANA,
                "receiver_id": SHOP,
                "chat_id": CHAT_ID,
                "text": h10.fj(
                    {"kind": "chat_image", "path": storage_path, "url": "", "v": 2}
                ),
                "is_read": False,
                "is_reservation": False,
                "created_at": h10.iso(now - timedelta(minutes=2)),
            },
        )
        chat_image_msg_id = img_msg[0]["id"]
        chat_image_ok = True
        print("chat_image_msg", chat_image_msg_id)
    except Exception as e:
        print("WARN upload/insert", e)

replacements = [
    (
        "Texto%20longo%20de%20teste",
        "Olá! Queria confirmar que o balão acomoda várias linhas sem partir o layout. "
        "Preciso de ver o preço, o envio, a protecção Fleaber e o prazo de reserva no "
        "mesmo ecrã, com scroll confortável até ao fim da conversa.",
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
        print("patched", m["id"], like)

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
        print("sys cleaned", m["id"])

for kind, title in (
    ("pending_expired", "O prazo do pedido de reserva expirou."),
    ("guaranteed_expired", "A reserva garantida expirou."),
):
    rows = (
        sb.get(
            f"/rest/v1/chat_messages?chat_id=eq.{CHAT_ID}&text=like.*{kind}*&select=id"
        )
        or []
    )
    full = (
        "pending_expired_buyer_notice"
        if kind.startswith("pending")
        else "guaranteed_expired_buyer_notice"
    )
    for m in rows:
        sb.patch(
            f"/rest/v1/chat_messages?id=eq.{m['id']}",
            {"text": h10.fj({"kind": full, "title": title})},
        )
        print("expired", m["id"])

sb.patch(
    f"/rest/v1/chats?id=eq.{CHAT_ID}",
    {
        "last_message": "Proposta de conjunto · 3 artigos",
        "last_message_time": h10.iso(now),
        "product_id": MAIN,
    },
)

inv_path = REP / "INVENTARIO_DADOS_TESTE.json"
inv = {}
if inv_path.exists():
    inv = json.loads(inv_path.read_text(encoding="utf-8"))
msgs = (
    sb.get(
        f"/rest/v1/chat_messages?chat_id=eq.{CHAT_ID}&select=id&order=created_at.asc"
    )
    or []
)
inv.update(
    {
        "chat_id": CHAT_ID,
        "main_product_id": MAIN,
        "main_product_title": "Casaco de ganga Levi's azul — tamanho M",
        "chat_image_ok": chat_image_ok,
        "chat_image_msg_id": chat_image_msg_id,
        "chat_image_path": storage_path if chat_image_ok else None,
        "message_count": len(msgs),
        "account": "mareantiga@gmail.com",
        "shop_id": SHOP,
        "tag": h10.TAG,
    }
)
inv_path.parent.mkdir(parents=True, exist_ok=True)
inv_path.write_text(json.dumps(inv, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(inv, ensure_ascii=False))
print("DONE continue")
