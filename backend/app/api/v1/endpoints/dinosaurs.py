"""Dinosaur read and status endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlmodel import Session

from app.core.database import get_session
from app.core.exceptions import ValidationError
from app.core.security import get_current_admin_user, get_optional_current_user
from app.models.user import User
from app.models.user_dinosaur import DINOSAUR_STATUS_HIDDEN
from app.schemas.dinosaur import (
    DinosaurArticleResponse,
    DinosaurListResponse,
    DinosaurSummary,
    SetDinosaurStatusRequest,
)
from app.services.dinosaur_service import get_dinosaur_by_id, list_dinosaurs
from app.services.dinosaur_service.list import (
    DinosaurListRow,
    ListMode,
    dinosaur_to_summary,
    viewer_status_for_occurrence,
    viewer_statuses_for_types,
)
from app.services.dinosaur_service.set_status import set_dinosaur_status
from app.services.curated_image_service.versions import ORIGINAL_VERSION
from app.services.wikipedia_service.parser import prepare_article_for_display

router = APIRouter(prefix="/dinosaurs", tags=["dinosaurs"])


@router.get("", response_model=DinosaurListResponse)
def get_dinosaurs(
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
    llm_enriched: bool | None = Query(default=None),
    mode: ListMode = Query(default="catalog"),
) -> DinosaurListResponse:
    if sort not in ("name", "random"):
        raise ValidationError("sort must be one of: name, random")
    if mode not in ("catalog", "inventory"):
        raise ValidationError("mode must be one of: catalog, inventory")
    viewer_user_id = current_user.id if current_user is not None else None
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
        mode=mode,
        viewer_user_id=viewer_user_id,
    )
    if mode == "catalog":
        type_ids = [int(row.dinosaur_type.id) for row in rows]
        statuses = viewer_statuses_for_types(
            session, type_ids=type_ids, viewer_user_id=viewer_user_id
        )
        items = [
            dinosaur_to_summary(
                row,
                viewer_status=statuses.get(
                    int(row.dinosaur_type.id), DINOSAUR_STATUS_HIDDEN
                )
                if viewer_user_id is not None
                else None,
            )
            for row in rows
        ]
    else:
        items = [
            dinosaur_to_summary(
                row,
                viewer_status=viewer_status_for_occurrence(
                    session,
                    occurrence_id=int(row.occurrence_id),
                    viewer_user_id=viewer_user_id,
                )
                if row.occurrence_id is not None
                else None,
            )
            for row in rows
        ]
    return DinosaurListResponse(
        items=items,
        total=total,
        limit=limit,
        offset=offset,
        has_next=offset + len(items) < total,
    )


@router.post("/{dinosaur_id}/status", response_model=DinosaurSummary)
def post_set_dinosaur_status(
    dinosaur_id: int,
    body: SetDinosaurStatusRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_admin_user),
) -> DinosaurSummary:
    """Set status for a catalog dinosaur type (creates inventory occurrence)."""
    return set_dinosaur_status(
        session,
        dinosaur_type_id=dinosaur_id,
        user_id=current_user.id,
        status=body.status,
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
    current_user: User | None = Depends(get_optional_current_user),
) -> DinosaurSummary:
    row = get_dinosaur_by_id(session, dinosaur_id)
    viewer_user_id = current_user.id if current_user is not None else None
    status = None
    if viewer_user_id is not None:
        statuses = viewer_statuses_for_types(
            session, type_ids=[dinosaur_id], viewer_user_id=viewer_user_id
        )
        status = statuses.get(dinosaur_id, DINOSAUR_STATUS_HIDDEN)
    return dinosaur_to_summary(
        DinosaurListRow(dinosaur_type=row, image_version=ORIGINAL_VERSION),
        viewer_status=status,
    )
