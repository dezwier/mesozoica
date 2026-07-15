"""Validate LLM enrichment JSON for fossil records."""

from __future__ import annotations

import random
import re
from typing import Any, Literal, Optional, get_args

from pydantic import BaseModel, Field, field_validator, model_validator

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
]

Category = Literal["body_fossil", "trace_fossil"]

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
]

PreservationQuality = Literal[
    "exceptional",
    "excellent",
    "good",
    "moderate",
    "poor",
    "very_poor",
]

Completeness = Literal[
    "nearly_complete",
    "substantial",
    "partial",
    "fragmentary",
    "isolated_element",
    "trace_only",
]

_BODY_SUBCATEGORIES = frozenset(
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

_TRACE_SUBCATEGORIES = frozenset(
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


def _pick_random(allowed: set[str]) -> str:
    return random.choice(sorted(allowed))


def _normalize_enum(value: Any) -> str:
    if value is None:
        return ""
    text = str(value).strip().lower()
    if not text:
        return ""
    text = re.sub(r"[\s\-/]+", "_", text)
    text = re.sub(r"[^a-z0-9_]", "", text)
    text = re.sub(r"_+", "_", text).strip("_")
    if not text or text in _UNKNOWN_ALIASES:
        return ""
    return text


def _coerce_to_allowed(value: str, allowed: set[str]) -> str:
    if value in allowed:
        return value
    return _pick_random(allowed)


class FossilEnrichmentOutput(BaseModel):
    llm_rock_type: str = ""
    llm_category: str = ""
    llm_subcategory: str = ""
    llm_preservation_quality: str = ""
    llm_completeness: str = ""
    llm_description: Optional[str] = Field(default=None, max_length=512)

    @field_validator(
        "llm_rock_type",
        "llm_category",
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
        return _coerce_to_allowed(value, set(get_args(RockType)))

    @field_validator("llm_category", mode="after")
    @classmethod
    def validate_category(cls, value: str) -> str:
        return _coerce_to_allowed(value, set(get_args(Category)))

    @field_validator("llm_subcategory", mode="after")
    @classmethod
    def validate_subcategory(cls, value: str) -> str:
        return _coerce_to_allowed(value, set(get_args(Subcategory)))

    @field_validator("llm_preservation_quality", mode="after")
    @classmethod
    def validate_preservation_quality(cls, value: str) -> str:
        return _coerce_to_allowed(value, set(get_args(PreservationQuality)))

    @field_validator("llm_completeness", mode="after")
    @classmethod
    def validate_completeness(cls, value: str) -> str:
        return _coerce_to_allowed(value, set(get_args(Completeness)))

    @model_validator(mode="after")
    def check_category_consistency(self) -> "FossilEnrichmentOutput":
        if self.llm_category == "body_fossil" and self.llm_subcategory in _TRACE_SUBCATEGORIES:
            self.llm_subcategory = _pick_random(_BODY_SUBCATEGORIES)
        if self.llm_category == "trace_fossil" and self.llm_subcategory in _BODY_SUBCATEGORIES:
            self.llm_subcategory = _pick_random(_TRACE_SUBCATEGORIES)
        if self.llm_category == "trace_fossil" and self.llm_completeness != "trace_only":
            self.llm_completeness = "trace_only"
        return self


def validate_llm_enrichment(raw: dict) -> FossilEnrichmentOutput:
    """Parse raw LLM JSON into a validated enrichment output."""
    return FossilEnrichmentOutput.model_validate(raw or {})
