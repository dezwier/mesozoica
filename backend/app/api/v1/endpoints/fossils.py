"""Fossil read endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlmodel import Session

from app.core.database import get_session
from app.core.exceptions import ValidationError
from app.schemas.fossil import FossilListResponse, FossilSummary
from app.services.fossil_service.list import fossil_row_to_summary, list_fossils

router = APIRouter(prefix="/fossils", tags=["fossils"])


@router.get("", response_model=FossilListResponse)
def get_fossils(
    session: Session = Depends(get_session),
    limit: int = Query(default=200, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    sort: str = Query(default="name"),
    seed: str | None = Query(default=None),
    q: str | None = Query(default=None),
    ma_younger: float | None = Query(default=None),
    ma_older: float | None = Query(default=None),
    has_custom_image: bool = Query(default=False),
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
        ma_younger=ma_younger,
        ma_older=ma_older,
        has_custom_image=has_custom_image,
    )
    items = [fossil_row_to_summary(row) for row in rows]
    return FossilListResponse(
        items=items,
        total=total,
        limit=limit,
        offset=offset,
        has_next=offset + len(items) < total,
    )
