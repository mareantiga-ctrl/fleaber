"""Cliente HTTP — ingest, pairing, heartbeat, contexto."""

from __future__ import annotations

import datetime as dt
import json
import logging
from pathlib import Path
from typing import Any

import httpx

from fleaber_ps.core.config import PsConfig
from fleaber_ps.parser.context import LiveContext
from fleaber_ps.parser.parse_pt import ParsedComment, line_hash, pseudo_id
from fleaber_ps.version import __version__

log = logging.getLogger("fleaber_ps.ingest")


def _now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


class IngestClient:
    def __init__(self, cfg: PsConfig) -> None:
        self.cfg = cfg
        self._client = httpx.Client(timeout=25.0)

    def close(self) -> None:
        self._client.close()

    def claim_pairing(self, code: str) -> dict[str, Any]:
        url = f"{self.cfg.supabase_url}/functions/v1/ps-pairing-claim"
        res = self._client.post(
            url,
            json={
                "code": code.strip(),
                "device_id": self.cfg.device_id or "ps-reader-pc",
                "app_version": __version__,
            },
        )
        data = res.json()
        if res.status_code != 200 or not data.get("ok"):
            raise RuntimeError(data.get("error", f"HTTP {res.status_code}"))
        return data

    def heartbeat(
        self,
        status: str = "online",
        last_error: str | None = None,
        roi_ok: bool | None = None,
    ) -> None:
        if not self.cfg.is_paired():
            return
        url = f"{self.cfg.supabase_url}/functions/v1/ps-heartbeat"
        try:
            self._client.post(
                url,
                json={
                    "live_id": self.cfg.live_id,
                    "device_id": self.cfg.device_id,
                    "status": status,
                    "app_version": __version__,
                    "last_error": last_error,
                    "roi_ok": roi_ok,
                },
                headers={"X-Device-Token": self.cfg.device_token},
            )
        except Exception as exc:  # noqa: BLE001
            log.warning("heartbeat failed: %s", exc)

    def ingest_parsed(
        self,
        parsed: ParsedComment,
        *,
        ocr_confidence: float,
        identity_confidence: float,
        avatar_phash: str = "ocr",
        chat_sequence: int | None = None,
    ) -> dict[str, Any]:
        digest = line_hash(parsed.raw_line)
        name = parsed.display_name or "Facebook"
        external_ref = pseudo_id(self.cfg.live_id, avatar_phash, name)

        payload = {
            "live_id": self.cfg.live_id,
            "ref_slug": parsed.ref_slug,
            "public_slot": parsed.public_slot,
            "ref_number": parsed.public_slot,
            "requested_qty": parsed.quantity,
            "title_hint": parsed.title_hint,
            "external_display_name": parsed.display_name,
            "external_buyer_ref": external_ref,
            "ocr_raw_line": parsed.raw_line,
            "ocr_line_hash": digest,
            "detected_at": _now_iso(),
            "chat_sequence": chat_sequence,
            "avatar_phash": avatar_phash,
            "ocr_confidence": round(ocr_confidence, 3),
            "parser_confidence": parsed.parser_confidence,
            "identity_confidence": round(identity_confidence, 3),
            "parser_intent": parsed.intent.value,
            "device_id": self.cfg.device_id,
            "force_needs_review": parsed.needs_review,
        }

        url = f"{self.cfg.supabase_url}/functions/v1/ingest-ocr-reservation"
        try:
            res = self._client.post(
                url,
                json=payload,
                headers={
                    "Content-Type": "application/json",
                    "X-Device-Token": self.cfg.device_token,
                },
            )
            data = res.json()
            if res.status_code in (200, 409):
                self.cfg.remember_hash(digest)
                self.cfg.save()
            return {"status": res.status_code, **data}
        except httpx.HTTPError as exc:
            self._enqueue_offline(payload)
            return {"ok": False, "error": "offline", "detail": str(exc)}

    def _enqueue_offline(self, payload: dict[str, Any]) -> None:
        path = PsConfig.offline_queue_path()
        with path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(payload, ensure_ascii=False) + "\n")
        log.info("queued offline ingest")

    def flush_offline_queue(self) -> int:
        path = PsConfig.offline_queue_path()
        if not path.exists():
            return 0
        lines = path.read_text(encoding="utf-8").splitlines()
        remaining: list[str] = []
        sent = 0
        url = f"{self.cfg.supabase_url}/functions/v1/ingest-ocr-reservation"
        for line in lines:
            if not line.strip():
                continue
            try:
                payload = json.loads(line)
                res = self._client.post(
                    url,
                    json=payload,
                    headers={
                        "Content-Type": "application/json",
                        "X-Device-Token": self.cfg.device_token,
                    },
                )
                if res.status_code in (200, 409):
                    sent += 1
                else:
                    remaining.append(line)
            except Exception:  # noqa: BLE001
                remaining.append(line)
        if remaining:
            path.write_text("\n".join(remaining) + "\n", encoding="utf-8")
        else:
            path.unlink(missing_ok=True)
        return sent

    @staticmethod
    def live_context_from_pairing(data: dict[str, Any]) -> LiveContext | None:
        ctx = data.get("live_context")
        if isinstance(ctx, dict) and ctx.get("ok"):
            return LiveContext.from_api(ctx)
        return None
