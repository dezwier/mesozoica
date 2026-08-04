"""Admin game config endpoints — the write surface the web app will drive.

Thin per the repo rule: parse HTTP, call ``game_config_service``, return a
schema. All validation, locking, and versioning lives in the service.
"""

from __future__ import annotations

import copy
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import ValidationError
from sqlmodel import Session

from app.core.database import get_session
from app.core.game_config import DOCUMENT_IDS
from app.core.game_config_docs import DOCUMENT_SPECS, LOCKED_PATHS
from app.core.security import get_current_admin_user
from app.models.user import User
from app.schemas.game_config import (
    GameConfigDocMeta,
    GameConfigDocumentPatchRequest,
    GameConfigPublishRequest,
    GameConfigResponse,
    GameConfigRevisionSummary,
    GameConfigRollbackRequest,
    GameConfigSchemaResponse,
    GameConfigValidateResponse,
)
from app.services.game_config_service import (
    GameConfigConflict,
    GameConfigLocked,
    StoredConfig,
    list_revisions,
    publish_documents,
    read_active_config,
    read_revision,
    rollback_to_version,
    validate_documents,
)

router = APIRouter(
    prefix="/admin/game-config",
    tags=["admin", "game-config"],
    dependencies=[Depends(get_current_admin_user)],
)


def _to_response(stored: StoredConfig) -> GameConfigResponse:
    return GameConfigResponse(
        version=stored.version,
        checksum=stored.checksum,
        activated_at=stored.activated_at,
        source="db",
        documents=stored.documents,
    )


def _require_active(session: Session) -> StoredConfig:
    stored = read_active_config(session)
    if stored is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No game config has been seeded yet",
        )
    return stored


def _publish(
    session: Session,
    *,
    documents: dict,
    base_version: Optional[int],
    note: str,
    user_id: Optional[int],
) -> GameConfigResponse:
    """Shared error mapping for every write path."""
    try:
        stored = publish_documents(
            session,
            documents=documents,
            base_version=base_version,
            note=note,
            source="admin",
            user_id=user_id,
        )
    except GameConfigConflict as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc))
    except GameConfigLocked as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))
    except ValidationError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=exc.errors(include_url=False),
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))
    return _to_response(stored)


@router.get("", response_model=GameConfigResponse)
async def get_active(session: Session = Depends(get_session)):
    return _to_response(_require_active(session))


@router.get("/schema", response_model=GameConfigSchemaResponse)
async def get_schema():
    """Document list and non-editable paths, so the web app need not hardcode them."""
    return GameConfigSchemaResponse(
        documents=[
            GameConfigDocMeta(
                doc_id=spec.doc_id,
                filename=spec.filename,
                label=spec.label,
                is_skill=spec.is_skill,
            )
            for spec in DOCUMENT_SPECS
        ],
        locked_paths=list(LOCKED_PATHS),
    )


@router.get("/revisions", response_model=list[GameConfigRevisionSummary])
async def get_revisions(
    limit: int = Query(50, ge=1, le=500),
    session: Session = Depends(get_session),
):
    return [
        GameConfigRevisionSummary(**vars(meta))
        for meta in list_revisions(session, limit=limit)
    ]


@router.get("/revisions/{version}", response_model=GameConfigResponse)
async def get_one_revision(version: int, session: Session = Depends(get_session)):
    stored = read_revision(session, version)
    if stored is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Unknown game config version: {version}",
        )
    return _to_response(stored)


@router.post("/validate", response_model=GameConfigValidateResponse)
async def validate(payload: GameConfigPublishRequest):
    """Dry run: full validation, no write."""
    try:
        validate_documents(payload.documents)
    except ValidationError as exc:
        return GameConfigValidateResponse(valid=False, errors=exc.errors(include_url=False))
    except ValueError as exc:
        return GameConfigValidateResponse(
            valid=False, errors=[{"msg": str(exc), "type": "value_error"}]
        )
    return GameConfigValidateResponse(valid=True)


@router.put("", response_model=GameConfigResponse)
async def publish_full_bundle(
    payload: GameConfigPublishRequest,
    session: Session = Depends(get_session),
    admin: User = Depends(get_current_admin_user),
):
    return _publish(
        session,
        documents=payload.documents,
        base_version=payload.base_version,
        note=payload.note,
        user_id=admin.id,
    )


@router.patch("/documents/{doc_id}", response_model=GameConfigResponse)
async def patch_document(
    doc_id: str,
    payload: GameConfigDocumentPatchRequest,
    session: Session = Depends(get_session),
    admin: User = Depends(get_current_admin_user),
):
    """Replace one document, carrying the other sixteen over unchanged."""
    if doc_id not in DOCUMENT_IDS:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Unknown game config document: {doc_id}",
        )
    active = _require_active(session)
    documents = copy.deepcopy(active.documents)
    documents[doc_id] = payload.data

    return _publish(
        session,
        documents=documents,
        base_version=payload.base_version,
        note=payload.note or f"edit {doc_id}",
        user_id=admin.id,
    )


@router.post("/rollback", response_model=GameConfigResponse)
async def rollback(
    payload: GameConfigRollbackRequest,
    session: Session = Depends(get_session),
    admin: User = Depends(get_current_admin_user),
):
    """Republish an old revision's content as a new, higher version."""
    try:
        stored = rollback_to_version(
            session,
            to_version=payload.to_version,
            note=payload.note,
            user_id=admin.id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    return _to_response(stored)
