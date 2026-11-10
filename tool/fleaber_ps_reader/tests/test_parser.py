"""Testes parser PT v2 + refs alfanuméricas."""

from __future__ import annotations

import pytest

from fleaber_ps.parser.context import LiveContext, LiveItemContext
from fleaber_ps.parser.parse_pt import ParseIntent, parse_comment_line
from fleaber_ps.parser.ref_extractor import extract_ref_tokens, extract_slot_number, normalize_ref


def _ctx() -> LiveContext:
    items = [
        LiveItemContext(
            live_item_id="a1",
            ref_code="#004/21",
            ref_norm=normalize_ref("#004/21"),
            title="Puzzle",
            is_active=True,
            public_slot=1,
            catalog_ordinal=1,
            quantity=2,
        ),
        LiveItemContext(
            live_item_id="a2",
            ref_code="#004/22",
            ref_norm=normalize_ref("#004/22"),
            title="Puzzle verde",
            is_active=False,
            public_slot=2,
            catalog_ordinal=2,
            quantity=1,
        ),
        LiveItemContext(
            live_item_id="a3",
            ref_code="A15",
            ref_norm=normalize_ref("A15"),
            title="Casaco",
            is_active=False,
            public_slot=3,
            catalog_ordinal=3,
            quantity=1,
        ),
    ]
    return LiveContext(
        live_id="live-1",
        live_title="Test",
        live_status="live",
        active_item_id="a1",
        items=items,
    )


class TestRefExtractor:
    def test_normalize_ref(self):
        assert normalize_ref("#004/21") == "00421"
        assert normalize_ref("L-32") == "L32"

    def test_extract_ref_004_21(self):
        tokens = extract_ref_tokens("Maria quero o 004/21")
        assert any("004/21" in t for t in tokens)

    def test_slot_not_from_ref(self):
        assert extract_slot_number("Maria quero o 004/21") is None

    def test_extract_ref_q1(self):
        tokens = extract_ref_tokens("Q1")
        assert tokens == ["Q1"]

    def test_extract_ref_ref_q1(self):
        tokens = extract_ref_tokens("REF Q1")
        assert any("Q1" in t.upper() for t in tokens)


