"""Stored game config: revision history, active release, seeding."""

from app.services.game_config_service.locked_paths import (
    GameConfigLocked,
    assert_locked_paths_unchanged,
    locked_path_violations,
)
from app.services.game_config_service.read import (
    RevisionMeta,
    StoredConfig,
    list_revisions,
    read_active_config,
    read_active_version,
    read_release,
    read_revision,
)
from app.services.game_config_service.seed import (
    SeedSummary,
    ensure_seeded,
    seed_from_yaml,
)
from app.services.game_config_service.write import (
    GameConfigConflict,
    normalize_documents,
    publish_documents,
    rollback_to_version,
    validate_documents,
)

__all__ = [
    "GameConfigConflict",
    "GameConfigLocked",
    "RevisionMeta",
    "SeedSummary",
    "StoredConfig",
    "assert_locked_paths_unchanged",
    "ensure_seeded",
    "list_revisions",
    "locked_path_violations",
    "normalize_documents",
    "publish_documents",
    "read_active_config",
    "read_active_version",
    "read_release",
    "read_revision",
    "rollback_to_version",
    "seed_from_yaml",
    "validate_documents",
]
