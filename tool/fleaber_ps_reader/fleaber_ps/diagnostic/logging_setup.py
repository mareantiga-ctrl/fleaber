"""Logging estruturado."""

from __future__ import annotations

import logging
from logging.handlers import RotatingFileHandler

from fleaber_ps.core.config import PsConfig


def setup_logging() -> None:
    PsConfig.logs_dir()
    log_path = PsConfig.logs_dir() / "fleaber_ps.log"
    root = logging.getLogger()
    root.setLevel(logging.INFO)
    if not root.handlers:
        fmt = logging.Formatter(
            "%(asctime)s [%(levelname)s] %(name)s: %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
        )
        fh = RotatingFileHandler(log_path, maxBytes=2_000_000, backupCount=5, encoding="utf-8")
        fh.setFormatter(fmt)
        root.addHandler(fh)
        sh = logging.StreamHandler()
        sh.setFormatter(fmt)
        root.addHandler(sh)
