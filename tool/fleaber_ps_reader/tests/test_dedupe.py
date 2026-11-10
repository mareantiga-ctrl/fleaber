"""Testes deduplicação."""

from fleaber_ps.core.dedupe import DedupeStore, normalize_text


def test_dedupe_line_hash():
    d = DedupeStore.empty()
    assert not d.is_duplicate_line("abc")
    d.register("abc", "key1", "actor1", "text")
    assert d.is_duplicate_line("abc")


def test_normalize_ocr_variation():
    a = normalize_text("Maria quero o 3")
    b = normalize_text("Maria  quero o  3!")
    assert a == b


def test_actor_repeat():
    d = DedupeStore.empty()
    d.register("h1", "k1", "actor", "quero o 3")
    assert d.is_repeat_reservation("actor", "quero o 3")
