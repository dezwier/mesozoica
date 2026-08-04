"""Generate the Flutter client's bundled game-config snapshot from the backend.

The backend YAML control board is the single source of truth. The Flutter client
ships a canonical JSON snapshot as its offline / first-launch fallback; this
script regenerates that snapshot so it always matches the validated backend
config. Run it whenever the control board changes:

    cd backend && .venv/bin/python -m scripts.export_bundled_game_config

The committed snapshot is drift-checked in CI by
``tests/test_game_config_bundled_snapshot.py`` (which fails if this script has
not been re-run after a control-board change).
"""

from __future__ import annotations

import json
from pathlib import Path

from app.services.game_config_service import (
    build_canonical_config,
    compute_config_version,
)

# backend/scripts/this.py -> parents[2] == repo root
_REPO_ROOT = Path(__file__).resolve().parents[2]
SNAPSHOT_PATH = _REPO_ROOT / "flutter" / "assets" / "game_config.json"


def build_snapshot_document() -> dict:
    """The `{version, config}` document written to the client bundle."""
    config = build_canonical_config()
    return {"version": compute_config_version(config), "config": config}


def render_snapshot(document: dict) -> str:
    """Deterministic JSON text (stable key order + trailing newline) for clean diffs."""
    return json.dumps(document, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def write_snapshot(path: Path = SNAPSHOT_PATH) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(render_snapshot(build_snapshot_document()), encoding="utf-8")
    return path


def main() -> int:
    path = write_snapshot()
    print(f"Wrote bundled game-config snapshot: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
