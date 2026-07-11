"""Dinosaur read endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlmodel import Session

from app.core.database import get_session
from app.schemas.dinosaur import DinosaurListResponse, DinosaurSummary
from app.services.dinosaur_service import get_dinosaur_by_id, list_dinosaurs

router = APIRouter(prefix="/dinosaurs", tags=["dinosaurs"])


@router.get("", response_model=DinosaurListResponse)
def get_dinosaurs(
    session: Session = Depends(get_session),
    limit: int = Query(default=200, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
) -> DinosaurListResponse:
    rows, total = list_dinosaurs(session, limit=limit, offset=offset)
    return DinosaurListResponse(
        items=[DinosaurSummary.model_validate(row) for row in rows],
        total=total,
        limit=limit,
        offset=offset,
    )


@router.get("/{dinosaur_id}", response_model=DinosaurSummary)
def get_dinosaur(
    dinosaur_id: int,
    session: Session = Depends(get_session),
) -> DinosaurSummary:
    row = get_dinosaur_by_id(session, dinosaur_id)
    return DinosaurSummary.model_validate(row)
