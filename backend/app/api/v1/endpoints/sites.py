"""Site read endpoints."""

from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field
from sqlmodel import Session

from app.core.database import get_session
from app.core.exceptions import NotFoundError, ValidationError
from app.core.security import (
    get_current_admin_user,
    get_current_user,
    get_optional_current_user,
)
from app.models.data_source import DATA_SOURCE_ARCHIVE, DATA_SOURCE_FIELD
from app.models.user import User
from app.schemas.site import (
    FieldDataPurgeResponse,
    FieldDiscoverResponse,
    FieldEnsureJobResponse,
    FieldEnsureResponse,
    FieldSurveyJobResponse,
    FieldSurveyResponse,
    SiteDinosaurThumbListResponse,
    SiteDinoFossilGroupListResponse,
    SiteFossilThumbListResponse,
    SiteListResponse,
    SiteNearbyResponse,
    SiteSummary,
)
from app.services.site_service import (
    discover_site,
    enrich_site_rows_for_viewer,
    get_site_by_id,
    get_survey_job,
    list_discoverable_sites_in_radius,
    list_site_dino_fossil_groups,
    list_site_dinosaurs,
    list_site_fossils,
    list_sites,
    list_sites_in_radius,
    load_site_types_by_period,
    set_site_status,
    site_row_to_summary,
    survey_site,
)
from app.services.site_service.summary import SiteRow
from app.services.site_service.field_fossil_onboard import (
    DiscoverFossilOnboardResult,
    surface_fossil_summaries,
)
from app.services.site_service.field_data_purge import purge_all_field_data
from app.services.site_service.field_ensure_background import schedule_field_site_ensure
from app.services.site_service.field_ensure_queue import (
    cell_key,
    get_field_ensure_job,
)
from app.services.site_service.field_generate import FieldSiteLazyConfig
from app.services.site_service.field_site_logging import log_field_event, normalize_reason

router = APIRouter(prefix="/sites", tags=["sites"])


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


def _field_visibility(
    *,
    data_source: str,
    show_all: bool,
    current_user: User | None,
) -> tuple[int | None, bool]:
    """Return (linked_user_id, show_all) for field list/nearby filtering.

    ``show_all`` is honored only for authenticated admins; everyone else gets
    linked-only field visibility.
    """
    if data_source != DATA_SOURCE_FIELD:
        return None, True
    if show_all and current_user is not None and current_user.is_admin:
        return None, True
    if current_user is None:
        return None, False
    return current_user.id, False


def _maybe_enrich_viewer(
    session: Session,
    rows: list[SiteRow],
    current_user: User | None,
) -> list[SiteRow]:
    if current_user is None or not rows:
        return rows
    return enrich_site_rows_for_viewer(
        session, rows, viewer_user_id=int(current_user.id)
    )


