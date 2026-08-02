"""Fossil read and status endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query, Response, status
from sqlmodel import Session, col, select

from app.core.database import get_session
from app.core.exceptions import NotFoundError, ValidationError
from app.core.security import (
    get_current_admin_user,
    get_current_user,
    get_optional_current_user,
)
from app.models.data_source import DATA_SOURCE_ARCHIVE, DATA_SOURCE_FIELD
from app.models.user import User
from app.models.user_fossil import UserFossil
from app.schemas.fossil import (
    FossilListResponse,
    FossilSummary,
    SetFossilStatusRequest,
)
from app.services.fossil_service.discard import discard_fossil_for_user
from app.services.fossil_service.list import fossil_row_to_summary, get_fossil_by_id, list_fossils
from app.services.fossil_service.set_status import set_fossil_status
from app.services.site_service.site_type_fallback import load_site_types_by_period

router = APIRouter(prefix="/fossils", tags=["fossils"])


@router.get("", response_model=FossilListResponse)
def get_fossils(
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_optional_current_user),
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
    data_source: str = Query(default=DATA_SOURCE_ARCHIVE),
    include_hidden: bool = Query(
        default=False,
        description="Admin-only: include undiscovered field fossils (card peek).",
    ),
) -> FossilListResponse:
    if sort not in ("name", "random"):
        raise ValidationError("sort must be one of: name, random")
    is_admin = bool(current_user is not None and current_user.is_admin)
    viewer_user_id = current_user.id if current_user is not None else None
    if include_hidden and not is_admin:
        raise ValidationError("include_hidden requires admin")
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
        data_source=data_source,
        viewer_user_id=viewer_user_id,
        include_hidden=include_hidden and is_admin,
    )
    types_by_period = load_site_types_by_period(session)
    items = [
        fossil_row_to_summary(
            row,
            types_by_period=types_by_period,
            viewer_user_id=viewer_user_id,
            session=session,
        )
        for row in rows
    ]
    return FossilListResponse(
        items=items,
        total=total,
        limit=limit,
        offset=offset,
        has_next=offset + len(items) < total,
    )


@router.post("/{fossil_id}/status", response_model=FossilSummary)
def post_set_fossil_status(
    fossil_id: int,
    body: SetFossilStatusRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_admin_user),
) -> FossilSummary:
    return set_fossil_status(
        session,
        fossil_id=fossil_id,
        user_id=current_user.id,
        status=body.status,
    )


@router.post("/{fossil_id}/discard", status_code=status.HTTP_204_NO_CONTENT)
def post_discard_fossil(
    fossil_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> Response:
    """Remove the caller's links to a field fossil."""
    discard_fossil_for_user(
        session,
        fossil_id=fossil_id,
        user_id=int(current_user.id),
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/{fossil_id}", response_model=FossilSummary)
def get_fossil(
    fossil_id: int,
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_optional_current_user),
    data_source: str = Query(default=DATA_SOURCE_ARCHIVE),
) -> FossilSummary:
    row = get_fossil_by_id(session, fossil_id, data_source=data_source)
    is_admin = bool(current_user is not None and current_user.is_admin)
    viewer_user_id = current_user.id if current_user is not None else None
    # Admins may open hidden fossils from site/dino card peeks.
    if row.fossil.data_source == DATA_SOURCE_FIELD and not is_admin:
        if viewer_user_id is None:
            raise NotFoundError(f"Fossil {fossil_id} not found")
        link = session.exec(
            select(UserFossil).where(
                col(UserFossil.user_id) == viewer_user_id,
                col(UserFossil.fossil_id) == fossil_id,
            )
        ).first()
        if link is None:
            raise NotFoundError(f"Fossil {fossil_id} not found")
    types_by_period = load_site_types_by_period(session)
    return fossil_row_to_summary(
        row,
        types_by_period=types_by_period,
        viewer_user_id=viewer_user_id,
        session=session,
    )
