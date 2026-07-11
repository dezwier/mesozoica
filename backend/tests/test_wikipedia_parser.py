"""Tests for Wikipedia HTML parser."""

from pathlib import Path

from app.services.wikipedia_service.parser import (
    parse_article_html,
    prepare_article_for_display,
    rewrite_article_links,
)

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


def test_parse_decimal_ma_range_with_linked_unit():
    html = (
        Path(__file__).parent / "fixtures" / "wikipedia" / "aardonyx_infobox.html"
    ).read_text(encoding="utf-8")
    parsed = parse_article_html(html)

    assert parsed.birth == 201.3
    assert parsed.death == 190.8
    assert parsed.period == "Early Jurassic"


def test_parse_single_ma_sets_birth_and_death():
    html = (
        Path(__file__).parent / "fixtures" / "wikipedia" / "abditosaurus_infobox.html"
    ).read_text(encoding="utf-8")
    parsed = parse_article_html(html)

    assert parsed.birth == 70.5
    assert parsed.death == 70.5
    assert parsed.period == "Late Cretaceous"


def test_parse_genus_strips_author_from_italic_cell():
    html = """
    <table class="infobox biota">
      <tr><td>Genus:</td><td><i>Brachiosaurus</i> Riggs, 1903</td></tr>
    </table>
    """
    parsed = parse_article_html(html)
    assert parsed.cladogram["genus"] == "Brachiosaurus"


def test_parse_genus_strips_author_from_plain_text_cell():
    html = """
    <table class="infobox biota">
      <tr><td>Genus:</td><td>Brachiosaurus Riggs, 1903</td></tr>
    </table>
    """
    parsed = parse_article_html(html)
    assert parsed.cladogram["genus"] == "Brachiosaurus"


def test_parse_subfamily_strips_author_with_space_before_comma():
    html = """
    <table class="infobox biota">
      <tr><td>Subfamily:</td><td>Allosaurinae Marsh , 1878</td></tr>
    </table>
    """
    parsed = parse_article_html(html)
    assert parsed.cladogram["subfamily"] == "Allosaurinae"


def test_parse_genus_strips_author_with_initials():
    html = """
    <table class="infobox biota">
      <tr><td>Genus:</td><td><i>Apatosaurus</i> C. A. Gilmore, 1924</td></tr>
    </table>
    """
    parsed = parse_article_html(html)
    assert parsed.cladogram["genus"] == "Apatosaurus"


def test_parse_genus_ignores_authority_span():
    html = """
    <table class="infobox biota">
      <tr><td>Genus:</td><td><i>Tyrannosaurus</i> <span class="authority">Osborn, 1905</span></td></tr>
    </table>
    """
    parsed = parse_article_html(html)
    assert parsed.cladogram["genus"] == "Tyrannosaurus"


def test_parse_genus_strips_et_al_in_separate_italic_tag():
    html = """
    <table class="infobox biota">
      <tr><td>Genus:</td><td><i>Abelisaurus</i> <i>et al.</i>, 2020</td></tr>
    </table>
    """
    parsed = parse_article_html(html)
    assert parsed.cladogram["genus"] == "Abelisaurus"


def test_parse_genus_strips_author_et_al_with_year():
    html = """
    <table class="infobox biota">
      <tr><td>Genus:</td><td>Abelisaurus Bonaparte et al., 1990</td></tr>
    </table>
    """
    parsed = parse_article_html(html)
    assert parsed.cladogram["genus"] == "Abelisaurus"


def test_parse_genus_strips_et_all_typo():
    html = """
    <table class="infobox biota">
      <tr><td>Genus:</td><td><i>Abelisaurus</i> Bonaparte et all., 1990</td></tr>
    </table>
    """
    parsed = parse_article_html(html)
    assert parsed.cladogram["genus"] == "Abelisaurus"


def test_parse_genus_strips_authority_inside_single_italic_tag():
    html = """
    <table class="infobox biota">
      <tr><td>Genus:</td><td><i>Abelisaurus Bonaparte et al., 1990</i></td></tr>
    </table>
    """
    parsed = parse_article_html(html)
    assert parsed.cladogram["genus"] == "Abelisaurus"


def test_prepare_article_strips_navbox_and_references():
    html = """
    <table class="infobox biota"><tr><td>Genus:</td><td><i>Tyrannosaurus</i></td></tr></table>
    <p>Lead paragraph about Tyrannosaurus.</p>
    <div class="navbox">Navigation box</div>
    <h2><span class="mw-headline" id="References">References</span></h2>
    <ol class="references"><li>Ref one</li></ol>
    """
    prepared = prepare_article_for_display(html)
    assert prepared is not None
    assert "Lead paragraph about Tyrannosaurus." in prepared
    assert "navbox" not in prepared
    assert "Ref one" not in prepared


def test_prepare_article_rewrites_protocol_relative_image_src():
    html = """
    <p>Body text.</p>
    <img src="//upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Tyrannosaurus.jpg/220px-Tyrannosaurus.jpg" />
    """
    prepared = prepare_article_for_display(html)
    assert prepared is not None
    assert 'src="https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Tyrannosaurus.jpg/220px-Tyrannosaurus.jpg"' in prepared


def test_prepare_article_strips_intrinsic_image_dimensions():
    html = """
    <img src="//upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Tyrannosaurus.jpg/220px-Tyrannosaurus.jpg"
         width="4928" height="3264" />
    """
    prepared = prepare_article_for_display(html)
    assert prepared is not None
    assert "width=" not in prepared
    assert "height=" not in prepared


def test_prepare_article_resolves_resource_when_src_missing():
    html = """
    <img resource="./File:Tyrannosaurus_Rex_Holotype.jpg" />
    """
    prepared = prepare_article_for_display(html)
    assert prepared is not None
    assert "Special:FilePath/Tyrannosaurus_Rex_Holotype.jpg" in prepared


def test_prepare_article_handles_headings_without_attrs():
    html = """
    <p>Lead paragraph about Tyrannosaurus.</p>
    <h2><span class="mw-headline" id="References">References</span></h2>
    <ol class="references"><li>Ref one</li></ol>
    """
    prepared = prepare_article_for_display(html)
    assert prepared is not None
    assert "Lead paragraph about Tyrannosaurus." in prepared
    assert "Ref one" not in prepared
