#!/usr/bin/env python3
# -*- coding: utf-8 -*-
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

req = urllib.request.Request(
    "https://picsum.photos/seed/h10fleaber117c/640/480.jpg",
    headers={"User-Agent": "FleaberH10/1.0"},
)
img = urllib.request.urlopen(req, timeout=60).read()
print("bytes", len(img))

storage_path = (
    f"chat_uploads/{h10.MARIANA}/{h10.CHAT_ID}/h10_117_"
    f"{datetime.now().strftime('%Y%m%d%H%M%S')}.jpg"
)
sb.upload_private(storage_path, img, "image/jpeg")
print("uploaded", storage_path)

# signed URL 30 days
sign_req = urllib.request.Request(
    f"{url}/storage/v1/object/sign/fleaber_private/{storage_path}",
    data=json.dumps({"expiresIn": 60 * 60 * 24 * 30}).encode(),
    headers={
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    },
    method="POST",
)
signed = json.loads(urllib.request.urlopen(sign_req).read().decode())
signed_path = signed.get("signedURL") or signed.get("signedUrl") or ""
if signed_path.startswith("/"):
    signed_url = url + "/storage/v1" + signed_path
else:
    signed_url = signed_path
print("signed", signed_url[:120])

now = datetime.now(timezone.utc)
# Prefer path-only (constraint-safe). If insert fails, try with signed url.
payloads = [
    {"kind": "chat_image", "path": storage_path, "url": "", "v": 2},
    {
        "kind": "chat_image",
        "path": storage_path,
        "url": signed_url,
        "v": 2,
    },
]
msg_id = None
for p in payloads:
    try:
        msg = sb.post(
            "/rest/v1/chat_messages",
            {
                "sender_id": h10.MARIANA,
                "receiver_id": h10.SHOP,
                "chat_id": h10.CHAT_ID,
                "text": h10.fj(p),
                "is_read": False,
                "is_reservation": False,
                "created_at": h10.iso(now - timedelta(minutes=1)),
            },
        )
        msg_id = msg[0]["id"]
        print("inserted", msg_id, "keys", list(p.keys()), "url_empty", not p.get("url"))
        break
    except Exception as e:
        print("insert fail", e)

inv_path = h10.REP / "INVENTARIO_DADOS_TESTE.json"
inv = json.loads(inv_path.read_text(encoding="utf-8")) if inv_path.exists() else {}
inv.update(
    {
        "bundle_id": "5d1ab2ec-9136-4b29-830f-b204d3e6ab63",
        "bundle_product_ids": [
            h10.MAIN,
            "b9baaaa6-014f-4822-8a2b-ca7c2cc398ff",
            "c78c84d6-7268-4bea-bc74-15fa7237261e",
        ],
        "chat_image_ok": msg_id is not None,
        "chat_image_msg_id": msg_id,
        "chat_image_path": storage_path,
        "chat_image_note": (
            "Bucket fleaber_private estava ausente na API Storage; "
            "criado nesta entrega 117 para permitir chat_image real."
            if msg_id
            else "falhou insert chat_image"
        ),
    }
)
msgs = (
    sb.get(
        f"/rest/v1/chat_messages?chat_id=eq.{h10.CHAT_ID}&select=id&order=created_at.asc"
    )
    or []
)
inv["message_count"] = len(msgs)
inv_path.write_text(json.dumps(inv, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(inv, ensure_ascii=False))
