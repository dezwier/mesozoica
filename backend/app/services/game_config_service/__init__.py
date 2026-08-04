"""Stored game config: revision history, active release, seeding.

Exports the public surface only — the callable operations plus the types they
return. Internal plumbing (locked-path matching, document normalization, the
release row accessor) stays reachable from its own module.
"""

from app.services.game_config_service.locked_paths import GameConfigLocked
from app.services.game_config_service.read import (
    RevisionMeta,
    StoredConfig,
    list_revisions,
    read_active_config,
    read_active_version,
    read_revision,
)
from app.services.game_config_service.seed import (
    SeedSummary,
    ensure_seeded,
    seed_from_yaml,
)
from app.services.game_config_service.write import (
    GameConfigConflict,
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
    "ensure_seeded",
    "list_revisions",
    "publish_documents",
    "read_active_config",
    "read_active_version",
    "read_revision",
    "rollback_to_version",
    "seed_from_yaml",
    "validate_documents",
]
