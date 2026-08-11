"""Field-assistant knowledge browser endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlmodel import Session

from app.core.database import get_session
from app.core.security import get_current_user
from app.features.assistant.application.list_sources import list_subject_sources
from app.features.assistant.application.list_subjects import list_indexed_subjects
from app.features.assistant.schemas import (
    KnowledgeSourcesResponse,
    KnowledgeSubjectsResponse,
)
from app.models.user import User

router = APIRouter(prefix="/assistant", tags=["assistant"])


@router.get("/subjects", response_model=KnowledgeSubjectsResponse)
async def get_subjects(
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> KnowledgeSubjectsResponse:
    """List dinosaurs that have at least one succeeded knowledge index."""
    _ = current_user
    return KnowledgeSubjectsResponse(subjects=list_indexed_subjects(session))


@router.get(
    "/subjects/{subject_id}/sources",
    response_model=KnowledgeSourcesResponse,
)
async def get_subject_sources(
    subject_id: str,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> KnowledgeSourcesResponse:
    """List indexed wikipedia / openalex documents for one dinosaur."""
    _ = current_user
    result = list_subject_sources(session, subject_id)
    if result is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No indexed knowledge for that dinosaur.",
        )
    return result