@router.get("", response_model=SiteListResponse)
def get_sites(
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_optional_current_user),
    limit: int = Query(default=200, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    sort: str = Query(default="name"),
    seed: str | None = Query(default=None),
    q: str | None = Query(default=None),
    ma_younger: float | None = Query(default=None),
    ma_older: float | None = Query(default=None),
    has_custom_image: bool = Query(default=False),
    data_source: str = Query(default=DATA_SOURCE_ARCHIVE),
    site_id_min: int | None = Query(default=None, ge=0),
    show_all: bool = Query(default=False),
    how_discovered: list[str] | None = Query(default=None),
    discovered_after: datetime | None = Query(default=None),
    discovered_before: datetime | None = Query(default=None),
    lat: float | None = Query(default=None, ge=-90, le=90),
    lon: float | None = Query(default=None, ge=-180, le=180),
    min_lat: float | None = Query(default=None, ge=-90, le=90),
    max_lat: float | None = Query(default=None, ge=-90, le=90),
    min_lon: float | None = Query(default=None, ge=-180, le=180),
    max_lon: float | None = Query(default=None, ge=-180, le=180),
) -> SiteListResponse:
    allowed_sorts = (
        "name",
        "random",
        "distance",
        "discovered_at",
        "discovered_at_desc",
    )
    if sort not in allowed_sorts:
        raise ValidationError(f"sort must be one of: {', '.join(allowed_sorts)}")
    linked_user_id, effective_show_all = _field_visibility(
        data_source=data_source,
        show_all=show_all,
        current_user=current_user,
    )
    rows, total = list_sites(
        session,
        limit=limit,
        offset=offset,
        sort=sort,  # type: ignore[arg-type]
        seed=seed,
        q=q,
        ma_younger=ma_younger,
        ma_older=ma_older,
        has_custom_image=has_custom_image,
        data_source=data_source,
        site_id_min=site_id_min,
        linked_user_id=linked_user_id,
        show_all=effective_show_all,
        how_discovered=how_discovered,
        discovered_after=discovered_after,
        discovered_before=discovered_before,
        lat=lat,
        lon=lon,
        min_lat=min_lat,
        max_lat=max_lat,
        min_lon=min_lon,
        max_lon=max_lon,
        viewer_user_id=int(current_user.id) if current_user is not None else None,
    )
    rows = _maybe_enrich_viewer(session, rows, current_user)
    types_by_period = load_site_types_by_period(session)
    items = [site_row_to_summary(row, types_by_period=types_by_period) for row in rows]
    return SiteListResponse(
        items=items,
        total=total,
        limit=limit,
        offset=offset,
        has_next=offset + len(items) < total if site_id_min is None else len(items) == limit,
    )


@router.get("/nearby", response_model=SiteNearbyResponse)
def get_sites_nearby(
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_optional_current_user),
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    radius_km: float = Query(default=1.0, gt=0, le=50),
    data_source: str = Query(default=DATA_SOURCE_FIELD),
    show_all: bool = Query(default=False),
) -> SiteNearbyResponse:
    linked_user_id, effective_show_all = _field_visibility(
        data_source=data_source,
        show_all=show_all,
        current_user=current_user,
    )
    rows = list_sites_in_radius(
        session,
        lat=lat,
        lon=lon,
        radius_km=radius_km,
        data_source=data_source,
        linked_user_id=linked_user_id,
        show_all=effective_show_all,
    )
    rows = _maybe_enrich_viewer(session, rows, current_user)
    types_by_period = load_site_types_by_period(session)
    items = [site_row_to_summary(row, types_by_period=types_by_period) for row in rows]
    return SiteNearbyResponse(
        items=items,
        total=len(items),
        generated=0,
        radius_km=radius_km,
    )


@router.get("/nearby-discoverable", response_model=SiteNearbyResponse)
def get_sites_nearby_discoverable(
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    radius_km: float = Query(default=1.0, gt=0, le=50),
) -> SiteNearbyResponse:
    """Field sites near the user that they can still discover (not yet linked)."""
    rows = list_discoverable_sites_in_radius(
        session,
        lat=lat,
        lon=lon,
        radius_km=radius_km,
        user_id=current_user.id,
    )
    rows = _maybe_enrich_viewer(session, rows, current_user)
    types_by_period = load_site_types_by_period(session)
    items = [site_row_to_summary(row, types_by_period=types_by_period) for row in rows]
    return SiteNearbyResponse(
        items=items,
        total=len(items),
        generated=0,
        radius_km=radius_km,
    )


@router.post("/field/ensure", response_model=FieldEnsureResponse, status_code=202)
def post_field_site_ensure(body: FieldEnsureRequest) -> FieldEnsureResponse:
    config = FieldSiteLazyConfig.from_game_config(radius_km=body.radius_km)
    reason = normalize_reason(body.reason)
    accepted, job_id = schedule_field_site_ensure(
        lat=body.lat,
        lon=body.lon,
        config=config,
        reason=body.reason,
    )
    log_field_event(
        "ensure_enqueued" if accepted else "ensure_deduped",
        service="api",
        reason=reason,
        lat=body.lat,
        lon=body.lon,
        radius_km=body.radius_km,
        cell=cell_key(body.lat, body.lon, body.radius_km),
        enqueued=accepted,
        job_id=job_id,
    )
    return FieldEnsureResponse(
        accepted=accepted,
        job_id=job_id,
        status="pending" if accepted else "pending_or_running",
        existing_in_radius=None,
        missing=None,
        generated=None,
        total_in_radius=None,
        radius_km=body.radius_km,
    )


