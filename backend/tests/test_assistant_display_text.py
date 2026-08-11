"""Unit tests for player-facing knowledge title cleanup."""

from __future__ import annotations

from app.features.assistant.application.display_text import clean_display_title


def test_clean_display_title_strips_html_entities_and_tags() -> None:
    assert (
        clean_display_title("&lt;i&gt;Tyrannosaurus&lt;/i&gt; rex")
        == "Tyrannosaurus rex"
    )
    assert (
        clean_display_title("&lt;italic&gt;Abrosaurus&lt;/italic&gt; diet")
        == "Abrosaurus diet"
    )


def test_clean_display_title_handles_double_escaping() -> None:
    assert (
        clean_display_title("&amp;lt;i&amp;gt;Paper&amp;lt;/i&amp;gt; title")
        == "Paper title"
    )


def test_clean_display_title_strips_mangled_entity_markup() -> None:
    assert clean_display_title("&lt:italic&gt;Foo&lt:/italic&gt; bar") == "Foo bar"
