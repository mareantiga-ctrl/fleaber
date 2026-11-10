"""Motor OCR — Tesseract + preprocess claro/escuro."""

from __future__ import annotations

import logging
from dataclasses import dataclass

import numpy as np
import pytesseract
from PIL import Image

from fleaber_ps.ocr.preprocess import preprocess_for_ocr
from fleaber_ps.ocr.tesseract_locate import find_tesseract

log = logging.getLogger("fleaber_ps.ocr")


@dataclass
class OcrLine:
    text: str
    confidence: float


@dataclass
class OcrResult:
    lines: list[OcrLine]
    confidence: float
    tesseract_ok: bool
    tesseract_path: str | None
    error: str | None = None


def configure_tesseract(cmd: str | None = None) -> str | None:
    path = find_tesseract(cmd)
    if path:
        pytesseract.pytesseract.tesseract_cmd = path
    return path


def _parse_tesseract_data(data: dict) -> tuple[list[OcrLine], float]:
    lines_map: dict[tuple[int, int, int], list[tuple[str, float]]] = {}
    n = len(data["text"])
    for i in range(n):
        txt = (data["text"][i] or "").strip()
        if not txt:
            continue
        try:
            conf = float(data["conf"][i])
        except (ValueError, TypeError):
            conf = 0.0
        if conf < 0:
            conf = 0.0
        key = (data["block_num"][i], data["par_num"][i], data["line_num"][i])
        lines_map.setdefault(key, []).append((txt, conf / 100.0))

    lines: list[OcrLine] = []
    confs: list[float] = []
    for parts in lines_map.values():
        text = " ".join(p[0] for p in parts).strip()
        if len(text) < 1:
            continue
        avg = sum(p[1] for p in parts) / len(parts)
        lines.append(OcrLine(text=text, confidence=avg))
        confs.append(avg)

    overall = sum(confs) / len(confs) if confs else 0.0
    return lines, overall


def _ocr_pass(bgr: np.ndarray, dark_mode: bool) -> tuple[list[OcrLine], float]:
    proc = preprocess_for_ocr(bgr, dark_mode_hint=dark_mode)
    pil = Image.fromarray(proc)
    config = "--psm 6 -c preserve_interword_spaces=1"
    data = pytesseract.image_to_data(
        pil, lang="por+eng", config=config, output_type=pytesseract.Output.DICT
    )
    return _parse_tesseract_data(data)


def ocr_image(bgr: np.ndarray, tesseract_cmd: str | None = None) -> OcrResult:
    path = configure_tesseract(tesseract_cmd)
    if not path:
        return OcrResult(
            lines=[],
            confidence=0.0,
            tesseract_ok=False,
            tesseract_path=None,
            error="tesseract_not_found",
        )

    try:
        # Facebook costuma ser tema escuro — tentar ambos e ficar com mais texto
        lines_dark, conf_dark = _ocr_pass(bgr, dark_mode=True)
        lines_light, conf_light = _ocr_pass(bgr, dark_mode=False)

        if len(lines_dark) >= len(lines_light):
            lines, conf = lines_dark, conf_dark
        else:
            lines, conf = lines_light, conf_light

        # Fallback PSM 4 (coluna única) se nada detectado
        if not lines:
            proc = preprocess_for_ocr(bgr, dark_mode_hint=True)
            pil = Image.fromarray(proc)
            raw = pytesseract.image_to_string(
                pil, lang="por+eng", config="--psm 4"
            )
            for ln in raw.splitlines():
                t = ln.strip()
                if len(t) >= 1:
                    lines.append(OcrLine(text=t, confidence=0.5))
            if lines:
                conf = 0.5

        return OcrResult(
            lines=lines,
            confidence=conf,
            tesseract_ok=True,
            tesseract_path=path,
        )
    except pytesseract.TesseractNotFoundError:
        return OcrResult(
            lines=[],
            confidence=0.0,
            tesseract_ok=False,
            tesseract_path=None,
            error="tesseract_not_found",
        )
    except Exception as exc:  # noqa: BLE001
        log.exception("ocr failed")
        return OcrResult(
            lines=[],
            confidence=0.0,
            tesseract_ok=False,
            tesseract_path=path,
            error=str(exc),
        )


def ocr_raw_string(bgr: np.ndarray, tesseract_cmd: str | None = None) -> tuple[str, float]:
    result = ocr_image(bgr, tesseract_cmd)
    return "\n".join(ln.text for ln in result.lines), result.confidence