class TestParser:
    def test_ref_004_21(self):
        p = parse_comment_line("Maria quero o 004/21", _ctx())
        assert p is not None
        assert p.intent == ParseIntent.RESERVE
        assert p.ref_slug is not None
        assert "004/21" in p.ref_slug
        assert p.public_slot is None

    def test_slot_1(self):
        p = parse_comment_line("Maria quero o 1", _ctx())
        assert p is not None
        assert p.public_slot == 1
        assert p.ref_slug is None

    def test_deictic_active(self):
        p = parse_comment_line("Ana quero esse", _ctx())
        assert p is not None
        assert p.ref_slug is not None

    def test_no_intent_chat(self):
        assert parse_comment_line("ola boa live") is None

    def test_quantity_two(self):
        p = parse_comment_line("João quero 2 unidades do 1", _ctx())
        assert p is not None
        assert p.quantity == 2

    def test_a15_ref(self):
        p = parse_comment_line("Sara fico com o A15", _ctx())
        assert p is not None
        assert p.ref_slug and "A15" in p.ref_slug.upper()

    def test_q1_shorthand_only(self):
        p = parse_comment_line("Q1", _ctx())
        assert p is not None
        assert p.intent == ParseIntent.RESERVE
        assert p.ref_slug and p.ref_slug.upper().startswith("Q1")

    def test_q1_with_name_merged(self):
        p = parse_comment_line("Cláudia Monteiro Q1", _ctx())
        assert p is not None
        assert p.display_name == "Cláudia Monteiro"
        assert p.ref_slug and "Q1" in p.ref_slug.upper()

    def test_ref_q1_explicit(self):
        p = parse_comment_line("Maria quero o REF Q1", _ctx())
        assert p is not None
        assert p.ref_slug is not None

    def test_qty_quero_2_q1(self):
        p = parse_comment_line("Maria quero 2 Q1", _ctx())
        assert p is not None
        assert p.quantity == 2
        assert p.ref_slug and "Q1" in p.ref_slug.upper()

    def test_supersede_qty_phrase(self):
        p = parse_comment_line("afinal só quero 1 Q1", _ctx())
        assert p is not None
        assert p.quantity == 1

    def test_cancel_with_ref(self):
        p = parse_comment_line("Maria cancela Q1", _ctx())
        assert p is not None
        assert p.intent == ParseIntent.CANCEL
        assert p.ref_slug and "Q1" in p.ref_slug.upper()

    def test_qty_only_supersede_not_slot(self):
        items = [
            LiveItemContext(
                live_item_id="zm1",
                ref_code="ZM1",
                ref_norm=normalize_ref("ZM1"),
                title="ZM1",
                is_active=True,
                public_slot=1,
                catalog_ordinal=1,
                quantity=10,
            ),
            LiveItemContext(
                live_item_id="zm2",
                ref_code="ZM2",
                ref_norm=normalize_ref("ZM2"),
                title="ZM2",
                is_active=False,
                public_slot=2,
                catalog_ordinal=2,
                quantity=10,
            ),
        ]
        ctx = LiveContext(
            live_id="live-1",
            live_title="Test",
            live_status="live",
            active_item_id="zm1",
            items=items,
        )
        p = parse_comment_line("afinal ja so quero 2", ctx)
        assert p is not None
        assert p.quantity == 2
        assert p.public_slot is None
        assert p.ref_slug is None or "ZM" in (p.ref_slug or "").upper()
        items = [
            LiveItemContext(
                live_item_id="zv2",
                ref_code="ZV2",
                ref_norm=normalize_ref("ZV2"),
                title="ZV2",
                is_active=True,
                public_slot=1,
                catalog_ordinal=1,
                quantity=10,
            ),
        ]
        ctx = LiveContext(
            live_id="live-1",
            live_title="Test",
            live_status="live",
            active_item_id="zv2",
            items=items,
        )
        p = parse_comment_line("(<A4/ tira2 ZV2", ctx)
        assert p is not None
        assert p.intent == ParseIntent.RESERVE
        assert p.ref_slug == "ZV2"
        assert p.quantity == 2
        assert p.reason == "reduce_delta"

    def test_cancel_ocr_janao(self):
        p = parse_comment_line('"8/ janao quero ZV1', _ctx())
        assert p is not None
        assert p.intent == ParseIntent.CANCEL


CORPUS = [
    ("Maria quero o 004/21", True, "004"),
    ("quero o 1", True, "slot"),
    ("fico com o puzzle", True, "title"),
    ("3", True, "slot_only"),
    ("boa noite", False, None),
    ("Pedro reserva o #004/22", True, "004"),
    ("L-32 para mim", True, "L"),
    ("duas unidades do 2", True, "qty"),
    ("quero esse", True, "deictic"),
    ("cancela", True, "cancel"),
]


def test_ocr_confusion_z_vs_7():
    items = [
        LiveItemContext(
            live_item_id="z1",
            ref_code="Z1",
            ref_norm=normalize_ref("Z1"),
            title="Artigo Z1",
            is_active=True,
            public_slot=1,
            catalog_ordinal=1,
            quantity=1,
        ),
        LiveItemContext(
            live_item_id="z2",
            ref_code="Z2",
            ref_norm=normalize_ref("Z2"),
            title="Artigo Z2",
            is_active=False,
            public_slot=2,
            catalog_ordinal=2,
            quantity=2,
        ),
    ]
    ctx = LiveContext(
        live_id="live-1",
        live_title="Test",
        live_status="live",
        active_item_id="z1",
        items=items,
    )
    p = parse_comment_line("Mariana Soares quero 2 728", ctx)
    assert p is not None
    assert p.ref_slug == "Z2"
    assert p.quantity == 2

    p2 = parse_comment_line("Mariana Soares Quero 2 z1", ctx)
    assert p2 is not None
    assert p2.ref_slug == "Z1"
    assert p2.quantity == 2

    p3 = parse_comment_line("Mariana Soares quero 271", ctx)
    assert p3 is not None
    assert p3.ref_slug == "Z1"


@pytest.mark.parametrize("text,should_match,kind", CORPUS)
def test_corpus(text: str, should_match: bool, kind: str | None):
    p = parse_comment_line(text, _ctx())
    if should_match:
        assert p is not None, f"expected match: {text}"
    else:
        assert p is None, f"expected no match: {text}"
