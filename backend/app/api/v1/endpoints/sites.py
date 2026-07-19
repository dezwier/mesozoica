"""Site read endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field
from sqlmodel import Session

from app.core.database import get_session
from app.core.exceptions import ValidationError
from app.core.security import get_current_user, get_optional_current_user
from app.models.data_source import DATA_SOURCE_ARCHIVE, DATA_SOURCE_FIELD
from app.models.user import User
from app.schemas.site import (
    FieldEnsureResponse,
    SiteDinosaurThumbListResponse,
    SiteDinoFossilGroupListResponse,
    SiteFossilThumbListResponse,
    SiteListResponse,
    SiteNearbyResponse,
    SiteSummary,
)
from app.services.site_service import (
    discover_site,
    get_site_by_id,
    list_discoverable_sites_in_radius,
    list_site_dino_fossil_groups,
    list_site_dinosaurs,
    list_site_fossils,
    list_sites,
    list_sites_in_radius,
    load_site_types_by_period,
    site_row_to_summary,
)
from app.services.site_service.field_ensure_background import schedule_field_site_ensure
from app.services.site_service.field_ensure_queue import cell_key
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


def _field_visibility(
    *,
    data_source: str,
    show_all: bool,
    current_user: User | None,
) -> tuple[int | None, bool]:
    """Return (linked_user_id, show_all) for field list/nearby filtering."""
    if data_source != DATA_SOURCE_FIELD:
        return None, True
    if show_all:
        return None, True
    if current_user is None:
        return None, False
    return current_user.id, False


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
) -> SiteListResponse:
    if sort not in ("name", "random"):
        raise ValidationError("sort must be one of: name, random")
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
    )
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
    config = FieldSiteLazyConfig(radius_km=body.radius_km)
    reason = normalize_reason(body.reason)
    accepted = schedule_field_site_ensure(
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
    )
    return FieldEnsureResponse(
        accepted=accepted,
        existing_in_radius=None,
        missing=None,
        radius_km=body.radius_km,
    )


@router.post("/{site_id}/discover", response_model=SiteSummary)
def post_discover_site(
    site_id: int,
    body: DiscoverSiteRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> SiteSummary:
    row = discover_site(
        session,
        site_id=site_id,
        user_id=current_user.id,
        lat=body.lat,
        lon=body.lon,
    )
    types_by_period = load_site_types_by_period(session)
    return site_row_to_summary(row, types_by_period=types_by_period)


@router.get("/{site_id}", response_model=SiteSummary)
def get_site(
    site_id: int,
    session: Session = Depends(get_session),
    data_source: str = Query(default=DATA_SOURCE_ARCHIVE),
) -> SiteSummary:
    row = get_site_by_id(session, site_id, data_source=data_source)
    types_by_period = load_site_types_by_period(session)
    return site_row_to_summary(row, types_by_period=types_by_period)


@router.get("/{site_id}/fossils", response_model=SiteFossilThumbListResponse)
def get_site_fossils(
    site_id: int,
    session: Session = Depends(get_session),
) -> SiteFossilThumbListResponse:
    items = list_site_fossils(session, site_id)
    return SiteFossilThumbListResponse(items=items)


@router.get("/{site_id}/dinosaurs", response_model=SiteDinosaurThumbListResponse)
def get_site_dinosaurs(
    site_id: int,
    session: Session = Depends(get_session),
) -> SiteDinosaurThumbListResponse:
    items = list_site_dinosaurs(session, site_id)
    return SiteDinosaurThumbListResponse(items=items)


@router.get("/{site_id}/groups", response_model=SiteDinoFossilGroupListResponse)
def get_site_dino_fossil_groups(
    site_id: int,
    session: Session = Depends(get_session),
) -> SiteDinoFossilGroupListResponse:
    items = list_site_dino_fossil_groups(session, site_id)
    return SiteDinoFossilGroupListResponse(items=items)
