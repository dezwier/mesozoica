"""Pydantic schemas for fossil API responses."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict


class FossilSummary(BaseModel):
    """Card-facing fossil fields with joined dinosaur image data."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    dinosaur_id: int
    identified_name: str | None = None
    country_code: str | None = None
    state: str | None = None
    geological_formation: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    collection_name: str | None = None
    collection_dates: str | None = None
    stratcomments: str | None = None
    lithdescript: str | None = None
    description: str | None = None
    collectors: str | None = None
    museum: str | None = None
    family: str | None = None
    pres_mode: str | None = None
    preservation_quality: str | None = None
    abund_value: int | None = None
    abund_unit: str | None = None
    min_age_ma: float | None = None
    max_age_ma: float | None = None
    early_interval: str | None = None
    main_image_url: str | None = None
    dinosaur_name: str
    dinosaur_main_image_url: str | None = None


class FossilListResponse(BaseModel):
    items: list[FossilSummary]
    total: int
    limit: int
    offset: int
    has_next: bool