@router.get("/field/ensure/jobs/{job_id}", response_model=FieldEnsureJobResponse)
def get_field_ensure_job_status(
    job_id: int,
    session: Session = Depends(get_session),
) -> FieldEnsureJobResponse:
    job = get_field_ensure_job(session, job_id)
    if job is None or job.id is None:
        raise NotFoundError(f"Field ensure job {job_id} not found")
    return FieldEnsureJobResponse(
        job_id=job.id,
        status=job.status,
        generated=job.generated_count,
        total_in_radius=job.total_in_radius,
        radius_km=job.radius_km,
        error_message=job.error_message,
    )


@router.delete("/field", response_model=FieldDataPurgeResponse)
def delete_all_field_data(
    session: Session = Depends(get_session),
    _admin: User = Depends(get_current_admin_user),
    user_sites: bool = Query(
        default=True,
        description="Delete user_site rows for field sites",
    ),
    user_fossils: bool = Query(
        default=True,
        description="Delete user_fossil rows for field fossils",
    ),
    sites: bool = Query(
        default=True,
        description="Delete field sites (and related survey/ensure jobs)",
    ),
    fossils: bool = Query(
        default=True,
        description="Delete field fossils",
    ),
    mission_events: bool = Query(
        default=True,
        description="Delete tool_mission_event rows",
    ),
    missions: bool = Query(
        default=True,
        description="Delete tool_mission rows (and remaining events)",
    ),
) -> FieldDataPurgeResponse:
    """Admin-only: selectively wipe field progress, sites, and/or fossils."""
    if not any(
        (user_sites, user_fossils, sites, fossils, mission_events, missions)
    ):
        raise ValidationError("Select at least one purge scope")
    result = purge_all_field_data(
        session,
        user_sites=user_sites,
        user_fossils=user_fossils,
        sites=sites,
        fossils=fossils,
        mission_events=mission_events,
        missions=missions,
    )
    log_field_event(
        "field_data_purged",
        service="api",
        user_sites_deleted=result.user_sites_deleted,
        user_fossils_deleted=result.user_fossils_deleted,
        sites_deleted=result.sites_deleted,
        fossils_deleted=result.fossils_deleted,
        survey_jobs_deleted=result.survey_jobs_deleted,
        ensure_jobs_deleted=result.ensure_jobs_deleted,
        mission_events_deleted=result.mission_events_deleted,
        missions_deleted=result.missions_deleted,
    )
    return FieldDataPurgeResponse(
        user_sites_deleted=result.user_sites_deleted,
        user_fossils_deleted=result.user_fossils_deleted,
        sites_deleted=result.sites_deleted,
        fossils_deleted=result.fossils_deleted,
        survey_jobs_deleted=result.survey_jobs_deleted,
        ensure_jobs_deleted=result.ensure_jobs_deleted,
        mission_events_deleted=result.mission_events_deleted,
        missions_deleted=result.missions_deleted,
    )


@router.get("/survey/jobs/{job_id}", response_model=FieldSurveyJobResponse)
def get_field_survey_job_status(
    job_id: int,
    session: Session = Depends(get_session),
    _current_user: User = Depends(get_current_user),
) -> FieldSurveyJobResponse:
    job = get_survey_job(session, job_id)
    if job is None or job.id is None:
        raise NotFoundError(f"Field survey job {job_id} not found")
    return FieldSurveyJobResponse(
        job_id=job.id,
        site_id=job.site_id,
        status=job.status,
        fossil_count=job.fossil_count,
        error_message=job.error_message,
    )


