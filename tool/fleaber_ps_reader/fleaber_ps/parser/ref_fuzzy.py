"""Correcção OCR de refs — usa catálogo emparelhado (Z↔7, O↔0, …)."""

from __future__ import annotations

from fleaber_ps.parser.context import LiveContext
from fleaber_ps.parser.ref_extractor import normalize_ref

# Pares de confusão típicos Tesseract (maiúsculas).
_OCR_CONFUSIONS: tuple[tuple[str, str], ...] = (
    ("7", "Z"),
    ("Z", "7"),
    ("0", "O"),
    ("O", "0"),
    ("1", "I"),
    ("I", "1"),
    ("1", "L"),
    ("L", "1"),
    ("5", "S"),
    ("S", "5"),
    ("8", "B"),
    ("B", "8"),
    ("2", "Z"),
    ("G", "6"),
    ("6", "G"),
)


def _catalog_entries(ctx: LiveContext) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    for it in ctx.items:
        n = it.ref_norm.upper().replace(" ", "")
        out.append((n, it.ref_code))
        if n.startswith("REF"):
            out.append((n[3:], it.ref_code))
    return out


def _confusion_equal(a: str, b: str) -> bool:
    if a == b:
        return True
    if len(a) != len(b):
        return False
    for ca, cb in zip(a, b, strict=True):
        if ca == cb:
            continue
        if (ca, cb) not in _OCR_CONFUSIONS and (cb, ca) not in _OCR_CONFUSIONS:
            return False
    return True


def _trim_trailing_ocr_noise(value: str) -> str:
    text = value.upper().strip(" ]|.,;")
    while len(text) > 2 and text[-1] in "08889":
        text = text[:-1]
    return text


def _variants(ref_norm: str) -> set[str]:
    target = ref_norm.upper().replace(" ", "")
    out: set[str] = {target}
    stack = [target]
    while stack:
        cur = stack.pop()
        for i, ch in enumerate(cur):
            for a, b in _OCR_CONFUSIONS:
                if ch != a:
                    continue
                variant = cur[:i] + b + cur[i + 1 :]
                if variant not in out:
                    out.add(variant)
                    if len(out) > 64:
                        return out
                    stack.append(variant)
    return out


def resolve_ocr_ref(ref_slug: str, ctx: LiveContext) -> tuple[str | None, str | None]:
    """Se OCR leu mal a ref, corrige quando há **uma** ref no catálogo."""
    if not ref_slug or not ctx.items:
        return None, None

    norm = _trim_trailing_ocr_noise(normalize_ref(ref_slug))
    if ctx.find_by_ref_norm(norm):
        return None, None

    catalog = _catalog_entries(ctx)
    catalog_norms = {c[0] for c in catalog}

    # 1) Variantes char-a-char (mesmo comprimento).
    matches: list[str] = []
    for variant in _variants(norm):
        if variant in catalog_norms:
            matches.append(variant)
    unique = list(dict.fromkeys(matches))
    if len(unique) == 1:
        return _code_for_norm(unique[0], catalog), "ocr_confusion"

    # 2) Prefixo curto (72888 → 728 → Z2 com confusão).
    for length in range(len(norm), 1, -1):
        prefix = norm[:length]
        hits = [c for c in catalog_norms if _confusion_equal(prefix, c)]
        if len(hits) == 1:
            return _code_for_norm(hits[0], catalog), "ocr_confusion_prefix"

    # 3) Comprimento ±1 (271 → Z1).
    for cat_norm, ref_code in catalog:
        if abs(len(norm) - len(cat_norm)) > 1:
            continue
        if _confusion_equal(norm, cat_norm):
            return ref_code, "ocr_confusion_len"
        if len(norm) == len(cat_norm) + 1:
            for i in range(len(norm)):
                trimmed = norm[:i] + norm[i + 1 :]
                if _confusion_equal(trimmed, cat_norm):
                    return ref_code, "ocr_confusion_drop"

    return None, None


def _code_for_norm(norm: str, catalog: list[tuple[str, str]]) -> str | None:
    for n, code in catalog:
        if n == norm:
            return code
    return None
