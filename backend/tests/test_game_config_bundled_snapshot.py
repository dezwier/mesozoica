"""Drift guard: the committed client snapshot must match the backend control board.

The Flutter client bundles ``flutter/assets/game_config.json`` as its offline
fallback. It is generated from the backend YAML (the single source of truth) by
``scripts/export_bundled_game_config``. This test fails if the control board
changed but the snapshot was not regenerated — keeping client and server in sync.
"""

import json

from app.core.game_config import GameConfig
from scripts.export_bundled_game_config import (
    SNAPSHOT_PATH,
    build_snapshot_document,
    render_snapshot,
)


def test_bundled_snapshot_is_in_sync_with_control_board():
    assert SNAPSHOT_PATH.is_file(), (
        f"Missing client snapshot at {SNAPSHOT_PATH}. "
        "Run: cd backend && .venv/bin/python -m scripts.export_bundled_game_config"
    )
    committed = SNAPSHOT_PATH.read_text(encoding="utf-8")
    expected = render_snapshot(build_snapshot_document())
    assert committed == expected, (
        "flutter/assets/game_config.json is stale. Regenerate it with: "
        "cd backend && .venv/bin/python -m scripts.export_bundled_game_config"
    )


def test_bundled_snapshot_is_valid_and_versioned():
    document = json.loads(SNAPSHOT_PATH.read_text(encoding="utf-8"))
    assert isinstance(document.get("version"), str) and document["version"]
    # The snapshot config must round-trip back through the schema (canonical shape).
    GameConfig.model_validate(document["config"])
