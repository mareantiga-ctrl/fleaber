"""Links FleaHub para partilhar com compradores (Facebook Live)."""

from __future__ import annotations

from typing import Any

HUB_WEB_HASH_BASE = "https://fleaber.pt/fleahub/index.html"


def build_hub_live_url(handle: str, live_id: str) -> str:
    h = handle.strip().lower().strip("/")
    lid = live_id.strip()
    if not h or not lid:
        return ""
    return f"{HUB_WEB_HASH_BASE}#/{h}/live?liveId={lid}"


def hub_link_from_pairing(data: dict[str, Any]) -> tuple[str, str]:
    """Extrai (url, handle) da resposta ps-pairing-claim."""
    ctx = data.get("live_context") if isinstance(data.get("live_context"), dict) else {}

    url = str(
        data.get("hub_live_url")
        or ctx.get("hub_live_url")
        or ""
    ).strip()
    handle = str(
        data.get("seller_handle")
        or ctx.get("seller_handle")
        or ""
    ).strip()
    live_id = str(data.get("live_id") or ctx.get("live_id") or "").strip()

    if not url and handle and live_id:
        url = build_hub_live_url(handle, live_id)
    return url, handle
