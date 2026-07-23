"""Pydantic schemas for site API responses."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.fossil import FossilSummary


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
    odd_dino_count: float | None = None
    odd_fossil_count: float | None = None
    odd_completeness: float | None = None
    odd_quality: float | None = None
    odd_depth: float | None = None


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
