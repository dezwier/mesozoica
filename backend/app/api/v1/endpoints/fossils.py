"""Fossil read endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlmodel import Session

from app.core.database import get_session
from app.core.exceptions import ValidationError
from app.schemas.fossil import FossilListResponse, FossilSummary
from app.services.fossil_service.list import fossil_row_to_summary, get_fossil_by_id, list_fossils
from app.services.site_service.site_type_fallback import load_site_types_by_period

router = APIRouter(prefix="/fossils", tags=["fossils"])


@router.get("", response_model=FossilListResponse)
def get_fossils(
    session: Session = Depends(get_session),
    limit: int = Query(default=200, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    sort: str = Query(default="name"),
    seed: str | None = Query(default=None),
    q: str | None = Query(default=None),
    dino_q: str | None = Query(default=None),
    fossil_q: str | None = Query(default=None),
    ma_younger: float | None = Query(default=None),
    ma_older: float | None = Query(default=None),
    has_custom_image: bool = Query(default=False),
    has_custom_fossil_image: bool = Query(default=False),
    llm_enriched: bool | None = Query(default=None),
    dinosaur_id: int | None = Query(default=None, ge=1),
) -> FossilListResponse:
    if sort not in ("name", "random"):
        raise ValidationError("sort must be one of: name, random")
    rows, total = list_fossils(
        session,
        limit=limit,
        offset=offset,
        sort=sort,  # type: ignore[arg-type]
        seed=seed,
        q=q,
        dino_q=dino_q,
        fossil_q=fossil_q,
        ma_younger=ma_younger,
        ma_older=ma_older,
        has_custom_image=has_custom_image,
        has_custom_fossil_image=has_custom_fossil_image,
        llm_enriched=llm_enriched,
        dinosaur_id=dinosaur_id,
    )
    types_by_period = load_site_types_by_period(session)
    items = [
        fossil_row_to_summary(row, types_by_period=types_by_period) for row in rows
    ]
    return FossilListResponse(
        items=items,
        total=total,
        limit=limit,
        offset=offset,
        has_next=offset + len(items) < total,
    )


@router.get("/{fossil_id}", response_model=FossilSummary)
def get_fossil(
    fossil_id: int,
    session: Session = Depends(get_session),
) -> FossilSummary:
    row = get_fossil_by_id(session, fossil_id)
    types_by_period = load_site_types_by_period(session)
    return fossil_row_to_summary(row, types_by_period=types_by_period)
