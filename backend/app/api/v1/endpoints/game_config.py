"""Serve the shared game-config control board (Phase 1 delivery).

Clients (`flutter/`) fetch the control board here at startup instead of bundling
it, so game-mechanics tuning can ship without an app release. The response is
cacheable via ETag, and the ``version`` field lets clients detect changes — the
same hook a future DB-backed, live-editable control board will reuse.
"""

from __future__ import annotations

from fastapi import APIRouter, Header, Response, status

from app.schemas.game_config import GameConfigResponse
from app.services.game_config_service import get_game_config_payload

router = APIRouter(prefix="/game-config", tags=["game-config"])


@router.get("", response_model=GameConfigResponse)
def get_game_config_document(
    response: Response,
    if_none_match: str | None = Header(default=None),
):
    """Return the full control board plus its content version.

    Honors conditional requests: when the client sends ``If-None-Match`` with the
    current ETag, respond ``304 Not Modified`` so unchanged config is a cheap
    no-body round trip.
    """
    payload = get_game_config_payload()
    etag = f'"{payload["version"]}"'

    if if_none_match is not None and if_none_match == etag:
        return Response(
            status_code=status.HTTP_304_NOT_MODIFIED,
            headers={"ETag": etag, "Cache-Control": "no-cache"},
        )

    response.headers["ETag"] = etag
    response.headers["Cache-Control"] = "no-cache"
    return GameConfigResponse(**payload)