@router.post("/{site_id}/survey", response_model=FieldSurveyResponse)
def post_survey_site(
    site_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> FieldSurveyResponse:
    result = survey_site(
        session,
        site_id=site_id,
        user_id=current_user.id,
    )
    types_by_period = load_site_types_by_period(session)
    enriched = enrich_site_rows_for_viewer(
        session, [result.site], viewer_user_id=int(current_user.id)
    )[0]
    return FieldSurveyResponse(
        site=site_row_to_summary(enriched, types_by_period=types_by_period),
        job_id=None,
        status="done",
        onboarded=True,
        generated=False,
        fossils_ready=True,
    )


def _discover_response(
    session: Session,
    result: DiscoverFossilOnboardResult,
    *,
    viewer_user_id: int,
) -> FieldDiscoverResponse:
    types_by_period = load_site_types_by_period(session)
    enriched = enrich_site_rows_for_viewer(
        session, [result.site], viewer_user_id=viewer_user_id
    )[0]
    return FieldDiscoverResponse(
        site=site_row_to_summary(enriched, types_by_period=types_by_period),
        job_id=result.job_id,
        status=result.job_status,
        onboarded=result.onboarded,
        generated=result.generated,
        fossils_ready=result.fossils_ready,
        surface_fossils=surface_fossil_summaries(
            session,
            fossil_ids=result.surface_fossil_ids,
            viewer_user_id=viewer_user_id,
        ),
    )


@router.post("/{site_id}/discover", response_model=FieldDiscoverResponse)
def post_discover_site(
    site_id: int,
    body: DiscoverSiteRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> FieldDiscoverResponse:
    result = discover_site(
        session,
        site_id=site_id,
        user_id=current_user.id,
        lat=body.lat,
        lon=body.lon,
    )
    return _discover_response(
        session, result, viewer_user_id=current_user.id
    )


@router.post("/{site_id}/status", response_model=SiteSummary | FieldDiscoverResponse)
def post_set_site_status(
    site_id: int,
    body: SetSiteStatusRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> SiteSummary | FieldDiscoverResponse:
    row = set_site_status(
        session,
        site_id=site_id,
        user_id=current_user.id,
        status=body.status,
        lat=body.lat,
        lon=body.lon,
        skip_distance_check=bool(current_user.is_admin),
    )
    if isinstance(row, DiscoverFossilOnboardResult):
        return _discover_response(
            session, row, viewer_user_id=current_user.id
        )
    types_by_period = load_site_types_by_period(session)
    enriched = enrich_site_rows_for_viewer(
        session, [row], viewer_user_id=int(current_user.id)
    )[0]
    return site_row_to_summary(enriched, types_by_period=types_by_period)


@router.get("/{site_id}", response_model=SiteSummary)
def get_site(
    site_id: int,
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_optional_current_user),
    data_source: str = Query(default=DATA_SOURCE_ARCHIVE),
) -> SiteSummary:
    row = get_site_by_id(
        session,
        site_id,
        data_source=data_source,
        viewer_user_id=current_user.id if current_user is not None else None,
    )
    types_by_period = load_site_types_by_period(session)
    return site_row_to_summary(row, types_by_period=types_by_period)


@router.get("/{site_id}/fossils", response_model=SiteFossilThumbListResponse)
def get_site_fossils(
    site_id: int,
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_optional_current_user),
) -> SiteFossilThumbListResponse:
    items = list_site_fossils(
        session,
        site_id,
        viewer_user_id=current_user.id if current_user is not None else None,
        is_admin=bool(current_user is not None and current_user.is_admin),
    )
    return SiteFossilThumbListResponse(items=items)


@router.get("/{site_id}/dinosaurs", response_model=SiteDinosaurThumbListResponse)
def get_site_dinosaurs(
    site_id: int,
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_optional_current_user),
) -> SiteDinosaurThumbListResponse:
    items = list_site_dinosaurs(
        session,
        site_id,
        viewer_user_id=current_user.id if current_user is not None else None,
        is_admin=bool(current_user is not None and current_user.is_admin),
    )
    return SiteDinosaurThumbListResponse(items=items)


@router.get("/{site_id}/groups", response_model=SiteDinoFossilGroupListResponse)
def get_site_dino_fossil_groups(
    site_id: int,
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_optional_current_user),
) -> SiteDinoFossilGroupListResponse:
    items = list_site_dino_fossil_groups(
        session,
        site_id,
        viewer_user_id=current_user.id if current_user is not None else None,
        is_admin=bool(current_user is not None and current_user.is_admin),
    )
    return SiteDinoFossilGroupListResponse(items=items)
