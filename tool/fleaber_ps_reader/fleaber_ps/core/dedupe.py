"""Deduplicação local de comentários."""

from __future__ import annotations

import hashlib
import re
import unicodedata
from dataclasses import dataclass


def normalize_text(text: str) -> str:
    t = unicodedata.normalize("NFKD", text.lower())
    t = "".join(c for c in t if not unicodedata.combining(c))
    t = re.sub(r"[^a-z0-9\s/\-#]", "", t)
    return re.sub(r"\s+", " ", t).strip()


def normalize_ref_key(ref_part: str) -> str:
    return re.sub(r"[^A-Z0-9]", "", ref_part.upper())


def reservation_key(live_id: str, buyer_ref: str, ref_part: str) -> str:
    """Chave estável comprador+artigo — supersede no servidor, não bloquear local."""
    ref = normalize_ref_key(ref_part)
    buyer = buyer_ref.strip()
    if not ref or not buyer:
        return ""
    payload = f"{live_id}|{buyer}|{ref}"
    return hashlib.sha256(payload.encode()).hexdigest()[:24]


@dataclass
class DedupeStore:
    line_hashes: set[str]
    comment_keys: set[str]
    actor_recent: dict[str, list[str]]

    @classmethod
    def empty(cls) -> DedupeStore:
        return cls(set(), set(), {})

    @classmethod
    def from_lists(
        cls,
        hashes: list[str],
        keys: list[str],
        _reservation_keys: list[str] | None = None,
    ) -> DedupeStore:
        return cls(set(hashes), set(keys), {})

    def is_duplicate_line(self, line_hash: str) -> bool:
        return line_hash in self.line_hashes

    def comment_key(
        self,
        actor_ref: str,
        normalized_text: str,
        ref_part: str,
    ) -> str:
        payload = f"{actor_ref}|{normalized_text}|{ref_part}"
        return hashlib.sha256(payload.encode()).hexdigest()[:24]

    def is_duplicate_comment(self, key: str) -> bool:
        return key in self.comment_keys

    def register(
        self,
        line_hash: str,
        comment_key: str,
        actor_ref: str,
        norm_text: str,
        _reservation_key: str = "",
    ) -> None:
        self.line_hashes.add(line_hash)
        self.comment_keys.add(comment_key)
        recent = self.actor_recent.setdefault(actor_ref, [])
        recent.append(norm_text)
        self.actor_recent[actor_ref] = recent[-10:]

    def is_repeat_reservation(self, actor_ref: str, norm_text: str, window: int = 3) -> bool:
        recent = self.actor_recent.get(actor_ref, [])
        return norm_text in recent[-window:]

    def to_persist(self, limit: int = 800) -> tuple[list[str], list[str], list[str]]:
        return (
            list(self.line_hashes)[-limit:],
            list(self.comment_keys)[-limit * 2:],
            [],
        )
