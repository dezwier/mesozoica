"""Validate LLM enrichment JSON for fossil records."""

from __future__ import annotations

import re
from typing import Any, Literal, Optional, get_args

from pydantic import BaseModel, Field, field_validator, model_validator

UNKNOWN = "unknown"

RockType = Literal[
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
    UNKNOWN,
]

Category = Literal["body", "trace", UNKNOWN]

Subcategory = Literal[
    "skull",
    "teeth",
    "vertebrae",
    "ribs_and_gastralia",
    "pectoral_girdle",
    "forelimbs",
    "pelvic_girdle",
    "hindlimbs",
    "tail_structures",
    "dermal_armour",
    "skin_and_soft_tissue",
    "eggs_and_embryos",
    "footprints_and_trackways",
    "burrows_and_nesting_traces",
    "bite_marks_and_feeding_traces",
    "coprolites",
    "gastroliths",
    "regurgitates",
    UNKNOWN,
]

PreservationQuality = Literal[
    "exceptional",
    "excellent",
    "good",
    "moderate",
    "poor",
    "very_poor",
    UNKNOWN,
]

Completeness = Literal[
    "nearly_complete",
    "substantial",
    "partial",
    "fragmentary",
    "isolated_element",
    "trace_only",
    UNKNOWN,
]

ROCK_TYPES = frozenset(get_args(RockType)) - {UNKNOWN}
CATEGORIES = frozenset(get_args(Category)) - {UNKNOWN}
SUBCATEGORIES = frozenset(get_args(Subcategory)) - {UNKNOWN}
PRESERVATION_QUALITIES = frozenset(get_args(PreservationQuality)) - {UNKNOWN}
COMPLETENESS_VALUES = frozenset(get_args(Completeness)) - {UNKNOWN}

BODY_SUBCATEGORIES = frozenset(
    {
        "skull",
        "teeth",
        "vertebrae",
        "ribs_and_gastralia",
        "pectoral_girdle",
        "forelimbs",
        "pelvic_girdle",
        "hindlimbs",
        "tail_structures",
        "dermal_armour",
        "skin_and_soft_tissue",
        "eggs_and_embryos",
    }
)

TRACE_SUBCATEGORIES = frozenset(
    {
        "footprints_and_trackways",
        "burrows_and_nesting_traces",
        "bite_marks_and_feeding_traces",
        "coprolites",
        "gastroliths",
        "regurgitates",
    }
)

_UNKNOWN_ALIASES = frozenset(
    {
        "unknown",
        "not_reported",
        "not_specified",
        "unspecified",
        "unclear",
        "not_known",
        "not_determined",
        "undetermined",
        "n_a",
        "na",
        "none",
        "null",
    }
)


def _normalize_enum(value: Any) -> str:
    if value is None:
        return UNKNOWN
    text = str(value).strip().lower()
    if not text:
        return UNKNOWN
    text = re.sub(r"[\s\-/]+", "_", text)
    text = re.sub(r"[^a-z0-9_]", "", text)
    text = re.sub(r"_+", "_", text).strip("_")
    if not text or text in _UNKNOWN_ALIASES:
        return UNKNOWN
    return text


def _coerce_to_allowed(value: str, allowed: set[str]) -> str:
    if value == UNKNOWN:
        return UNKNOWN
    if value in allowed:
        return value
    return UNKNOWN


def category_from_subcategory(subcategory: str) -> str:
    """Derive llm_category from a validated subcategory."""
    if subcategory in BODY_SUBCATEGORIES:
        return "body"
    if subcategory in TRACE_SUBCATEGORIES:
        return "trace"
    return UNKNOWN


class FossilEnrichmentOutput(BaseModel):
    llm_rock_type: str = UNKNOWN
    llm_category: str = UNKNOWN
    llm_subcategory: str = UNKNOWN
    llm_preservation_quality: str = UNKNOWN
    llm_completeness: str = UNKNOWN
    llm_description: Optional[str] = Field(default=None, max_length=512)

    @field_validator(
        "llm_rock_type",
        "llm_subcategory",
        "llm_preservation_quality",
        "llm_completeness",
        mode="before",
    )
    @classmethod
    def normalize_enum_value(cls, value: Any) -> str:
        return _normalize_enum(value)

    @field_validator("llm_description", mode="before")
    @classmethod
    def coerce_description(cls, value: Any) -> Optional[str]:
        if value is None:
            return None
        if isinstance(value, str):
            text = value.strip()
            return text or None
        return str(value).strip() or None

    @field_validator("llm_rock_type", mode="after")
    @classmethod
    def validate_rock_type(cls, value: str) -> str:
        return _coerce_to_allowed(value, ROCK_TYPES)

    @field_validator("llm_subcategory", mode="after")
    @classmethod
    def validate_subcategory(cls, value: str) -> str:
        return _coerce_to_allowed(value, SUBCATEGORIES)

    @field_validator("llm_preservation_quality", mode="after")
    @classmethod
    def validate_preservation_quality(cls, value: str) -> str:
        return _coerce_to_allowed(value, PRESERVATION_QUALITIES)

    @field_validator("llm_completeness", mode="after")
    @classmethod
    def validate_completeness(cls, value: str) -> str:
        return _coerce_to_allowed(value, COMPLETENESS_VALUES)

    @model_validator(mode="after")
    def derive_category_and_check_completeness(self) -> "FossilEnrichmentOutput":
        self.llm_category = category_from_subcategory(self.llm_subcategory)
        if self.llm_category == "trace" and self.llm_completeness not in {
            "trace_only",
            UNKNOWN,
        }:
            self.llm_completeness = UNKNOWN
        return self


def validate_llm_enrichment(raw: dict) -> FossilEnrichmentOutput:
    """Parse raw LLM JSON into a validated enrichment output."""
    return FossilEnrichmentOutput.model_validate(raw or {})
