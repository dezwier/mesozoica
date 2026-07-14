"""Validate LLM enrichment JSON for fossil records."""

from __future__ import annotations

import re
from typing import Any, Literal, get_args

from pydantic import BaseModel, field_validator, model_validator

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
    "unknown",
]

Category = Literal["body_fossil", "trace_fossil", "unknown"]

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
    "unknown",
]

PreservationQuality = Literal[
    "exceptional",
    "excellent",
    "good",
    "moderate",
    "poor",
    "very_poor",
    "unknown",
]

Completeness = Literal[
    "nearly_complete",
    "substantial",
    "partial",
    "fragmentary",
    "isolated_element",
    "trace_only",
    "unknown",
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


def _normalize_enum(value: Any) -> str:
    if value is None:
        return "unknown"
    text = str(value).strip().lower()
    if not text:
        return "unknown"
    text = re.sub(r"[\s\-/]+", "_", text)
    text = re.sub(r"[^a-z0-9_]", "", text)
    text = re.sub(r"_+", "_", text).strip("_")
    return text or "unknown"


class FossilEnrichmentOutput(BaseModel):
    llm_rock_type: str = "unknown"
    llm_category: str = "unknown"
    llm_subcategory: str = "unknown"
    llm_preservation_quality: str = "unknown"
    llm_completeness: str = "unknown"

    @field_validator(
        "llm_rock_type",
        "llm_category",
        "llm_subcategory",
        "llm_preservation_quality",
        "llm_completeness",
        mode="before",
    )
    @classmethod
    def normalize_value(cls, value: Any) -> str:
        return _normalize_enum(value)

    @field_validator("llm_rock_type", mode="after")
    @classmethod
    def validate_rock_type(cls, value: str) -> str:
        allowed = set(get_args(RockType))
        if value not in allowed:
            raise ValueError(f"invalid llm_rock_type: {value}")
        return value

    @field_validator("llm_category", mode="after")
    @classmethod
    def validate_category(cls, value: str) -> str:
        allowed = set(get_args(Category))
        if value not in allowed:
            raise ValueError(f"invalid llm_category: {value}")
        return value

    @field_validator("llm_subcategory", mode="after")
    @classmethod
    def validate_subcategory(cls, value: str) -> str:
        allowed = set(get_args(Subcategory))
        if value not in allowed:
            raise ValueError(f"invalid llm_subcategory: {value}")
        return value

    @field_validator("llm_preservation_quality", mode="after")
    @classmethod
    def validate_preservation_quality(cls, value: str) -> str:
        allowed = set(get_args(PreservationQuality))
        if value not in allowed:
            raise ValueError(f"invalid llm_preservation_quality: {value}")
        return value

    @field_validator("llm_completeness", mode="after")
    @classmethod
    def validate_completeness(cls, value: str) -> str:
        allowed = set(get_args(Completeness))
        if value not in allowed:
            raise ValueError(f"invalid llm_completeness: {value}")
        return value

    @model_validator(mode="after")
    def check_category_consistency(self) -> "FossilEnrichmentOutput":
        if self.llm_category == "body_fossil" and self.llm_subcategory in _TRACE_SUBCATEGORIES:
            raise ValueError("body_fossil cannot have trace subcategory")
        if self.llm_category == "trace_fossil" and self.llm_subcategory in _BODY_SUBCATEGORIES:
            raise ValueError("trace_fossil cannot have body subcategory")
        if self.llm_category == "trace_fossil" and self.llm_completeness not in {
            "trace_only",
            "unknown",
        }:
            raise ValueError("trace_fossil completeness must be trace_only or unknown")
        return self


def validate_llm_enrichment(raw: dict) -> FossilEnrichmentOutput:
    """Parse raw LLM JSON into a validated enrichment output."""
    return FossilEnrichmentOutput.model_validate(raw or {})
