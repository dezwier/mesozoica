"""Supported cross-feature game-config surface."""

from app.features.game_config.domain import (
    DOCUMENT_FILES,
    DOCUMENT_IDS,
    GameConfig,
    RawDocuments,
    build_game_config,
    canonical_checksum,
    get_game_config,
    load_game_config,
    load_yaml_documents,
)
from app.features.game_config.provider import GameConfigSnapshot, get_active_snapshot

__all__ = [name for name in globals() if not name.startswith("_")]
