"""Public game config endpoints owned by the game-config feature.

Unauthenticated on purpose: the app fetches this during bootstrap, before login
and on first launch. The content already ships inside every app binary, so it
is not a secret.
"""

from __future__ import annotations

from fastapi import APIRouter, Request, Response, status

from app.core.game_config_provider import get_active_snapshot
from app.schemas.game_config import GameConfigResponse, GameConfigVersionResponse

router = APIRouter(prefix="/game-config", tags=["game-config"])

_REVALIDATE = "no-cache"


@router.get("", response_model=GameConfigResponse)
async def get_public_game_config(request: Request, response: Response):
    """The active control board. Revalidate cheaply with ``If-None-Match``."""
    snapshot = get_active_snapshot()
    headers = {"ETag": snapshot.etag, "Cache-Control": _REVALIDATE}

    if request.headers.get("if-none-match") == snapshot.etag:
        return Response(status_code=status.HTTP_304_NOT_MODIFIED, headers=headers)

    response.headers.update(headers)
    return GameConfigResponse(
        version=snapshot.version,
        checksum=snapshot.checksum,
        activated_at=snapshot.activated_at,
        source=snapshot.source,
        documents=snapshot.documents,
    )


@router.get("/version", response_model=GameConfigVersionResponse)
async def get_public_game_config_version(response: Response):
    """Cheap freshness probe (~90 bytes) for clients that already have a bundle."""
    snapshot = get_active_snapshot()
    response.headers["ETag"] = snapshot.etag
    response.headers["Cache-Control"] = _REVALIDATE
    return GameConfigVersionResponse(
        version=snapshot.version,
        checksum=snapshot.checksum,
        activated_at=snapshot.activated_at,
    )
