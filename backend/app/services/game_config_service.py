"""Serve the shared game-config control board to clients.

This is Phase 1 of the game-config single-source-of-truth plan (see
``docs/game-config.md``): the backend already owns the YAML control board, so we
expose it over HTTP and let the Flutter client (and, later, an admin web tool)
fetch config at runtime instead of bundling a copy. Values are unchanged here —
only the delivery path moves from "bundled asset" to "fetched from the API".

The payload carries a content ``version`` so clients (and HTTP caches via ETag)
can cheaply detect changes; this is the hook a future DB-backed, live-editable
control board will reuse to push updates without an app release.
"""

from __future__ import annotations

import hashlib
import json
from functools import lru_cache
from typing import Any

from app.core.game_config import get_game_config, load_game_config_raw


def _compute_version(sections: dict[str, Any]) -> str:
    """Stable short hash of the config content (order-independent)."""
    canonical = json.dumps(
        sections, sort_keys=True, separators=(",", ":"), default=str
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:16]


@lru_cache(maxsize=1)
def get_game_config_payload() -> dict[str, Any]:
    """Return ``{"version": str, "config": dict}`` for the current control board.

    :func:`get_game_config` is called first so a schema-invalid control board
    fails loudly instead of shipping broken values to clients. The raw sections
    are then returned so clients parse the exact structure they would from the
    bundled YAML fallback.

    Cached process-wide. When the control board can change at runtime (the future
    admin write path), call :func:`clear_game_config_payload_cache` after a write.
    """
    get_game_config()  # validate; raises on a malformed control board
    sections = load_game_config_raw()
    return {"version": _compute_version(sections), "config": sections}


def get_game_config_version() -> str:
    """Content version of the active control board (for ETag / change signals)."""
    return get_game_config_payload()["version"]


def clear_game_config_payload_cache() -> None:
    """Drop the cached payload (tests, and the future admin write path)."""
    get_game_config_payload.cache_clear()
