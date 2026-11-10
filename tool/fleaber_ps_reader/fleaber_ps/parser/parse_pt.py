"""Parser PT v2 — intenções de reserva em lives portuguesas."""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from enum import Enum

from fleaber_ps.parser.context import LiveContext
from fleaber_ps.parser.ref_extractor import (
    extract_quantity,
    extract_ref_tokens,
    extract_slot_number,
    normalize_ref,
)
from fleaber_ps.parser.name_validation import (
    is_plausible_display_name,
    normalize_display_name,
    normalize_ocr_line,
    strip_ocr_artifacts,
)
from fleaber_ps.parser.ref_fuzzy import resolve_ocr_ref


def normalize_name(value: str) -> str:
    return normalize_display_name(value)


class ParseIntent(str, Enum):
    RESERVE = "reserve"
    CANCEL = "cancel"
    QUESTION = "question"
    CHAT = "chat"
    AMBIGUOUS = "ambiguous"


@dataclass(frozen=True)
class ParsedComment:
    intent: ParseIntent
    display_name: str | None
    ref_slug: str | None
    public_slot: int | None
    title_hint: str | None
    quantity: int
    parser_confidence: float
    raw_line: str
    needs_review: bool = False
    reason: str | None = None

    @property
    def ref_number_legacy(self) -> int | None:
        return self.public_slot


RESERVE_VERBS = re.compile(
    r"\b(quero|queria|reservo|reserva|fico com|fica com|leva|pego|pega|"
    r"mete|adiciona|adicionar|saco|para mim|é meu|e meu|sou eu)\b",
    re.IGNORECASE,
)

DEICTIC = re.compile(
    r"\b(esse|essa|este|esta|aquele|aquela|o que est[aá]s|ultimo|último|"
    r"da esquerda|de cima|activo|ativo|a mostrar)\b",
    re.IGNORECASE,
)

CANCEL = re.compile(
    r"\b(cancela|cancelar|desisto|"
    r"n[aã]o\s+quero|nao\s+quero|"
    r"ja\s+n[aã]o\s+quero|j[aá]\s+n[aã]o\s+quero|"
    r"deixa\s+(?:ser|estar)|"
    r"tira(?:\s+me)?|retira(?:\s+me)?|"
    r"anula(?:\s+a\s+reserva)?)\b",
    re.IGNORECASE,
)

# «afinal só quero 5 Z2» — supersede, não cancel.
SUPERSEDE_PREFIX = re.compile(
    r"^(?:afinal|so|só|apenas|corrigo|mudo|enganei|errei)\b",
    re.IGNORECASE,
)

REDUCE_QTY = re.compile(
    r"\b(?:tira|retira)(?:\s+|(?=\d))(?:me\s+)?(\d{1,2})\s+(?:ref\s*)?[a-z]{0,2}\d{1,4}\b",
    re.IGNORECASE,
)


def line_hash(line: str) -> str:
    return hashlib.sha256(line.strip().encode("utf-8")).hexdigest()


def pseudo_id(live_id: str, avatar_phash: str, name: str) -> str:
    payload = f"{avatar_phash}|{normalize_name(name)}".encode("utf-8")
    digest = hashlib.sha256(payload).hexdigest()[:16]
    return f"sess:{live_id}:{digest}"


RESERVE_VERB_WORDS = frozenset(
    {
        "quero", "queria", "reservo", "reserva", "fico", "leva", "pego", "pega",
        "mete", "adiciona", "adicionar", "afinal", "so", "só", "ja", "já",
        "apenas", "corrigo", "mudo",
    }
)


def split_name_body(text: str) -> tuple[str | None, str]:
    parts = text.split()
    if len(parts) < 2:
        return None, text
    max_name_words = min(4, len(parts) - 1)
    for n in range(max_name_words, 0, -1):
        name = " ".join(parts[:n])
        body = " ".join(parts[n:])
        if not body:
            continue
        name_first = name.split()[0].lower()
        if (
            is_plausible_display_name(name)
            and name_first not in RESERVE_VERB_WORDS
            and not RESERVE_VERBS.match(name)
        ):
            return name, body
    return None, text


