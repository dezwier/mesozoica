"""Unit tests for player-facing knowledge title cleanup."""

from __future__ import annotations

from app.features.assistant.application.display_text import (
    clean_display_title,
    plain_display_title,
)


def test_clean_display_title_keeps_italic_spans() -> None:
    assert (
        clean_display_title("&lt;i&gt;Tyrannosaurus&lt;/i&gt; rex")
        == "<i>Tyrannosaurus</i> rex"
    )
    assert (
        clean_display_title("&lt;italic&gt;Abrosaurus&lt;/italic&gt; diet")
        == "<i>Abrosaurus</i> diet"
    )


def test_clean_display_title_inserts_missing_spaces_around_italics() -> None:
    assert (
        clean_display_title("of&lt;i&gt;T. rex&lt;/i&gt;fossils")
        == "of <i>T. rex</i> fossils"
    )


def test_clean_display_title_handles_double_escaping() -> None:
    assert (
        clean_display_title("&amp;lt;i&amp;gt;Paper&amp;lt;/i&amp;gt; title")
        == "<i>Paper</i> title"
    )


def test_clean_display_title_strips_mangled_entity_markup() -> None:
    # Colon-mangled tags cannot form a real italic span; strip leftovers.
    assert clean_display_title("&lt:italic&gt;Foo&lt:/italic&gt; bar") == "Foo bar"


def test_plain_display_title_flattens_italics() -> None:
    assert plain_display_title("&lt;i&gt;Tyrannosaurus&lt;/i&gt; rex") == "Tyrannosaurus rex"
