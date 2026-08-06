"""Validate LLM enrichment JSON against DB field constraints."""

from __future__ import annotations

from typing import Any, Optional

from pydantic import BaseModel, Field, field_validator


class DinosaurEnrichmentOutput(BaseModel):
    length: Optional[str] = Field(default=None, max_length=128)
    mass: Optional[str] = Field(default=None, max_length=128)
    location: Optional[str] = Field(default=None, max_length=512)
    diet_type: Optional[str] = Field(default=None, max_length=64)
    short_description: Optional[str] = Field(default=None)

    @field_validator("length", "mass", "location", "diet_type", "short_description", mode="before")
    @classmethod
    def coerce_to_optional_str(cls, value: Any) -> Optional[str]:
        if value is None:
            return None
        if isinstance(value, str):
            text = value.strip()
            return text or None
        return str(value).strip() or None


def validate_llm_enrichment(raw: dict) -> DinosaurEnrichmentOutput:
    """Parse raw LLM JSON into a validated enrichment output."""
    return DinosaurEnrichmentOutput.model_validate(raw)
