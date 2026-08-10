"""Shared provenance metadata used across sources and knowledge."""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator


class SourceMetadata(BaseModel):
    """Common provenance with source-specific metadata permitted."""

    model_config = ConfigDict(extra="allow")

    source: str = Field(min_length=1)
    source_id: str = Field(min_length=1)
    source_version: str | None = None
    title: str = Field(min_length=1)
    section: str | None = None
    section_path: list[str] = Field(default_factory=list)
    section_depth: int | None = Field(default=None, ge=0)
    section_ordinal: int | None = Field(default=None, ge=0)
    source_url: str | None = None
    published_at: datetime | None = None
    updated_at: datetime | None = None
    namespace: str | None = None
    subject_id: str | None = None

    @field_validator("published_at", "updated_at")
    @classmethod
    def require_timezone(cls, value: datetime | None) -> datetime | None:
        """Require unambiguous provenance timestamps."""
        if value is not None and value.tzinfo is None:
            raise ValueError("source timestamps must include a timezone")
        return value