def parse_comment_line(
    line: str,
    ctx: LiveContext | None = None,
) -> ParsedComment | None:
    text = normalize_ocr_line(line)
    if not text:
        return None
    if len(text) < 2 and not re.fullmatch(r"\d", text):
        return None

    reduce_m = REDUCE_QTY.search(text)
    if reduce_m:
        display_name, body = split_name_body(text)
        work = body if body else text
        refs = extract_ref_tokens(work)
        ref_slug = refs[0] if refs else None
        slot = extract_slot_number(work) if not ref_slug else None
        delta = max(1, min(int(reduce_m.group(1)), 99))
        return ParsedComment(
            intent=ParseIntent.RESERVE,
            display_name=display_name,
            ref_slug=ref_slug,
            public_slot=slot,
            title_hint=None,
            quantity=delta,
            parser_confidence=0.84 if ref_slug or slot else 0.68,
            raw_line=text,
            needs_review=False,
            reason="reduce_delta",
        )

    is_explicit_cancel = bool(
        re.search(
            r"\b(j[aá]\s+n[aã]o\s+quero|n[aã]o\s+quero|nao\s+quero|cancela|desisto|anula)\b",
            text,
            re.IGNORECASE,
        )
    )
    if not reduce_m:
        is_explicit_cancel = is_explicit_cancel or bool(
            re.search(r"\b(?:tira|retira)\b", text, re.IGNORECASE)
        )
    is_cancel = bool(CANCEL.search(text)) and not (
        SUPERSEDE_PREFIX.search(text)
        and RESERVE_VERBS.search(text)
        and not is_explicit_cancel
    )

    if is_cancel:
        display_name, body = split_name_body(text)
        work = body if body else text
        refs = extract_ref_tokens(work)
        ref_slug = refs[0] if refs else None
        slot = extract_slot_number(work) if not ref_slug else None
        qty = extract_quantity(work)
        return ParsedComment(
            intent=ParseIntent.CANCEL,
            display_name=display_name,
            ref_slug=ref_slug,
            public_slot=slot,
            title_hint=None,
            quantity=qty,
            parser_confidence=0.82 if ref_slug or slot else 0.68,
            raw_line=text,
            needs_review=False,
            reason="cancel",
        )

    display_name, body = split_name_body(text)
    work = body if body else text

    if not RESERVE_VERBS.search(work) and not DEICTIC.search(work):
        refs_only = extract_ref_tokens(work)
        slot_only = extract_slot_number(work)
        has_qty_slot = bool(re.search(r"\b(unidades?|peças?|pcs?)\b", work, re.I)) and slot_only is not None
        if refs_only or slot_only is not None or has_qty_slot or re.fullmatch(r"\d{1,3}", work.strip()):
            pass
        else:
            return None

    qty = extract_quantity(work)
    refs = extract_ref_tokens(work)
    ref_slug: str | None = refs[0] if refs else None
    slot = extract_slot_number(work) if not ref_slug else None
    title_hint: str | None = None
    conf = 0.65
    needs_review = False
    reason: str | None = None

    # Deícticos → artigo activo
    if DEICTIC.search(work) and ctx and ctx.active_item:
        if ref_slug is None and slot is None:
            ref_slug = ctx.active_item.ref_code
            conf = 0.82
            reason = "deictic_active"
        elif ref_slug is None:
            conf = max(conf, 0.78)

    # Título como hint («quero o puzzle», «o azul»)
    title_patterns = [
        r"(?:quero|fico com|reservo)\s+(?:o\s+|a\s+)?(?P<t>[a-zà-ú]{3,30})",
        r"(?:o|a)\s+(?P<t>puzzle|mapa|azul|verde|vermelho|preto|branco|vestido|casaco)",
    ]
    for pat in title_patterns:
        m = re.search(pat, work, re.IGNORECASE)
        if m and ref_slug is None and slot is None:
            title_hint = m.group("t")
            conf = 0.68
            reason = "title_hint"
            break

    if ref_slug:
        conf = 0.92 if ("/" in ref_slug or "-" in ref_slug) else 0.85
        # Nunca interpretar 004/21 como slot 4
        slot = None
        if ctx:
            corrected, ocr_reason = resolve_ocr_ref(ref_slug, ctx)
            if corrected:
                ref_slug = corrected
                conf = min(conf + 0.04, 0.94)
                reason = ocr_reason

    if slot is not None and ref_slug is None:
        conf = 0.88 if RESERVE_VERBS.search(work) else 0.62
        if not RESERVE_VERBS.search(work) and display_name is None:
            needs_review = True
            reason = reason or "slot_only"

    if ref_slug and not RESERVE_VERBS.search(work) and display_name is None:
        # Comentário só "Q1" / "004/21" — reserva válida, revisão se confiança baixa
        conf = max(conf, 0.80)
        if re.fullmatch(r"(?:ref\s*)?[a-z0-9/\-]{2,20}", work, re.IGNORECASE):
            needs_review = True
            reason = reason or "ref_only"

    if ref_slug is None and slot is None and title_hint is None:
        if RESERVE_VERBS.search(work) or DEICTIC.search(work):
            return ParsedComment(
                intent=ParseIntent.AMBIGUOUS,
                display_name=display_name,
                ref_slug=None,
                public_slot=None,
                title_hint=None,
                quantity=qty,
                parser_confidence=0.45,
                raw_line=text,
                needs_review=True,
                reason="no_ref",
            )
        return None

    if display_name and len(display_name) >= 3:
        conf = min(conf + 0.04, 0.99)

    if ctx:
        resolved = resolve_local(ctx, ref_slug, slot, title_hint)
        if resolved == "ambiguous":
            needs_review = True
            conf = min(conf, 0.55)
            reason = reason or "ambiguous_local"

    if conf < 0.55:
        needs_review = True

    return ParsedComment(
        intent=ParseIntent.RESERVE,
        display_name=display_name,
        ref_slug=ref_slug,
        public_slot=slot,
        title_hint=title_hint,
        quantity=qty,
        parser_confidence=round(conf, 3),
        raw_line=text,
        needs_review=needs_review,
        reason=reason,
    )


def resolve_local(
    ctx: LiveContext,
    ref_slug: str | None,
    slot: int | None,
    title_hint: str | None,
) -> str | None:
    """Pré-validação local; retorna 'ambiguous' se múltiplos matches."""
    if ref_slug:
        norm = normalize_ref(ref_slug)
        matches = ctx.find_by_ref_norm(norm)
        if len(matches) > 1:
            return "ambiguous"
        if len(matches) == 1:
            return "ok"
    if slot is not None:
        matches = ctx.find_by_slot(slot)
        if len(matches) > 1:
            return "ambiguous"
    if title_hint:
        matches = ctx.find_by_title_hint(title_hint)
        if len(matches) > 1:
            return "ambiguous"
    return None
