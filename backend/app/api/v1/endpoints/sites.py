"""Site read endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlmodel import Session

from app.core.database import get_session
from app.core.exceptions import ValidationError
from app.schemas.site import (
    SiteDinosaurThumbListResponse,
    SiteDinoFossilGroupListResponse,
    SiteFossilThumbListResponse,
    SiteListResponse,
    SiteSummary,
)
from app.services.site_service import (
    get_site_by_id,
    list_site_dino_fossil_groups,
    list_site_dinosaurs,
    list_site_fossils,
    list_sites,
    site_row_to_summary,
)

router = APIRouter(prefix="/sites", tags=["sites"])


@router.get("", response_model=SiteListResponse)
def get_sites(
    session: Session = Depends(get_session),
    limit: int = Query(default=200, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    sort: str = Query(default="name"),
    seed: str | None = Query(default=None),
    q: str | None = Query(default=None),
    ma_younger: float | None = Query(default=None),
    ma_older: float | None = Query(default=None),
    has_custom_image: bool = Query(default=False),
) -> SiteListResponse:
    if sort not in ("name", "random"):
        raise ValidationError("sort must be one of: name, random")
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
    )
    items = [site_row_to_summary(row) for row in rows]
    return SiteListResponse(
        items=items,
        total=total,
        limit=limit,
        offset=offset,
        has_next=offset + len(items) < total,
    )


@router.get("/{site_id}", response_model=SiteSummary)
def get_site(
    site_id: int,
    session: Session = Depends(get_session),
) -> SiteSummary:
    row = get_site_by_id(session, site_id)
    return site_row_to_summary(row)


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
