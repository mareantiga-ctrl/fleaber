"""Parser PT para comentários Facebook (PS / Fleaber Reader)."""

from __future__ import annotations

import hashlib
import re
import unicodedata
from dataclasses import dataclass


@dataclass(frozen=True)
class ParsedReservation:
    ref_number: int
    display_name: str | None
    confidence: float
    raw_line: str


_PATTERNS: list[tuple[re.Pattern[str], float]] = [
    (
        re.compile(
            r"^(?P<name>.+?)\s+(?:quero|queria|reservo|fico com)\s+(?:o\s+)?(?P<num>\d{1,3})\b",
            re.IGNORECASE,
        ),
        0.92,
    ),
    (
        re.compile(
            r"^(?:quero|reservo)\s+(?:o\s+)?(?P<num>\d{1,3})\b",
            re.IGNORECASE,
        ),
        0.78,
    ),
    (
        re.compile(
            r"^(?P<name>[A-Za-zÀ-ú][\w\s]{2,30})\s+(?P<num>\d{1,3})$",
            re.IGNORECASE,
        ),
        0.72,
    ),
]


def normalize_name(value: str) -> str:
    text = unicodedata.normalize("NFKD", value.strip().lower())
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def line_hash(line: str) -> str:
    return hashlib.sha256(line.strip().encode("utf-8")).hexdigest()


def pseudo_id(live_id: str, avatar_phash: str, name: str) -> str:
    payload = f"{avatar_phash}|{normalize_name(name)}".encode("utf-8")
    digest = hashlib.sha256(payload).hexdigest()[:16]
    return f"sess:{live_id}:{digest}"


def parse_comment_line(line: str) -> ParsedReservation | None:
    text = " ".join(line.split())
    if not text:
        return None

    for pattern, base_conf in _PATTERNS:
        match = pattern.search(text)
        if not match:
            continue
        num_raw = match.groupdict().get("num")
        if not num_raw:
            continue
        num = int(num_raw)
        if num < 1 or num > 999:
            continue
        name = match.groupdict().get("name")
        display = name.strip() if name else None
        conf = base_conf
        if display and len(display) >= 3:
            conf += 0.03
        return ParsedReservation(
            ref_number=num,
            display_name=display,
            confidence=min(conf, 0.99),
            raw_line=text,
        )

    only_num = re.fullmatch(r"(?P<num>\d{1,3})", text)
    if only_num:
        num = int(only_num.group("num"))
        if 1 <= num <= 999:
            return ParsedReservation(
                ref_number=num,
                display_name=None,
                confidence=0.55,
                raw_line=text,
            )

    return None
