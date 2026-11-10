#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""H10 117.1 — limpar textos técnicos, foto casaco, bucket privado."""
from __future__ import annotations

import json
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENV = ROOT / "tool" / "live_ops_production.env"
REP = ROOT / "tool" / "reports" / "fleahub_h10_mensagens_117_1_2026-10-26"
CHAT = "84cd817c-9068-4d0b-960a-8d41110da40b"
MARIANA = "08c9dca8-3707-4ee5-9f43-b33293085d6a"
SHOP = "06ed6f36-acfb-4c36-a3cf-d77a0eeeb451"


def load_env():
    env = {}
    for line in ENV.read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip()
    return env["SUPABASE_URL"].rstrip("/"), env["SUPABASE_SERVICE_ROLE_KEY"]


class Sb:
    def __init__(self, url, key):
        self.url, self.key = url, key

    def _req(self, method, path, body=None, prefer="return=representation", raw=None, ctype="application/json"):
        headers = {
            "apikey": self.key,
            "Authorization": f"Bearer {self.key}",
            "Content-Type": ctype,
            "Prefer": prefer,
        }
        data = raw if raw is not None else (None if body is None else json.dumps(body, ensure_ascii=False).encode("utf-8"))
        req = urllib.request.Request(self.url + path, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=90) as resp:
                b = resp.read()
                return json.loads(b.decode()) if b else None
        except urllib.error.HTTPError as e:
            raise RuntimeError(f"{method} {path} -> {e.code}: {e.read().decode()[:500]}") from e

    def get(self, path):
        return self._req("GET", path) or []

    def patch(self, path, body):
        return self._req("PATCH", path, body, prefer="return=minimal")

    def post(self, path, body, prefer="return=representation"):
        return self._req("POST", path, body, prefer=prefer)

    def delete(self, path):
        return self._req("DELETE", path, prefer="return=minimal")

    def upload(self, storage_path, data, ctype):
        return self._req(
            "POST",
            f"/storage/v1/object/fleaber_private/{storage_path}",
            raw=data,
            ctype=ctype,
            prefer="return=representation",
        )

    def bucket_update(self, public: bool):
        body = json.dumps({"public": public}).encode()
        req = urllib.request.Request(
            self.url + "/storage/v1/bucket/fleaber_private",
            data=body,
            headers={
                "apikey": self.key,
                "Authorization": f"Bearer {self.key}",
                "Content-Type": "application/json",
            },
            method="PUT",
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.read().decode()


def fj(obj):
    return "FLEABER_JSON_V1:" + json.dumps(obj, ensure_ascii=False, separators=(",", ":"))


def main():
    url, key = load_env()
    sb = Sb(url, key)
    REP.mkdir(parents=True, exist_ok=True)
    print("=== H10 117.1 data + storage ===")

    # 1) Bucket privado
    print("bucket_private", sb.bucket_update(False))

    # 2) Mensagem 75 — reserva confirmada sem marcador técnico no texto
    #    (o marcador continua no fim para o parser, mas com corpo limpo)
    body75 = (
        "Fleaber · sistema\n"
        "Reserva garantida\n"
        "Casaco de ganga Levi's azul — tamanho M\n"
        "1 unidade reservada. Efetua o pagamento no saco até ao fim do prazo indicado.\n"
        "\n"
        "[[fleaber_res:reservation_guaranteed:43e80fc9-e729-45d9-bd64-ade8473b41ab]]"
    )
    sb.patch(f"/rest/v1/chat_messages?id=eq.75", {"text": body75})
    print("patched 75")

    # 3) Limpar notes/titles técnicos em JSON
    patches = {
        50: fj({"amount": 10, "kind": "price_offer", "note": "Proposta inicial"}),
        52: fj({"amount": 11.5, "kind": "price_offer", "note": "Nova proposta"}),
        54: fj(
            {
                "qty": 1,
                "title": "Casaco de ganga Levi's azul — tamanho M",
                "order_id": "b4388d54-752a-46bc-96f1-e451282e7ad8",
                "kind": "reservation_request",
            }
        ),
        69: fj(
            {
                "kind": "cancel_request",
                "reason": "Mudei de ideias antes do envio",
                "order_id": "733e160b-af6c-4b32-89f4-f00e31c5a961",
            }
        ),
        70: fj(
            {
                "kind": "cancel_request_outcome",
                "outcome": "accepted",
                "order_id": "733e160b-af6c-4b32-89f4-f00e31c5a961",
            }
        ),
        71: fj(
            {
                "kind": "cancel_request",
                "reason": "Artigo diferente do anunciado",
                "order_id": "70652ca0-9ce9-4f29-9a21-a2c60c7c316a",
            }
        ),
        72: fj(
            {
                "kind": "cancel_request_outcome",
                "outcome": "rejected",
                "order_id": "70652ca0-9ce9-4f29-9a21-a2c60c7c316a",
            }
        ),
        73: fj(
            {
                "kind": "order_dispute_opened",
                "reason": "danificado",
                "order_id": "70652ca0-9ce9-4f29-9a21-a2c60c7c316a",
            }
        ),
        74: fj(
            {
                "kind": "raffle_prize_awarded",
                "title": "Premio da rifa",
                "message": "Ganhaste um premio na rifa. Segue as instrucoes para o envio.",
            }
        ),
    }
    # Continuar a partir do 70 (50–69 já aplicados na corrida anterior).
    for mid in (70, 71, 72, 73, 74):
        sb.patch(f"/rest/v1/chat_messages?id=eq.{mid}", {"text": patches[mid]})
        print("patched", mid)

    # 4) Substituir códigos de teste e texto de layout
    natural = {
        76: "Obrigada! Já vi o histórico completo — parece tudo certo do meu lado.",
        77: "Perfeito. Qualquer dúvida sobre o casaco ou o envio, escreve aqui.",
        78: "Ainda tens o casaco na tua loja física ou só online?",
        79: (
            "Olá! Confirmei o tamanho M e o estado «Muito bom». "
            "Queria perceber se o envio para Lisboa chega esta semana e se "
            "aceitas proposta perto dos 38 €."
        ),
        89: "Combinado, fico a aguardar a tua resposta à proposta do conjunto.",
    }
    for mid, text in natural.items():
        sb.patch(f"/rest/v1/chat_messages?id=eq.{mid}", {"text": text})
        print("natural", mid)

    # 5) Substituir imagem do camião por detalhe de casaco
    img_url = (
        "https://images.unsplash.com/photo-1576995853123-5a10305d93c0"
        "?auto=format&fit=crop&w=800&q=80"
    )
    try:
        req = urllib.request.Request(img_url, headers={"User-Agent": "FleaberH10/1.0"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            img = resp.read()
        print("downloaded jacket detail", len(img))
        storage_path = (
            f"chat_uploads/{MARIANA}/{CHAT}/h10_117_1_jacket_"
            f"{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}.jpg"
        )
        # upsert via storage
        headers = {
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "image/jpeg",
            "x-upsert": "true",
        }
        up = urllib.request.Request(
            f"{url}/storage/v1/object/fleaber_private/{storage_path}",
            data=img,
            headers=headers,
            method="POST",
        )
        urllib.request.urlopen(up, timeout=90).read()
        print("uploaded", storage_path)
        # update msg 91 to new path (path-only, constraint-safe)
        sb.patch(
            "/rest/v1/chat_messages?id=eq.91",
            {
                "text": fj(
                    {"kind": "chat_image", "path": storage_path, "url": "", "v": 2}
                )
            },
        )
        print("chat_image -> jacket detail")
        # optional: remove old truck object
        old = (
            "chat_uploads/08c9dca8-3707-4ee5-9f43-b33293085d6a/"
            "84cd817c-9068-4d0b-960a-8d41110da40b/h10_117_20261026180121.jpg"
        )
        try:
            del_req = urllib.request.Request(
                f"{url}/storage/v1/object/fleaber_private/{old}",
                headers={"apikey": key, "Authorization": f"Bearer {key}"},
                method="DELETE",
            )
            urllib.request.urlopen(del_req, timeout=30).read()
            print("deleted old truck image")
        except Exception as e:
            print("warn delete old", e)
        chat_image_path = storage_path
    except Exception as e:
        print("WARN image replace failed", e)
        chat_image_path = None

    # 6) last_message human
    sb.patch(
        f"/rest/v1/chats?id=eq.{CHAT}",
        {
            "last_message": "Combinado, fico a aguardar a tua resposta à proposta do conjunto.",
            "last_message_time": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        },
    )

    # Verify bucket public flag
    req = urllib.request.Request(
        f"{url}/storage/v1/bucket/fleaber_private",
        headers={"apikey": key, "Authorization": f"Bearer {key}"},
    )
    bucket = json.loads(urllib.request.urlopen(req).read().decode())
    # Verify public URL denied
    public_ok = None
    if chat_image_path:
        try:
            pub = f"{url}/storage/v1/object/public/fleaber_private/{chat_image_path}"
            urllib.request.urlopen(urllib.request.Request(pub, method="HEAD"), timeout=20)
            public_ok = True
        except Exception:
            public_ok = False

    # Signed URL as service role still works
    signed_ok = None
    if chat_image_path:
        try:
            sign_req = urllib.request.Request(
                f"{url}/storage/v1/object/sign/fleaber_private/{chat_image_path}",
                data=json.dumps({"expiresIn": 3600}).encode(),
                headers={
                    "apikey": key,
                    "Authorization": f"Bearer {key}",
                    "Content-Type": "application/json",
                },
                method="POST",
            )
            signed = json.loads(urllib.request.urlopen(sign_req).read().decode())
            signed_ok = bool(signed.get("signedURL") or signed.get("signedUrl"))
        except Exception as e:
            signed_ok = str(e)

    inv = {
        "chat_id": CHAT,
        "account": "mareantiga@gmail.com",
        "bucket": "fleaber_private",
        "bucket_public": bucket.get("public"),
        "public_url_accessible": public_ok,
        "service_signed_url_ok": signed_ok,
        "chat_image_path": chat_image_path,
        "policies_expected": [
            "fleaber_private_select_own",
            "fleaber_private_insert_own",
            "fleaber_private_select_chat_counterparty",
            "fleaber_private_select_order_counterparty",
        ],
        "note": (
            "Bucket tornado privado. Políticas RLS já definidas na migração "
            "20260829130000_rtb_p2_storage_chat_private.sql — participantes "
            "assinam URLs via cliente autenticado. Sem fallback público na app."
        ),
    }
    (REP / "STORAGE_SECURITY.json").write_text(
        json.dumps(inv, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps(inv, ensure_ascii=False))
    print("=== DONE 117.1 polish ===")


if __name__ == "__main__":
    main()
