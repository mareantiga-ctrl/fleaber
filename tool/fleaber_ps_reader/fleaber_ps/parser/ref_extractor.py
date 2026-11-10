"""Extracção e normalização de referências de artigos."""

from __future__ import annotations

import re
import unicodedata

# Refs: 004/21, Q1, A15, REF Q1, L-32
REF_PATTERN = re.compile(
    r"(?:#(?:REF[-_]?)?[A-Z0-9]+(?:[/_-][A-Z0-9]+)+"
    r"|(?:REF\s*)?[A-Z]{1,4}-?\d{1,4}(?:/\d+)?"
    r"|REF[-_][A-Z0-9]+(?:[/_-][A-Z0-9]+)*"
    r"|\d{2,}[/_-]\d+"
    r"|#\d{2,})",
    re.IGNORECASE,
)

SHORTHAND_ONLY = re.compile(
    r"^(?:ref\s*)?([A-Za-z]{1,4}\d{1,4}|\d{2,}/\d+)$",
    re.IGNORECASE,
)

STOPWORDS = frozenset(
    {
        "quero", "queria", "reservo", "reserva", "fico", "com", "para", "mim",
        "esse", "essa", "este", "esta", "live", "noite", "ola", "olá", "boa",
        "unidades", "peça", "peças", "the", "and",
    }
)

ORDINAL_WORDS = {
    "primeiro": 1,
    "primeira": 1,
    "1º": 1,
    "1ª": 1,
    "segundo": 2,
    "segunda": 2,
    "2º": 2,
    "2ª": 2,
    "terceiro": 3,
    "terceira": 3,
    "3º": 3,
    "3ª": 3,
}


def normalize_ref(raw: str) -> str:
    text = raw.strip()
    if text.startswith("#"):
        text = text[1:]
    text = unicodedata.normalize("NFKD", text.upper())
    return re.sub(r"[^A-Z0-9]", "", text)


def _is_valid_ref_token(token: str) -> bool:
    t = token.strip().lower()
    if t in STOPWORDS or len(t) < 2:
        return False
    if re.fullmatch(r"(?:tira|retira)\d+", t):
        return False
    if t.startswith("#") or t.upper().startswith("REF"):
        return True
    if re.search(r"\d", t):
        return True
    if re.fullmatch(r"[a-z]{1,4}-?\d{1,4}(/\\d+)?", t, re.IGNORECASE):
        return True
    return False


def extract_ref_tokens(text: str) -> list[str]:
    found: list[str] = []
    for m in REF_PATTERN.finditer(text):
        token = m.group(0).strip()
        if _is_valid_ref_token(token):
            found.append(token)
    m = SHORTHAND_ONLY.match(text.strip())
    if m:
        token = m.group(1).strip()
        if _is_valid_ref_token(token) and token not in found:
            found.append(token)
    found.sort(key=lambda t: ("/" in t or "-" in t, len(t)), reverse=True)
    seen: set[str] = set()
    out: list[str] = []
    for t in found:
        n = normalize_ref(t)
        if n and n not in seen:
            seen.add(n)
            out.append(t)
    return out


def extract_slot_number(text: str) -> int | None:
    refs = extract_ref_tokens(text)
    if refs:
        return None

    lower = text.lower()
    # «afinal so quero 2» = quantidade, NÃO slot 2
    if re.search(
        r"\b(?:afinal|so|só|apenas).{0,24}\b(?:quero|queria)\s+\d{1,2}\b"
        r"(?!\s*(?:ref\s*)?[a-z]{1,4}\d)",
        lower,
    ):
        return None

    for word, num in ORDINAL_WORDS.items():
        if word in lower:
            return num

    # Slot explícito: «quero o 2» / «quero o número 2»
    m = re.search(
        r"(?:quero|queria|reservo|fico com|fica com|so|só|apenas)\s+"
        r"(?:o|a|os|as)\s+(?:n[úu]mero\s+|nº\s+|#\s*)?(\d{1,3})\b",
        lower,
    )
    if m:
        n = int(m.group(1))
        if 1 <= n <= 999:
            return n

    m = re.search(r"\b(?:do|da|de)\s+(\d{1,3})\b", lower)
    if m:
        n = int(m.group(1))
        if 1 <= n <= 999:
            return n

    m = re.search(
        r"\b(\d{1,2})\s*(?:unidades?|pcs?|peças?)?\s*(?:do|da|de)\s*(?:n[úu]mero|nº|#)?\s*(\d{1,3})\b",
        lower,
    )
    if m:
        return int(m.group(2))

    m = re.fullmatch(r"(\d{1,3})", text.strip())
    if m:
        n = int(m.group(1))
        if 1 <= n <= 999:
            return n

    return None


def extract_quantity(text: str) -> int:
    lower = text.lower()
    m = re.search(
        r"\b(?:quero|queria|fico|afinal|so|só|apenas)\s+(\d{1,2})\s+(?:ref\s*)?[a-z0-9/\-]{1,12}\b",
        lower,
    )
    if m:
        return max(1, min(int(m.group(1)), 99))
    m = re.search(r"\b(\d{1,2})\s*(?:unidades?|pcs?|peças?)\b", lower)
    if m:
        return max(1, min(int(m.group(1)), 99))
    m = re.search(r"\b(?:afinal|so|só|apenas)\s+(?:quero\s+)?(\d{1,2})\b", lower)
    if m:
        return max(1, min(int(m.group(1)), 99))
    m = re.search(r"\b(dois|duas|tr[eê]s|quatro|cinco)\b", lower)
    if m:
        words = {"dois": 2, "duas": 2, "três": 3, "tres": 3, "quatro": 4, "cinco": 5}
        return words.get(m.group(1), 1)
    if " os dois" in lower or " as duas" in lower:
        return 2
    return 1
