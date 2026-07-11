"""Tests for dinosaur enrichment validation."""

from app.services.dinosaur_enrichment_service.validate import validate_llm_enrichment


def test_validate_llm_enrichment_accepts_llm_payload():
    raw = {
        "length": "12 m",
        "mass": "5-10 t",
        "location": "western North America",
        "diet_type": "carnivore",
        "short_description": (
            "A towering Late Cretaceous apex predator whose bone-crushing bite "
            "made it the most famous dinosaur of all time."
        ),
    }
    result = validate_llm_enrichment(raw)
    assert result.length == "12 m"
    assert result.mass == "5-10 t"
    assert result.location == "western North America"
    assert result.diet_type == "carnivore"


def test_validate_llm_enrichment_coerces_numeric_values():
    raw = {
        "length": 12.5,
        "mass": 7000,
        "location": None,
        "diet_type": "carnivore",
        "short_description": "A large theropod predator from the Late Cretaceous.",
    }
    result = validate_llm_enrichment(raw)
    assert result.length == "12.5"
    assert result.mass == "7000"
