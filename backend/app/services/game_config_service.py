"""Serve the shared game-config control board to clients.

Part of the game-config single-source-of-truth plan (see ``docs/game-config.md``).
The backend owns the YAML control board and is the single source of truth; it
exposes the **canonical, validated projection** of that board over HTTP so the
Flutter client (and, later, an admin web tool) consume one authoritative shape
instead of re-deriving values and defaults independently.

"Canonical" means the config is loaded, validated, and normalized through the
Pydantic ``GameConfig`` model (`model_dump`). Defaults and types therefore come
from one place (the schema), which removes a whole class of client/server drift.

The payload carries a content ``version`` so clients (and HTTP caches via ETag)
can cheaply detect changes; this is the hook a future DB-backed, live-editable
control board will reuse to push updates without an app release.
"""

from __future__ import annotations

import hashlib
import json
from functools import lru_cache
from typing import Any

from app.core.game_config import get_game_config


def build_canonical_config() -> dict[str, Any]:
    """Return the validated, normalized control board as a JSON-safe dict.

    This is the single shape served to clients and written to the client's
    bundled snapshot (``flutter/assets/game_config.json``), so both always agree.
    """
    return get_game_config().model_dump(mode="json")


def compute_config_version(config: dict[str, Any]) -> str:
    """Stable short content hash of a config document (order-independent)."""
    canonical = json.dumps(config, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:16]


@lru_cache(maxsize=1)
def get_game_config_payload() -> dict[str, Any]:
    """Return ``{"version": str, "config": dict}`` for the current control board.

    Cached process-wide. When the control board can change at runtime (the future
    admin write path), call :func:`clear_game_config_payload_cache` after a write.
    """
    config = build_canonical_config()
    return {"version": compute_config_version(config), "config": config}


def get_game_config_version() -> str:
    """Content version of the active control board (for ETag / change signals)."""
    return get_game_config_payload()["version"]


def clear_game_config_payload_cache() -> None:
    """Drop the cached payload (tests, and the future admin write path)."""
    get_game_config_payload.cache_clear()
