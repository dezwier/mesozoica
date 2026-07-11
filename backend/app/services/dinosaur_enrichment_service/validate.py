"""Validate and normalize LLM enrichment output."""

from __future__ import annotations

import re
from typing import Optional

from pydantic import BaseModel, Field, field_validator

KNOWN_DIET_TYPES = frozenset(
    {"herbivore", "carnivore", "omnivore", "piscivore", "insectivore", "filter-feeder", "unknown"}
)

_PLACEHOLDER_VALUES = frozenset(
    {"", "n/a", "na", "none", "null", "unknown", "?", "not available", "not known", "unclear"}
)


def _clean_optional(value: Optional[str], *, max_len: int) -> Optional[str]:
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    if text.lower() in _PLACEHOLDER_VALUES:
        return None
    if len(text) > max_len:
        text = text[:max_len].rstrip()
    return text


def _normalize_diet(value: Optional[str]) -> Optional[str]:
    if value is None:
        return None
    text = str(value).strip().lower()
    if not text or text in _PLACEHOLDER_VALUES:
        return None
    if text in KNOWN_DIET_TYPES:
        return text
    return text[:64]


def _coerce_optional_str(value: object) -> Optional[str]:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return str(value)
    text = str(value).strip()
    if not text:
        return None
    return text


def _sentence_terminator_positions(text: str) -> list[int]:
    """Positions of real sentence-ending punctuation (ignore decimal points)."""
    positions: list[int] = []
    for match in re.finditer(r"[.!?]", text):
        pos = match.start()
        char = text[pos]
        if char == "." and pos > 0 and pos + 1 < len(text):
            if text[pos - 1].isdigit() and text[pos + 1].isdigit():
                continue
        positions.append(pos)
    return positions


class DinosaurEnrichmentOutput(BaseModel):
    length: Optional[str] = Field(default=None, max_length=128)
    mass: Optional[str] = Field(default=None, max_length=128)
    location: Optional[str] = Field(default=None, max_length=512)
    diet_type: Optional[str] = Field(default=None, max_length=64)
    short_description: str = Field(min_length=30, max_length=280)

    @field_validator("length", "mass", "location", mode="before")
    @classmethod
    def nullish_to_none(cls, value: object) -> Optional[str]:
        text = _coerce_optional_str(value)
        if text is None:
            return None
        if text.lower() in _PLACEHOLDER_VALUES:
            return None
        return text

    @field_validator("short_description")
    @classmethod
    def single_sentence(cls, value: str) -> str:
        text = value.strip()
        if "\n" in text:
            raise ValueError("short_description must be a single line")
        terminators = _sentence_terminator_positions(text)
        if len(terminators) > 1:
            raise ValueError("short_description must be a single sentence")
        if terminators and terminators[0] != len(text) - 1:
            raise ValueError("short_description must end with sentence punctuation")
        return text


def validate_llm_enrichment(raw: dict) -> DinosaurEnrichmentOutput:
    """Parse and normalize raw LLM JSON into a validated enrichment output."""
    model = DinosaurEnrichmentOutput.model_validate(raw)
    return DinosaurEnrichmentOutput(
        length=_clean_optional(model.length, max_len=128),
        mass=_clean_optional(model.mass, max_len=128),
        location=_clean_optional(model.location, max_len=512),
        diet_type=_normalize_diet(model.diet_type),
        short_description=model.short_description,
    )
