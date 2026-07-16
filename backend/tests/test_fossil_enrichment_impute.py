"""Tests for fossil enrichment imputation."""

from __future__ import annotations

import random

from app.services.fossil_enrichment_service.impute import impute_llm_fields
from app.services.fossil_enrichment_service.validate import (
    BODY_SUBCATEGORIES,
    CATEGORIES,
    COMPLETENESS_VALUES,
    PRESERVATION_QUALITIES,
    ROCK_TYPES,
    TRACE_SUBCATEGORIES,
    UNKNOWN,
    FossilEnrichmentOutput,
    validate_llm_enrichment,
)


def test_impute_copies_known_values():
    validated = validate_llm_enrichment(
        {
            "llm_rock_type": "sandstone",
            "llm_subcategory": "skull",
            "llm_preservation_quality": "good",
            "llm_completeness": "partial",
        }
    )
    imputed = impute_llm_fields(validated)
    assert imputed.llm_imp_rock_type == "sandstone"
    assert imputed.llm_imp_category == "body"
    assert imputed.llm_imp_subcategory == "skull"
    assert imputed.llm_imp_preservation_quality == "good"
    assert imputed.llm_imp_completeness == "partial"


def test_impute_samples_unknown_fields():
    random.seed(0)
    validated = FossilEnrichmentOutput()
    imputed = impute_llm_fields(validated)
    assert imputed.llm_imp_rock_type in ROCK_TYPES
    assert imputed.llm_imp_category in CATEGORIES
    if imputed.llm_imp_category == "body":
        assert imputed.llm_imp_subcategory in BODY_SUBCATEGORIES
    else:
        assert imputed.llm_imp_subcategory in TRACE_SUBCATEGORIES
    assert imputed.llm_imp_preservation_quality in PRESERVATION_QUALITIES
    assert imputed.llm_imp_completeness in COMPLETENESS_VALUES


def test_impute_copies_derived_body_category_and_subcategory():
    validated = validate_llm_enrichment({"llm_subcategory": "skull"})
    imputed = impute_llm_fields(validated)
    assert imputed.llm_imp_category == "body"
    assert imputed.llm_imp_subcategory == "skull"


def test_impute_copies_derived_trace_category_and_subcategory():
    validated = validate_llm_enrichment({"llm_subcategory": "coprolites"})
    imputed = impute_llm_fields(validated)
    assert imputed.llm_imp_category == "trace"
    assert imputed.llm_imp_subcategory == "coprolites"


def test_impute_samples_subcategory_from_matching_category_pool():
    random.seed(1)
    validated = validate_llm_enrichment({"llm_subcategory": UNKNOWN})
    imputed = impute_llm_fields(validated)
    pool = BODY_SUBCATEGORIES if imputed.llm_imp_category == "body" else TRACE_SUBCATEGORIES
    assert imputed.llm_imp_subcategory in pool


def test_impute_samples_subcategory_from_trace_pool_when_category_sampled_trace():
    random.seed(42)
    validated = validate_llm_enrichment({"llm_subcategory": UNKNOWN})
    imputed = impute_llm_fields(validated)
    if imputed.llm_imp_category == "trace":
        assert imputed.llm_imp_subcategory in TRACE_SUBCATEGORIES


def test_impute_forces_trace_only_for_trace_category():
    validated = validate_llm_enrichment(
        {
            "llm_subcategory": "coprolites",
            "llm_completeness": "partial",
        }
    )
    imputed = impute_llm_fields(validated)
    assert imputed.llm_imp_category == "trace"
    assert imputed.llm_imp_completeness == "trace_only"


def test_impute_samples_only_unknown_fields():
    random.seed(2)
    validated = validate_llm_enrichment(
        {
            "llm_rock_type": "limestone",
            "llm_subcategory": "teeth",
            "llm_preservation_quality": UNKNOWN,
            "llm_completeness": UNKNOWN,
        }
    )
    imputed = impute_llm_fields(validated)
    assert imputed.llm_imp_rock_type == "limestone"
    assert imputed.llm_imp_category == "body"
    assert imputed.llm_imp_subcategory == "teeth"
    assert imputed.llm_imp_preservation_quality in PRESERVATION_QUALITIES
    assert imputed.llm_imp_completeness in COMPLETENESS_VALUES
