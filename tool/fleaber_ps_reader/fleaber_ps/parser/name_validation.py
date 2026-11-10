"""Validação de nomes OCR — evita «afinal», «C4», «so» como comprador."""

from __future__ import annotations

import re
import unicodedata

# Palavras PT live-shopping — nunca são nome de pessoa.
NOT_DISPLAY_NAMES = frozenset(
    {
        "afinal",
        "so",
        "só",
        "ja",
        "já",
        "nao",
        "não",
        "quero",
        "queria",
        "cancela",
        "cancelar",
        "desisto",
        "facebook",
        "cliente",
        "comprador",
        "responder",
        "gosto",
        "partilhar",
        "reserva",
        "reservo",
        "apenas",
        "corrigo",
        "mudo",
        "mete",
        "leva",
        "pego",
        "pega",
        "teste",
        "ola",
        "olá",
        "boa",
        "noite",
        "py",
        "ocr",
        "live",
        "directo",
        "direto",
        "comentario",
        "comentário",
        "min",
        "agora",
        "entao",
        "então",
        "pronto",
        "obrigado",
        "obrigada",
        "fixe",
        "lindo",
        "linda",
        "beijinhos",
        "bjs",
        "ola",
        "adeus",
        "tchau",
        "sim",
        "nao",
        "não",
        "ok",
        "okay",
        "certo",
        "isso",
        "essa",
        "esse",
        "este",
        "esta",
        "aquela",
        "aquele",
        "ultimo",
        "último",
        "ultima",
        "última",
        "fico",
        "fica",
        "para",
        "mim",
        "mais",
        "menos",
        "unidade",
        "unidades",
        "peca",
        "peça",
        "pecas",
        "peças",
        "pcs",
        "ref",
        "refs",
        "artigo",
        "produto",
        "preco",
        "preço",
        "envio",
        "portes",
        "mbway",
        "mb",
        "way",
        "pago",
        "pagamento",
        "disponivel",
        "disponível",
        "esgotado",
        "stock",
        "saco",
        "adiciona",
        "adicionar",
        "remove",
        "remover",
        "troca",
        "trocar",
        "muda",
        "mudar",
        "altera",
        "alterar",
        "corrige",
        "corrigir",
        "enganei",
        "errei",
        "desculpa",
        "desculpem",
        "perdao",
        "perdão",
        "espera",
        "espere",
        "aguarda",
        "aguarde",
        "calma",
        "atenção",
        "atencao",
        "vendedor",
        "vendedora",
        "host",
        "mod",
        "admin",
    }
)

# Verbos/modificadores que podem aparecer colados ao nome OCR.
_NAME_FORBIDDEN_WORDS = NOT_DISPLAY_NAMES | frozenset(
    {
        "quero", "queria", "reservo", "reserva", "fico", "leva", "pego", "pega",
        "mete", "adiciona", "adicionar", "afinal", "so", "só", "ja", "já",
        "apenas", "corrigo", "mudo", "unidades", "unidade", "peca", "peça",
    }
)
_LEADING_PHRASE = re.compile(
    r"^(?:afinal|so|só|ja|já|nao|não|apenas|corrigo|mudo|enganei|errei|"
    r"desculpa|desculpem|perdao|perdão|espera|espere|calma)\b",
    re.IGNORECASE,
)

# Prefixos OCR lixo: (PY), (OCR), (=4/, <A/, etc.
_OCR_PREFIX = re.compile(r"\([A-Za-z0-9]{1,5}\)\s*")
_LEADING_JUNK = re.compile(r'^[\s"\'*+\-€=\(<>\[\]/\\;0-9A]+', re.IGNORECASE)
_MERGED_TIRA = re.compile(r"\b(tira|retira)(\d{1,2})\b", re.IGNORECASE)
_MERGED_JA_NAO = re.compile(r"\bjanao\b", re.IGNORECASE)

# Nome típico FB: «Cláudia Monteiro» — 2+ palavras ou nome longo.
_NAME_LIKE = re.compile(
    r"^[A-Za-zÀ-ú][a-zà-ú'`.-]*(?:\s+[A-Za-zÀ-ú][a-zà-ú'`.-]+)+$",
)

# Ref confundida com nome: C4, Z1, 7Z, Q12
_REF_LIKE_NAME = re.compile(r"^[a-z0-9]{1,4}$|^[a-z]\d{1,2}$|^\d[a-z]{1,2}$", re.I)


def normalize_display_name(value: str) -> str:
    text = unicodedata.normalize("NFKD", value.strip().lower())
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    return re.sub(r"\s+", " ", text).strip()


def strip_ocr_artifacts(text: str) -> str:
    t = text.strip()
    for _ in range(3):
        t = _OCR_PREFIX.sub("", t).strip()
        t = _LEADING_JUNK.sub("", t).strip()
    return t


def normalize_ocr_line(text: str) -> str:
    """Limpa lixo OCR antes do parser (tira2 -> tira 2, janao -> ja nao)."""
    t = strip_ocr_artifacts(" ".join(text.split()))
    t = _MERGED_JA_NAO.sub("ja nao", t)
    t = _MERGED_TIRA.sub(r"\1 \2", t)
    return t.strip()


def is_plausible_display_name(name: str | None) -> bool:
    if not name:
        return False
    raw = strip_ocr_artifacts(name.strip())
    if len(raw) < 3:
        return False
    if _LEADING_PHRASE.match(raw):
        return False
    norm = normalize_display_name(raw)
    if norm in NOT_DISPLAY_NAMES:
        return False
    words = norm.split()
    if any(w in _NAME_FORBIDDEN_WORDS for w in words):
        return False
    first = words[0] if words else ""
    if first in NOT_DISPLAY_NAMES:
        return False
    if _REF_LIKE_NAME.fullmatch(norm):
        return False
    if re.fullmatch(r"[a-z]\d{1,2}", norm):
        return False
    # Nome completo «Nome Apelido»
    if _NAME_LIKE.match(raw):
        return True
    # Nome único longo (≥6 chars, só letras)
    if len(norm) >= 6 and re.fullmatch(r"[a-zà-ú\s'.-]+", norm):
        return True
    return False
