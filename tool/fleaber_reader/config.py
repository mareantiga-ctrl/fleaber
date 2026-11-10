"""Config local do Fleaber Reader (%APPDATA%/FleaberReader/config.json)."""

from __future__ import annotations

import json
import os
from dataclasses import asdict, dataclass
from pathlib import Path


@dataclass
class ReaderConfig:
    supabase_url: str
    live_id: str
    device_token: str
    device_id: str = "pc-reader-1"
    roi: dict[str, int] | None = None
    poll_interval_ms: int = 400
    seen_hashes: list[str] | None = None

    @staticmethod
    def config_dir() -> Path:
        base = os.environ.get("APPDATA") or os.environ.get("HOME") or "."
        return Path(base) / "FleaberReader"

    @staticmethod
    def config_path() -> Path:
        return ReaderConfig.config_dir() / "config.json"

    @classmethod
    def load(cls) -> "ReaderConfig":
        path = cls.config_path()
        if not path.exists():
            raise FileNotFoundError(
                f"Config em falta: {path}. Corre setup primeiro."
            )
        data = json.loads(path.read_text(encoding="utf-8"))
        return cls(
            supabase_url=str(data.get("supabase_url", "")).rstrip("/"),
            live_id=str(data.get("live_id", "")),
            device_token=str(data.get("device_token", "")),
            device_id=str(data.get("device_id", "pc-reader-1")),
            roi=data.get("roi"),
            poll_interval_ms=int(data.get("poll_interval_ms", 400)),
            seen_hashes=list(data.get("seen_hashes") or []),
        )

    def save(self) -> None:
        self.config_dir().mkdir(parents=True, exist_ok=True)
        payload = asdict(self)
        self.config_path().write_text(
            json.dumps(payload, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )

    def remember_hash(self, digest: str, limit: int = 500) -> None:
        seen = self.seen_hashes or []
        if digest in seen:
            return
        seen.append(digest)
        self.seen_hashes = seen[-limit:]
