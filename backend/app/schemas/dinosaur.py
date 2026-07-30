"""Pydantic schemas for dinosaur API responses."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict


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
