"""Pydantic schemas for site API responses."""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.fossil import FossilSummary


class OwnedOccurrenceThumb(BaseModel):
    """Viewer-owned site occurrence thumbnail for catalog album tiles."""

    id: int
    version: str | None = None
    main_image_url: str | None = None
    created_at: datetime | None = None


class SiteTypeSummary(BaseModel):
    """Catalog album row for a geological site type (period + rock)."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    period: str
    rock_type: str
    main_image_url: str | None = None
    owned_occurrences: list[OwnedOccurrenceThumb] = Field(default_factory=list)


class SiteTypeListResponse(BaseModel):
    items: list[SiteTypeSummary]
    total: int
    limit: int
    offset: int
    has_next: bool


class SiteSummary(BaseModel):
    """Card-facing site fields with joined site_type image data."""

    model_config = ConfigDict(from_attributes=True)

    site_id: int
    latitude: float | None = None
    longitude: float | None = None
    country_code: str | None = None
    state: str | None = None
    rock_type: str | None = None
    formation: str | None = None
    min_age_ma: float | None = None
    max_age_ma: float | None = None
    site_type_id: int | None = None
    site_type_period: str | None = None
    site_type_rock_type: str | None = None
    main_image_url: str | None = None
    data_source: str = "archive"
    how_discovered: str | None = None
    status: str | None = None
    viewer_has_surveyed: bool | None = None
    # Viewer's discoverer UserSite (when authenticated and linked).
    discovered_at: datetime | None = None
    discovering_session_id: int | None = None
    odd_dino_count: float | None = None
    odd_fossil_count: float | None = None
    odd_completeness: float | None = None
    odd_quality: float | None = None
    odd_depth: float | None = None
    version: str = "Original"


class SiteListResponse(BaseModel):
    items: list[SiteSummary]
    total: int
    limit: int
    offset: int
    has_next: bool


class SiteNearbyResponse(BaseModel):
    items: list[SiteSummary]
    total: int
    generated: int
    radius_km: float


class FieldEnsureResponse(BaseModel):
    accepted: bool
    job_id: int | None = None
    status: str | None = None
    existing_in_radius: int | None = None
    missing: int | None = None
    generated: int | None = None
    total_in_radius: int | None = None
    radius_km: float
    error_message: str | None = None


class FieldEnsureJobResponse(BaseModel):
    job_id: int
    status: str
    accepted: bool = True
    generated: int | None = None
    total_in_radius: int | None = None
    radius_km: float
    error_message: str | None = None


class FieldSurveyResponse(BaseModel):
    site: SiteSummary
    job_id: int | None = None
    status: str = "done"
    onboarded: bool = False
    generated: bool = False
    fossils_ready: bool = True


class FieldSurveyJobResponse(BaseModel):
    job_id: int
    site_id: int
    status: str
    fossil_count: int | None = None
    error_message: str | None = None


class FieldDataPurgeResponse(BaseModel):
    user_sites_deleted: int = 0
    user_fossils_deleted: int = 0
    sites_deleted: int
    fossils_deleted: int
    survey_jobs_deleted: int
    ensure_jobs_deleted: int
    session_events_deleted: int = 0
    sessions_deleted: int = 0


class FieldDiscoverResponse(BaseModel):
    """Site discovery plus global fossil generation onboard metadata."""

    site: SiteSummary
    job_id: int | None = None
    status: str = "done"
    onboarded: bool = False
    generated: bool = False
    fossils_ready: bool = False
    surface_fossils: list[FossilSummary] = Field(default_factory=list)


class SiteFossilThumb(BaseModel):
    id: int
    main_image_url: str | None = None
    identified_name: str | None = None
    status: str = "hidden"


class SiteDinosaurThumb(BaseModel):
    id: int
    name: str
    main_image_url: str | None = None


class SiteFossilThumbListResponse(BaseModel):
    items: list[SiteFossilThumb]


class SiteDinosaurThumbListResponse(BaseModel):
    items: list[SiteDinosaurThumb]


class SiteDinoFossilGroup(BaseModel):
    dinosaur: SiteDinosaurThumb
    fossils: list[SiteFossilThumb]


class SiteDinoFossilGroupListResponse(BaseModel):
    items: list[SiteDinoFossilGroup]


class FieldEnsureRequest(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    radius_km: float = Field(default=1.0, gt=0, le=50)
    reason: str | None = Field(default=None, max_length=32)


class DiscoverSiteRequest(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)


class SetSiteStatusRequest(BaseModel):
    status: str = Field(min_length=1, max_length=32)
    lat: float | None = Field(default=None, ge=-90, le=90)
    lon: float | None = Field(default=None, ge=-180, le=180)
