"""Testes identidade OCR + cenário Cláudia (stock)."""

from __future__ import annotations

from dataclasses import replace

import pytest

from fleaber_ps.parser.context import LiveContext, LiveItemContext
from fleaber_ps.parser.name_validation import is_plausible_display_name
from fleaber_ps.parser.parse_pt import ParseIntent, parse_comment_line
from fleaber_ps.parser.ref_extractor import normalize_ref
from fleaber_ps.parser.session_identity import SessionIdentity


def _claudia_ctx() -> LiveContext:
    items = [
        LiveItemContext(
            live_item_id="z1",
            ref_code="Z1",
            ref_norm=normalize_ref("Z1"),
            title="Artigo Z1",
            is_active=True,
            public_slot=1,
            catalog_ordinal=1,
            quantity=10,
        ),
        LiveItemContext(
            live_item_id="z2",
            ref_code="Z2",
            ref_norm=normalize_ref("Z2"),
            title="Artigo Z2",
            is_active=False,
            public_slot=2,
            catalog_ordinal=2,
            quantity=20,
        ),
    ]
    return LiveContext(
        live_id="live-1",
        live_title="Test",
        live_status="live",
        active_item_id="z1",
        items=items,
    )


class TestNameValidation:
    @pytest.mark.parametrize(
        "name",
        ["afinal", "C4", "so", "Facebook", "PY", "Z1", "quero"],
    )
    def test_rejects_ocr_garbage(self, name: str):
        assert is_plausible_display_name(name) is False

    def test_accepts_full_name(self):
        assert is_plausible_display_name("Cláudia Monteiro") is True


class TestClaudiaFlow:
    def test_session_identity_single_buyer(self):
        ctx = _claudia_ctx()
        identity = SessionIdentity()
        lines = [
            "Cláudia Monteiro z1",
            "Cláudia Monteiro quero 2 Z1",
            "afinal ja nao quero Z1",
            "quero 10 Z2",
            "so quero 5 Z2",
        ]
        intents = []
        for line in lines:
            parsed = parse_comment_line(line, ctx)
            assert parsed is not None, line
            parsed = identity.apply(parsed)
            assert parsed.display_name == "Cláudia Monteiro", line
            intents.append((line, parsed.intent, parsed.ref_slug, parsed.quantity))

        assert intents[0][1] == ParseIntent.RESERVE
        assert intents[1][1] == ParseIntent.RESERVE and intents[1][3] == 2
        assert intents[2][1] == ParseIntent.CANCEL
        assert intents[3][1] == ParseIntent.RESERVE and "Z2" in (intents[3][2] or "").upper()
        assert intents[4][1] == ParseIntent.RESERVE and intents[4][3] == 5

    def test_afinal_not_name_on_cancel(self):
        p = parse_comment_line("afinal ja nao quero Z1", _claudia_ctx())
        assert p is not None
        assert p.intent == ParseIntent.CANCEL
        assert p.display_name is None

    def test_so_quero_supersede_not_cancel(self):
        p = parse_comment_line("so quero 5 Z2", _claudia_ctx())
        assert p is not None
        assert p.intent == ParseIntent.RESERVE
        assert p.quantity == 5
        assert p.display_name is None

    def test_merged_name_preserved(self):
        identity = SessionIdentity()
        first = identity.apply(parse_comment_line("Cláudia Monteiro Q1", _claudia_ctx()))
        assert first.display_name == "Cláudia Monteiro"
        second = identity.apply(
            parse_comment_line("afinal ja nao quero Z1", _claudia_ctx()) or first
        )
        assert second.display_name == "Cláudia Monteiro"
