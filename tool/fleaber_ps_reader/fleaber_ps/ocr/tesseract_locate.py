"""Localizar Tesseract OCR no Windows."""

from __future__ import annotations

import os
import shutil
from pathlib import Path

_WIN_CANDIDATES = [
    Path(r"C:\Program Files\Tesseract-OCR\tesseract.exe"),
    Path(r"C:\Program Files (x86)\Tesseract-OCR\tesseract.exe"),
    Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "Tesseract-OCR" / "tesseract.exe",
]


def find_tesseract(configured: str | None = None) -> str | None:
    if configured and os.path.isfile(configured):
        return configured
    env = os.environ.get("FLEABER_TESSERACT")
    if env and os.path.isfile(env):
        return env
    found = shutil.which("tesseract")
    if found and os.path.isfile(found):
        return found
    for path in _WIN_CANDIDATES:
        if path.is_file():
            return str(path)
    return None


def tesseract_status(configured: str | None = None) -> tuple[bool, str]:
    path = find_tesseract(configured)
    if not path:
        return False, (
            "Tesseract OCR nao encontrado.\n\n"
            "Instala no PowerShell (como administrador):\n"
            "  winget install UB-Mannheim.TesseractOCR\n\n"
            "Marca o idioma Portuguese na instalacao.\n"
            "Reinicia o Fleaber PS Reader depois de instalar."
        )
    return True, path
