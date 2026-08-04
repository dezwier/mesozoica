"""Schemas for the shared game-config control board endpoint."""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class GameConfigResponse(BaseModel):
    """The full game-config control board plus a content version.

    ``config`` is the raw per-section control board (``site_generation``, each
    skill id, ``tool_actions``, ``period_colors``, ``rock_type_colors``,
    ``leveling``) — the same structure the Flutter client parses from its bundled
    YAML fallback. ``version`` is a stable content hash used for ETag caching and
    client-side change detection.
    """

    version: str = Field(description="Stable content hash of the control board.")
    config: dict[str, Any] = Field(
        description="Raw game-config sections keyed by domain."
    )
