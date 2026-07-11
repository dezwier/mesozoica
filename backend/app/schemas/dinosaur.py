"""Pydantic schemas for dinosaur API responses."""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, ConfigDict


class DinosaurSummary(BaseModel):
    """Card-facing dinosaur fields (excludes heavy article HTML)."""

    model_config = ConfigDict(from_attributes=True)

    id: int
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


class DinosaurListResponse(BaseModel):
    items: list[DinosaurSummary]
    total: int
    limit: int
    offset: int
