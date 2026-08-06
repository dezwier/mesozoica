"""Shared provenance identifiers and query validation."""

from __future__ import annotations

from app.core.exceptions import ValidationError

DATA_SOURCE_ARCHIVE = "archive"
DATA_SOURCE_FIELD = "field"
DATA_SOURCES: frozenset[str] = frozenset({DATA_SOURCE_ARCHIVE, DATA_SOURCE_FIELD})


def normalize_data_source(value: str | None, *, default: str = DATA_SOURCE_ARCHIVE) -> str:
    """Return a validated data_source label."""
    normalized = (value or default).strip().lower()
    if normalized not in DATA_SOURCES:
        allowed = ", ".join(sorted(DATA_SOURCES))
        raise ValidationError(f"data_source must be one of: {allowed}")
    return normalized
