"""Exportar diagnóstico ZIP."""

from __future__ import annotations

import json
import zipfile
from datetime import datetime
from pathlib import Path

from fleaber_ps.core.config import PsConfig
from fleaber_ps.version import __version__


def export_diagnostic(out_path: Path | None = None) -> Path:
    cfg = PsConfig.load()
    d = cfg.config_dir()
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    out = out_path or (d / f"diagnostic_{ts}.zip")

    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr(
            "manifest.json",
            json.dumps(
                {"version": __version__, "exported_at": ts},
                indent=2,
            ),
        )
        zf.writestr("config_redacted.json", json.dumps(cfg.redacted_dict(), indent=2, ensure_ascii=False))

        log_file = PsConfig.logs_dir() / "fleaber_ps.log"
        if log_file.exists():
            zf.write(log_file, "logs/fleaber_ps.log")

        off = PsConfig.offline_queue_path()
        if off.exists():
            zf.write(off, "offline_queue.jsonl")

        preview = d / "calibration_preview.png"
        if preview.exists():
            zf.write(preview, "calibration_preview.png")

    return out
