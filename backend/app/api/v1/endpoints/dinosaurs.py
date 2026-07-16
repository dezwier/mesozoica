"""Dinosaur read endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlmodel import Session

from app.core.database import get_session
from app.core.exceptions import ValidationError
from app.schemas.dinosaur import DinosaurArticleResponse, DinosaurListResponse, DinosaurSummary
from app.services.dinosaur_service import get_dinosaur_by_id, list_dinosaurs
from app.services.wikipedia_service.parser import prepare_article_for_display

router = APIRouter(prefix="/dinosaurs", tags=["dinosaurs"])


@router.get("", response_model=DinosaurListResponse)
def get_dinosaurs(
    session: Session = Depends(get_session),
    limit: int = Query(default=200, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    sort: str = Query(default="name"),
    seed: str | None = Query(default=None),
    q: str | None = Query(default=None),
    ma_younger: float | None = Query(default=None),
    ma_older: float | None = Query(default=None),
    has_custom_image: bool = Query(default=False),
    llm_enriched: bool | None = Query(default=None),
) -> DinosaurListResponse:
    if sort not in ("name", "random"):
        raise ValidationError("sort must be one of: name, random")
    rows, total = list_dinosaurs(
        session,
        limit=limit,
        offset=offset,
        sort=sort,  # type: ignore[arg-type]
        seed=seed,
        q=q,
        ma_younger=ma_younger,
        ma_older=ma_older,
        has_custom_image=has_custom_image,
        llm_enriched=llm_enriched,
    )
    items = [DinosaurSummary.model_validate(row) for row in rows]
    return DinosaurListResponse(
        items=items,
        total=total,
        limit=limit,
        offset=offset,
        has_next=offset + len(items) < total,
    )


@router.get("/{dinosaur_id}/article", response_model=DinosaurArticleResponse)
def get_dinosaur_article(
    dinosaur_id: int,
    session: Session = Depends(get_session),
) -> DinosaurArticleResponse:
    row = get_dinosaur_by_id(session, dinosaur_id)
    article = prepare_article_for_display(row.article)
    return DinosaurArticleResponse(
        id=row.id,
        name=row.name,
        wikipedia_title=row.wikipedia_title,
        article=article,
        article_date=row.article_date,
    )


@router.get("/{dinosaur_id}", response_model=DinosaurSummary)
def get_dinosaur(
    dinosaur_id: int,
    session: Session = Depends(get_session),
) -> DinosaurSummary:
    row = get_dinosaur_by_id(session, dinosaur_id)
    return DinosaurSummary.model_validate(row)
