"""Resolve identidade OCR estável (sessão live)."""

from __future__ import annotations

from dataclasses import replace

from fleaber_ps.parser.name_validation import is_plausible_display_name, normalize_display_name
from fleaber_ps.parser.parse_pt import ParseIntent, ParsedComment


class SessionIdentity:
    """Último nome FB válido visto nesta sessão de leitura."""

    def __init__(self) -> None:
        self._last_valid_name: str | None = None
        self._last_ref: str | None = None
        self._by_ref: dict[str, str] = {}
        self._buyer_ref_touch: set[str] = set()

    def _touch_key(self, name: str, ref: str) -> str:
        return f"{normalize_display_name(name)}|{ref.strip().upper()}"

    def register_touch(self, name: str | None, ref: str | None) -> None:
        if not name or not ref:
            return
        if not is_plausible_display_name(name):
            return
        self._buyer_ref_touch.add(self._touch_key(name, ref))
        self._last_ref = ref.strip().upper()

    def buyer_touched_ref(self, name: str | None, ref: str | None) -> bool:
        if not name or not ref:
            return False
        return self._touch_key(name, ref) in self._buyer_ref_touch

    def has_prior_context(self) -> bool:
        return self._last_valid_name is not None and bool(
            self._by_ref or self._buyer_ref_touch or self._last_ref
        )

    def apply(self, parsed: ParsedComment) -> ParsedComment:
        ref_key = (parsed.ref_slug or str(parsed.public_slot or "")).upper()
        out = parsed

        if parsed.display_name and is_plausible_display_name(parsed.display_name):
            name = parsed.display_name.strip()
            self._last_valid_name = name
            if ref_key:
                self._by_ref[ref_key] = name
                if parsed.ref_slug:
                    self._last_ref = parsed.ref_slug.strip().upper()
            out = parsed
        elif ref_key and ref_key in self._by_ref:
            out = replace(parsed, display_name=self._by_ref[ref_key])
        elif self._last_valid_name:
            out = replace(parsed, display_name=self._last_valid_name)
        elif parsed.display_name and not is_plausible_display_name(parsed.display_name):
            out = replace(parsed, display_name=None)

        # Continuidade: «afinal so quero 2» sem ref → último artigo
        if (
            out.intent == ParseIntent.RESERVE
            and not out.ref_slug
            and out.public_slot is None
            and self._last_ref
        ):
            out = replace(
                out,
                ref_slug=self._last_ref,
                needs_review=False,
                reason=out.reason or "continuity_last_ref",
                parser_confidence=min(out.parser_confidence, 0.78),
            )

        if out.ref_slug:
            self._last_ref = out.ref_slug.strip().upper()
        return out

    @property
    def last_valid_name(self) -> str | None:
        return self._last_valid_name

    @property
    def last_ref(self) -> str | None:
        return self._last_ref
