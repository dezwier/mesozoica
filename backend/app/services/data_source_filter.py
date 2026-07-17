"""Validate data_source query parameters."""

from __future__ import annotations

from app.core.exceptions import ValidationError
from app.models.data_source import DATA_SOURCE_ARCHIVE, DATA_SOURCES


def normalize_data_source(value: str | None, *, default: str = DATA_SOURCE_ARCHIVE) -> str:
    """Return a validated data_source label."""
    normalized = (value or default).strip().lower()
    if normalized not in DATA_SOURCES:
        allowed = ", ".join(sorted(DATA_SOURCES))
        raise ValidationError(f"data_source must be one of: {allowed}")
    return normalized
