"""Field-assistant ask endpoint. Owned by the assistant feature."""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, status

from app.core.security import get_current_user
from app.features.assistant.application.ask import ask_question
from app.features.assistant.schemas import AskRequest, AskResponse
from app.models.user import User
from mesozoica_ai.common.errors import (
    CitationError,
    ConfigurationError,
    InsufficientEvidenceError,
    StructuredOutputError,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/assistant", tags=["assistant"])


@router.post("/ask", response_model=AskResponse)
async def ask(
    body: AskRequest,
    current_user: User = Depends(get_current_user),
) -> AskResponse:
    """Answer a natural-language paleontology question from indexed knowledge."""
    _ = current_user
    try:
        return ask_question(body.question)
    except InsufficientEvidenceError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Not enough indexed knowledge to answer that question.",
        ) from exc
    except (CitationError, ConfigurationError, StructuredOutputError) as exc:
        logger.warning("assistant ask failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Field assistant is temporarily unavailable.",
        ) from exc
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from exc
    except Exception as exc:
        logger.exception("assistant ask unexpected failure")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Field assistant is temporarily unavailable.",
        ) from exc
