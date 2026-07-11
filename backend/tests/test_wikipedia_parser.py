"""Tests for Wikipedia HTML parser."""

from pathlib import Path

from app.services.wikipedia_service.parser import parse_article_html, rewrite_article_links

_FIXTURE = Path(__file__).parent / "fixtures" / "wikipedia" / "tyrannosaurus_infobox.html"


def test_parse_infobox_fields():
    html = _FIXTURE.read_text(encoding="utf-8")
    parsed = parse_article_html(html)

    assert parsed.birth == 77.0
    assert parsed.death == 66.0
    assert parsed.period == "Late Cretaceous"
    assert parsed.diet_type == "Carnivore"
    assert parsed.cladogram["kingdom"] == "Animalia"
    assert parsed.cladogram["phylum"] == "Chordata"
    assert parsed.cladogram["genus"] == "Tyrannosaurus"
    assert parsed.cladogram["species"] == "T. rex"
    assert parsed.long_description is not None
    assert "large theropod dinosaur" in parsed.long_description


def test_rewrite_relative_links():
    html = '<a href="./Late_Cretaceous">Late Cretaceous</a>'
    rewritten = rewrite_article_links(html)
    assert "https://en.wikipedia.org/wiki/Late_Cretaceous" in rewritten
