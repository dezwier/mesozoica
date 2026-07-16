"""Tests for PBDB-driven fossil enrichment hints."""

from app.models.fossil import Fossil
from app.services.fossil_enrichment_service.pbdb_hints import (
    apply_pbdb_hints,
    infer_subcategory_from_pbdb,
)
from app.services.fossil_enrichment_service.validate import UNKNOWN, validate_llm_enrichment


def _fossil(**kwargs) -> Fossil:
    base = {"id": 219975, "dinosaur_id": 1}
    base.update(kwargs)
    return Fossil(**base)


def test_infer_subcategory_from_pbdb_detects_tooth_marks():
    fossil = _fossil(
        feed_pred_traces="tooth marks, arthropod boring",
        component_comments="tooth marks",
    )
    assert infer_subcategory_from_pbdb(fossil) == "bite_marks_and_feeding_traces"


def test_infer_subcategory_from_pbdb_detects_trackways():
    fossil = _fossil(occurrence_comments="well-preserved theropod trackway")
    assert infer_subcategory_from_pbdb(fossil) == "footprints_and_trackways"


def test_infer_subcategory_from_pbdb_returns_none_without_trace_evidence():
    fossil = _fossil(common_body_parts="teeth", pres_mode="body")
    assert infer_subcategory_from_pbdb(fossil) is None


def test_apply_pbdb_hints_fills_unknown_trace_fields():
    fossil = _fossil(
        feed_pred_traces="tooth marks, arthropod boring",
        component_comments="tooth marks",
    )
    validated = validate_llm_enrichment({"llm_subcategory": UNKNOWN})

    result = apply_pbdb_hints(fossil, validated)

    assert result.llm_subcategory == "bite_marks_and_feeding_traces"
    assert result.llm_category == "trace"
    assert result.llm_completeness == "trace_only"


def test_apply_pbdb_hints_preserves_explicit_llm_subcategory():
    fossil = _fossil(feed_pred_traces="tooth marks")
    validated = validate_llm_enrichment({"llm_subcategory": "skull"})

    result = apply_pbdb_hints(fossil, validated)

    assert result.llm_subcategory == "skull"
    assert result.llm_category == "body"
