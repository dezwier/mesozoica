"""Tests for Imagen prompt builders and text helpers."""

from __future__ import annotations

from decimal import Decimal

from app.models.fossil import Fossil
from app.services.image_generation_service.article_text import extract_article_text
from app.services.image_generation_service.fossil_json import (
    fossil_to_image_prompt_dict,
    fossil_to_prompt_dict,
    fossil_to_prompt_json,
)
from app.services.image_generation_service.prompting import (
    build_dinosaur_image_prompt,
    build_fossil_image_prompt,
    build_fossil_preservation_brief,
    build_site_type_image_prompt,
)


def test_build_dinosaur_image_prompt_includes_name_and_article():
    prompt = build_dinosaur_image_prompt(
        "Tyrannosaurus",
        "Tyrannosaurus was a large theropod dinosaur.",
    )
    assert "Tyrannosaurus" in prompt
    assert "dramatic warm" in prompt
    assert "3:4" in prompt
    assert "iphone photograph" in prompt.lower()
    assert "Tyrannosaurus was a large theropod dinosaur." in prompt


def test_extract_article_text_uses_lead_paragraphs_only():
    html = """
    <html><body>
      <p>First lead paragraph about the dinosaur genus.</p>
      <p>Second lead paragraph with more detail about fossils.</p>
      <h2>Discovery</h2>
      <p>This section should not appear in the excerpt.</p>
    </body></html>
    """
    text = extract_article_text(html, max_chars=5000)
    assert "First lead paragraph" in text
    assert "Second lead paragraph" in text
    assert "Discovery" not in text
    assert "should not appear" not in text


def test_extract_article_text_truncates_long_content():
    html = "<p>" + ("A" * 2000) + "</p>"
    text = extract_article_text(html, max_chars=100)
    assert len(text) <= 100
    assert text.endswith("...")


def test_fossil_to_prompt_dict_omits_nulls_and_includes_dino_name():
    fossil = Fossil(
        id=139292,
        dinosaur_id=1,
        pres_mode="body",
        geological_formation="Scollard",
        min_age_ma=Decimal("66.0"),
        max_age_ma=Decimal("72.2"),
        main_image_url="https://example.com/old.jpg",
    )
    payload = fossil_to_prompt_dict(fossil, dinosaur_name="Tyrannosaurus")
    assert payload["dinosaur_name"] == "Tyrannosaurus"
    assert payload["id"] == 139292
    assert payload["pres_mode"] == "body"
    assert payload["geological_formation"] == "Scollard"
    assert "main_image_url" not in payload
    assert "dinosaur_id" in payload


def test_fossil_to_image_prompt_dict_includes_only_llm_fields():
    fossil = Fossil(
        id=139292,
        dinosaur_id=1,
        pres_mode="body",
        occurrence_comments="NMC 9554",
        common_body_parts="skull, vertebrae",
        reference_no=4218,
        museum="GSC",
        country_code="CA",
        geological_formation="Scollard",
        llm_rock_type="sandstone",
        llm_category="body_fossil",
        llm_subcategory="skull",
        llm_completeness="partial",
        llm_preservation_quality="good",
    )
    payload = fossil_to_image_prompt_dict(fossil, dinosaur_name="Tyrannosaurus")
    assert payload == {
        "dinosaur": "Tyrannosaurus",
        "llm_rock_type": "sandstone",
        "llm_category": "body_fossil",
        "llm_subcategory": "skull",
        "llm_completeness": "partial",
        "llm_quality": "good",
    }


def test_fossil_to_image_prompt_dict_omits_unset_llm_fields():
    fossil = Fossil(
        id=1,
        dinosaur_id=1,
        occurrence_comments="partial skull and vertebrae",
        pres_mode="body",
    )
    payload = fossil_to_image_prompt_dict(fossil, dinosaur_name="Tyrannosaurus")
    assert payload == {"dinosaur": "Tyrannosaurus"}


def test_build_fossil_image_prompt_includes_llm_fields_and_dinosaur():
    fossil = Fossil(
        id=291021,
        dinosaur_id=2,
        pres_mode="body",
        common_body_parts="femur, tibia",
        llm_rock_type="mudstone",
        llm_category="body_fossil",
        llm_subcategory="hindlimbs",
        llm_completeness="isolated_element",
        llm_preservation_quality="moderate",
    )
    payload = fossil_to_image_prompt_dict(fossil, dinosaur_name="Allosaurus")
    prompt = build_fossil_image_prompt(payload)
    assert "291021" not in prompt
    assert "Allosaurus" in prompt
    assert "primary subject" in prompt.lower()
    assert "hindlimbs" in prompt
    assert "mudstone" in prompt
    assert "dramatic warm" in prompt
    assert "iphone" in prompt.lower()
    assert "femur, tibia" not in prompt
    assert "reference_no" not in prompt


def test_build_fossil_preservation_brief_maps_llm_fields():
    brief = build_fossil_preservation_brief(
        {
            "dinosaur": "Iguanodon",
            "llm_category": "trace_fossil",
            "llm_subcategory": "footprints_and_trackways",
            "llm_quality": "poor",
            "llm_completeness": "trace_only",
            "llm_rock_type": "sandstone",
        }
    )
    assert "Iguanodon" in brief
    assert "trace_fossil" in brief
    assert "footprints and trackways" in brief
    assert "poor" in brief
    assert "trace_only" in brief
    assert "sandstone" in brief


def test_fossil_to_prompt_json_respects_max_chars():
    fossil = Fossil(
        id=1,
        dinosaur_id=1,
        component_comments="x" * 5000,
        geogcomments="y" * 5000,
        pres_mode="body",
    )
    text = fossil_to_prompt_json(fossil, dinosaur_name="Foo", max_chars=400)
    assert len(text) <= 400


def test_build_site_type_image_prompt_emphasizes_rock_type_and_period():
    prompt = build_site_type_image_prompt(
        period="cretaceous",
        rock_type="sandstone",
    )
    assert "sandstone" in prompt
    assert "Cretaceous" in prompt
    assert "3:4" in prompt
    assert "dramatic warm" in prompt
    assert "field outcrop" in prompt.lower()
    assert "scrappy" in prompt.lower()
    assert "too clean" in prompt.lower()
    assert "no text" in prompt.lower()
    assert "no people" in prompt.lower()


def test_build_site_type_image_prompt_includes_period_context_for_triassic():
    prompt = build_site_type_image_prompt(
        period="triassic",
        rock_type="claystone",
    )
    assert "claystone" in prompt
    assert "Triassic" in prompt
    assert "252" in prompt or "201" in prompt
