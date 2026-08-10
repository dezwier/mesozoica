"""Shared provenance metadata used across sources and knowledge."""

from __future__ import annotations

from datetime import datetime, timezone

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
    def coerce_timezone(cls, value: datetime | None) -> datetime | None:
        """Assume UTC when SQL/JSON round-trips drop tzinfo (date-only OpenAlex)."""
        if value is None:
            return None
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value
