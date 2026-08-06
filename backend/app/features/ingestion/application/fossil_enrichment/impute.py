"""Impute missing LLM enrichment enum fields for downstream use."""

from __future__ import annotations

import random

from pydantic import BaseModel

from app.features.ingestion.application.fossil_enrichment.validate import (
    BODY_SUBCATEGORIES,
    CATEGORIES,
    COMPLETENESS_VALUES,
    PRESERVATION_QUALITIES,
    ROCK_TYPES,
    TRACE_SUBCATEGORIES,
    UNKNOWN,
    FossilEnrichmentOutput,
)


def _pick_random(allowed: set[str]) -> str:
    return random.choice(sorted(allowed))


def _is_unknown(value: str) -> bool:
    return value == UNKNOWN


def _subcategory_pool(category: str) -> frozenset[str]:
    if category == "body":
        return BODY_SUBCATEGORIES
    return TRACE_SUBCATEGORIES


class FossilEnrichmentImputed(BaseModel):
    llm_imp_rock_type: str
    llm_imp_category: str
    llm_imp_subcategory: str
    llm_imp_preservation_quality: str
    llm_imp_completeness: str


def impute_llm_fields(validated: FossilEnrichmentOutput) -> FossilEnrichmentImputed:
    """Derive always-filled imputed fields from validated LLM output."""
    if not _is_unknown(validated.llm_category):
        imp_category = validated.llm_category
    else:
        imp_category = _pick_random(CATEGORIES)

    pool = _subcategory_pool(imp_category)
    if not _is_unknown(validated.llm_subcategory):
        imp_subcategory = validated.llm_subcategory
    else:
        imp_subcategory = _pick_random(pool)

    imp_rock_type = (
        validated.llm_rock_type
        if not _is_unknown(validated.llm_rock_type)
        else _pick_random(ROCK_TYPES)
    )
    imp_preservation_quality = (
        validated.llm_preservation_quality
        if not _is_unknown(validated.llm_preservation_quality)
        else _pick_random(PRESERVATION_QUALITIES)
    )
    imp_completeness = (
        validated.llm_completeness
        if not _is_unknown(validated.llm_completeness)
        else _pick_random(COMPLETENESS_VALUES)
    )

    if imp_category == "trace":
        imp_completeness = "trace_only"

    return FossilEnrichmentImputed(
        llm_imp_rock_type=imp_rock_type,
        llm_imp_category=imp_category,
        llm_imp_subcategory=imp_subcategory,
        llm_imp_preservation_quality=imp_preservation_quality,
        llm_imp_completeness=imp_completeness,
    )
