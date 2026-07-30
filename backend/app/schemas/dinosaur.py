"""Pydantic schemas for dinosaur API responses."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class DinosaurSummary(BaseModel):
    """Card-facing dinosaur fields (excludes heavy article HTML)."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    dinosaur_type_id: int | None = None
    name: str
    wikipedia_title: str
    birth: float | None = None
    death: float | None = None
    period: str | None = None
    diet_type: str | None = None
    length: str | None = None
    mass: str | None = None
    location: str | None = None
    short_description: str | None = None
    cladogram: dict[str, Any] = {}
    main_image_url: str | None = None
    # Inventory occurrence reconstruction time; null for catalog rows.
    created_at: datetime | None = None
    # Curated image version folder; set for inventory occurrences.
    version: str | None = None
    # Viewer collection status (catalog: latest role for type; inventory: occurrence).
    status: str | None = None


class CollectDinosaurRequest(BaseModel):
    """Admin collect body: collection role status + curated image version."""

    status: str = Field(min_length=1, max_length=32)
    version: str = Field(
        ...,
        min_length=1,
        max_length=64,
        description="Curated image version folder (e.g. Original, Summer 26)",
    )


class DinosaurImageVersionItem(BaseModel):
    name: str
    run_date: str | None = None


class DinosaurImageVersionListResponse(BaseModel):
    items: list[DinosaurImageVersionItem]


class DinosaurListResponse(BaseModel):
    items: list[DinosaurSummary]
    total: int
    limit: int
    offset: int
    has_next: bool


class DinosaurArticleResponse(BaseModel):
    """Reader-mode Wikipedia article for a single dinosaur."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    wikipedia_title: str
    article: str | None = None
    article_date: datetime | None = None
