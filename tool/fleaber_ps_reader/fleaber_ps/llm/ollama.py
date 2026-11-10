"""LLM local opcional (Ollama) para ambiguidades."""

from __future__ import annotations

import json
import logging
from typing import Any

import httpx

from fleaber_ps.parser.context import LiveContext

log = logging.getLogger("fleaber_ps.llm")

SYSTEM_PROMPT = """És um assistente que analisa comentários de Facebook Live em português (Portugal).
Responde APENAS JSON válido com campos:
intent (reserve|cancel|chat|ambiguous),
ref_slug (string|null),
public_slot (int|null),
quantity (int),
confidence (0-1),
needs_review (bool),
reason (string curta).

Regras:
- «afinal ja nao quero Z1» → cancel, ref Z1, quantity 1
- «afinal so quero 5 Z2» → reserve (supersede qty), ref Z2, quantity 5
- «afinal so quero 2» (sem ref) → reserve qty 2, ref = último artigo do comprador se conhecido
- «quero 2 Z1» → reserve, ref Z1, quantity 2
- «tira 2 Z2» → NÃO é «quero 2 Z2». É reduzir 2: se tinha 10, quantity final 8, ref Z2
- Nunca trates «tira N REF» como quantidade absoluta N
- Linhas com lixo OCR ((=4/, "A/, janao) — ignora lixo, interpreta intenção real
- Comentários podem chegar fora de ordem; preferir intenção semântica mais recente
- «C4», «afinal», «so», «Facebook» NUNCA são nomes de pessoa
- Nunca inventes artigos que não estão no catálogo."""


def resolve_ambiguous(
    comment: str,
    ctx: LiveContext,
    *,
    base_url: str = "http://127.0.0.1:11434",
    model: str = "llama3.2:3b",
    timeout: float = 8.0,
) -> dict[str, Any] | None:
    items = [
        {
            "slot": it.public_slot,
            "ref": it.ref_code,
            "title": it.title,
            "active": it.is_active,
        }
        for it in ctx.items[:30]
    ]
    user = json.dumps(
        {"comment": comment, "catalog": items, "active_ref": ctx.active_item.ref_code if ctx.active_item else None},
        ensure_ascii=False,
    )
    try:
        with httpx.Client(timeout=timeout) as client:
            res = client.post(
                f"{base_url.rstrip('/')}/api/chat",
                json={
                    "model": model,
                    "stream": False,
                    "messages": [
                        {"role": "system", "content": SYSTEM_PROMPT},
                        {"role": "user", "content": user},
                    ],
                },
            )
            if res.status_code != 200:
                return None
            content = res.json().get("message", {}).get("content", "")
            start = content.find("{")
            end = content.rfind("}") + 1
            if start < 0 or end <= start:
                return None
            return json.loads(content[start:end])
    except Exception as exc:  # noqa: BLE001
        log.debug("ollama unavailable: %s", exc)
        return None
