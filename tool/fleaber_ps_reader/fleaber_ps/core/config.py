"""Configuração persistente Fleaber PS Reader."""

from __future__ import annotations

import json
import os
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any


DEFAULT_SUPABASE_URL = "https://fxdknzrqjenzqcvnwqqq.supabase.co"


@dataclass
class ConfidenceThresholds:
    auto_ingest: float = 0.85
    review: float = 0.55
    ocr_min: float = 0.40


@dataclass
class PsConfig:
    supabase_url: str = DEFAULT_SUPABASE_URL
    live_id: str = ""
    live_title: str = ""
    seller_handle: str = ""
    hub_live_url: str = ""
    device_token: str = ""
    device_id: str = ""
    roi: dict[str, int] | None = None
    monitor_index: int = 1
    poll_interval_ms: int = 400
    seen_hashes: list[str] = field(default_factory=list)
    seen_comment_keys: list[str] = field(default_factory=list)
    seen_reservation_keys: list[str] = field(default_factory=list)
    ollama_enabled: bool = False
    ollama_url: str = "http://127.0.0.1:11434"
    ollama_model: str = "llama3.2:3b"
    thresholds: ConfidenceThresholds = field(default_factory=ConfidenceThresholds)
    tesseract_cmd: str | None = None
    app_version: str = "1.0.0"

    @staticmethod
    def config_dir() -> Path:
        base = os.environ.get("APPDATA") or os.environ.get("HOME") or "."
        return Path(base) / "FleaberReader"

    @staticmethod
    def config_path() -> Path:
        return PsConfig.config_dir() / "config.json"

    @staticmethod
    def logs_dir() -> Path:
        d = PsConfig.config_dir() / "logs"
        d.mkdir(parents=True, exist_ok=True)
        return d

    @staticmethod
    def offline_queue_path() -> Path:
        return PsConfig.config_dir() / "offline_queue.jsonl"

    @classmethod
    def load(cls) -> PsConfig:
        path = cls.config_path()
        if not path.exists():
            return cls()
        data = json.loads(path.read_text(encoding="utf-8"))
        th = data.get("thresholds") or {}
        return cls(
            supabase_url=str(data.get("supabase_url", DEFAULT_SUPABASE_URL)).rstrip("/"),
            live_id=str(data.get("live_id", "")),
            live_title=str(data.get("live_title", "")),
            seller_handle=str(data.get("seller_handle", "")),
            hub_live_url=str(data.get("hub_live_url", "")),
            device_token=str(data.get("device_token", "")),
            device_id=str(data.get("device_id", "")),
            roi=data.get("roi"),
            monitor_index=int(data.get("monitor_index", 1)),
            poll_interval_ms=int(data.get("poll_interval_ms", 400)),
            seen_hashes=list(data.get("seen_hashes") or []),
            seen_comment_keys=list(data.get("seen_comment_keys") or []),
            seen_reservation_keys=list(data.get("seen_reservation_keys") or []),
            ollama_enabled=bool(data.get("ollama_enabled", False)),
            ollama_url=str(data.get("ollama_url", "http://127.0.0.1:11434")),
            ollama_model=str(data.get("ollama_model", "llama3.2:3b")),
            thresholds=ConfidenceThresholds(
                auto_ingest=float(th.get("auto_ingest", 0.85)),
                review=float(th.get("review", 0.55)),
                ocr_min=float(th.get("ocr_min", 0.40)),
            ),
            tesseract_cmd=data.get("tesseract_cmd"),
            app_version=str(data.get("app_version", "1.0.0")),
        )

    def save(self) -> None:
        self.config_dir().mkdir(parents=True, exist_ok=True)
        payload: dict[str, Any] = asdict(self)
        payload["thresholds"] = asdict(self.thresholds)
        self.config_path().write_text(
            json.dumps(payload, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )

    def is_paired(self) -> bool:
        return bool(self.live_id and self.device_token and self.device_id)

    def remember_hash(self, digest: str, limit: int = 800) -> None:
        if digest in self.seen_hashes:
            return
        self.seen_hashes.append(digest)
        self.seen_hashes = self.seen_hashes[-limit:]

    def remember_comment_key(self, key: str, limit: int = 1200) -> None:
        if key in self.seen_comment_keys:
            return
        self.seen_comment_keys.append(key)
        self.seen_comment_keys = self.seen_comment_keys[-limit:]

    def redacted_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d["device_token"] = "***" if self.device_token else ""
        d["thresholds"] = asdict(self.thresholds)
        return d

    def clear_pairing(self) -> None:
        self.live_id = ""
        self.live_title = ""
        self.seller_handle = ""
        self.hub_live_url = ""
        self.device_token = ""
        self.save()
