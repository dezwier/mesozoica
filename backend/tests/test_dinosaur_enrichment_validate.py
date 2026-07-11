"""Tests for dinosaur enrichment validation."""

from __future__ import annotations

import pytest

from app.services.dinosaur_enrichment_service.validate import (
    DinosaurEnrichmentOutput,
    validate_llm_enrichment,
)


def test_validate_llm_enrichment_accepts_good_payload():
    raw = {
        "length": "12 m (39 ft)",
        "mass": "7 t",
        "location": "western North America",
        "diet_type": "Carnivore",
        "short_description": (
            "A towering Late Cretaceous apex predator whose bone-crushing bite "
            "made it the most famous dinosaur of all time."
        ),
    }
    result = validate_llm_enrichment(raw)
    assert result.length == "12 m (39 ft)"
    assert result.mass == "7 t"
    assert result.location == "western North America"
    assert result.diet_type == "carnivore"


def test_validate_llm_enrichment_rejects_placeholders():
    raw = {
        "length": "N/A",
        "mass": "unknown",
        "location": "?",
        "diet_type": "carnivore",
        "short_description": "A well-known theropod from the Late Cretaceous of North America.",
    }
    result = validate_llm_enrichment(raw)
    assert result.length is None
    assert result.mass is None
    assert result.location is None


def test_validate_llm_enrichment_accepts_decimal_in_description():
    raw = {
        "length": "17.5 m",
        "mass": "5 t",
        "location": "Spain",
        "diet_type": "herbivore",
        "short_description": (
            "This colossal 17.5-meter titanosaur from the Late Cretaceous "
            "roamed the Ibero-Armorican Island."
        ),
    }
    result = validate_llm_enrichment(raw)
    assert result.length == "17.5 m"
    assert result.short_description.startswith("This colossal 17.5-meter")


def test_validate_llm_enrichment_coerces_numeric_length_mass():
    raw = {
        "length": 12.5,
        "mass": 7000,
        "location": "North America",
        "diet_type": "carnivore",
        "short_description": "A large theropod predator from the Late Cretaceous of North America.",
    }
    result = validate_llm_enrichment(raw)
    assert result.length == "12.5"
    assert result.mass == "7000"


def test_validate_llm_enrichment_rejects_multi_sentence_description():
    with pytest.raises(ValueError, match="single sentence"):
        DinosaurEnrichmentOutput.model_validate(
            {
                "diet_type": "herbivore",
                "short_description": "First sentence. Second sentence here for testing.",
            }
        )


def test_validate_llm_enrichment_rejects_too_short_description():
    with pytest.raises(ValueError):
        DinosaurEnrichmentOutput.model_validate(
            {
                "diet_type": "herbivore",
                "short_description": "Too short.",
            }
        )
