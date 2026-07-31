"""Public site-type catalog read endpoint."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlmodel import Session

from app.core.database import get_session
from app.core.security import get_optional_current_user
from app.models.user import User
from app.schemas.site import SiteTypeListResponse
from app.services.site_service.site_type_list import (
    list_site_types,
    owned_occurrences_for_site_types,
    site_type_to_summary,
)

router = APIRouter(prefix="/site-types", tags=["site-types"])


@router.get("", response_model=SiteTypeListResponse)
def get_site_types(
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_optional_current_user),
    limit: int = Query(default=200, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
) -> SiteTypeListResponse:
    rows, total = list_site_types(session, limit=limit, offset=offset)
    viewer_user_id = current_user.id if current_user is not None else None
    type_ids = [int(row.id) for row in rows if row.id is not None]
    owned = owned_occurrences_for_site_types(
        session, type_ids=type_ids, viewer_user_id=viewer_user_id
    )
    items = [
        site_type_to_summary(
            row,
            owned_occurrences=owned.get(int(row.id), []) if row.id is not None else [],
        )
        for row in rows
    ]
    return SiteTypeListResponse(
        items=items,
        total=total,
        limit=limit,
        offset=offset,
        has_next=offset + len(items) < total,
    )
