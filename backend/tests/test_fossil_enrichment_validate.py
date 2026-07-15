"""Tests for fossil enrichment validation."""

import random

from app.services.fossil_enrichment_service.validate import (
    _BODY_SUBCATEGORIES,
    _TRACE_SUBCATEGORIES,
    validate_llm_enrichment,
)


def test_validate_llm_enrichment_accepts_valid_payload():
    raw = {
        "llm_rock_type": "sandstone",
        "llm_category": "body_fossil",
        "llm_subcategory": "skull",
        "llm_preservation_quality": "good",
        "llm_completeness": "partial",
        "llm_description": "A partial skull from Late Cretaceous sandstone in Montana.",
    }
    result = validate_llm_enrichment(raw)
    assert result.llm_rock_type == "sandstone"
    assert result.llm_category == "body_fossil"
    assert result.llm_subcategory == "skull"
    assert result.llm_preservation_quality == "good"
    assert result.llm_completeness == "partial"
    assert result.llm_description == (
        "A partial skull from Late Cretaceous sandstone in Montana."
    )


def test_validate_llm_enrichment_defaults_missing_keys_to_random_allowed_values():
    random.seed(0)
    result = validate_llm_enrichment({})
    assert result.llm_rock_type in {
        "mudstone",
        "shale",
        "siltstone",
        "sandstone",
        "conglomerate",
        "limestone",
        "marl",
        "chalk",
        "claystone",
        "coal",
        "volcanic_ash",
        "tuff",
        "ironstone",
        "phosphorite",
        "evaporite",
        "other",
    }
    assert result.llm_category in {"body_fossil", "trace_fossil"}
    assert result.llm_subcategory in _BODY_SUBCATEGORIES | _TRACE_SUBCATEGORIES
    assert result.llm_preservation_quality in {
        "exceptional",
        "excellent",
        "good",
        "moderate",
        "poor",
        "very_poor",
    }
    assert result.llm_completeness in {
        "nearly_complete",
        "substantial",
        "partial",
        "fragmentary",
        "isolated_element",
        "trace_only",
    }
    assert result.llm_description is None


def test_validate_llm_enrichment_coerces_empty_description_to_none():
    result = validate_llm_enrichment({"llm_description": "   "})
    assert result.llm_description is None


def test_validate_llm_enrichment_coerces_snake_case():
    raw = {
        "llm_rock_type": "Volcanic Ash",
        "llm_category": "trace_fossil",
        "llm_subcategory": "Footprints and Trackways",
        "llm_preservation_quality": "Very Poor",
        "llm_completeness": "Trace Only",
    }
    result = validate_llm_enrichment(raw)
    assert result.llm_rock_type == "volcanic_ash"
    assert result.llm_category == "trace_fossil"
    assert result.llm_subcategory == "footprints_and_trackways"
    assert result.llm_preservation_quality == "very_poor"
    assert result.llm_completeness == "trace_only"


def test_validate_llm_enrichment_coerces_unlisted_enum_to_random_allowed_value():
    random.seed(1)
    result = validate_llm_enrichment({"llm_rock_type": "granite"})
    assert result.llm_rock_type != "granite"
    assert result.llm_rock_type in {
        "mudstone",
        "shale",
        "siltstone",
        "sandstone",
        "conglomerate",
        "limestone",
        "marl",
        "chalk",
        "claystone",
        "coal",
        "volcanic_ash",
        "tuff",
        "ironstone",
        "phosphorite",
        "evaporite",
        "other",
    }


def test_validate_llm_enrichment_coerces_not_reported_to_random_allowed_value():
    random.seed(2)
    result = validate_llm_enrichment({"llm_rock_type": "not reported"})
    assert result.llm_rock_type in {
        "mudstone",
        "shale",
        "siltstone",
        "sandstone",
        "conglomerate",
        "limestone",
        "marl",
        "chalk",
        "claystone",
        "coal",
        "volcanic_ash",
        "tuff",
        "ironstone",
        "phosphorite",
        "evaporite",
        "other",
    }


def test_validate_llm_enrichment_coerces_category_mismatch_to_body_subcategory():
    random.seed(3)
    result = validate_llm_enrichment(
        {
            "llm_category": "body_fossil",
            "llm_subcategory": "coprolites",
        }
    )
    assert result.llm_subcategory in _BODY_SUBCATEGORIES


def test_validate_llm_enrichment_coerces_trace_completeness_mismatch():
    result = validate_llm_enrichment(
        {
            "llm_category": "trace_fossil",
            "llm_subcategory": "coprolites",
            "llm_completeness": "partial",
        }
    )
    assert result.llm_completeness == "trace_only"
