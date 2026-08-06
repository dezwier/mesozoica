"""Load shared game-mechanics YAML (control board under app/game_config/)."""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field, field_validator, model_validator

# Raw parsed YAML mappings keyed by document id. This is the wire shape the
# config API serves and the storage shape in the database, so the Pydantic
# models below stay the single validation path for every source.
RawDocuments = dict[str, dict[str, Any]]

# Every control board document, in load order. Numbered files are skill domains
# (order matches leveling.yaml skills); the rest are non-skill domains.
DOCUMENT_FILES: tuple[tuple[str, str], ...] = (
    ("site_generation", "site_generation.yaml"),
    ("field_survey", "01_field_survey.yaml"),
    ("bone_quarry", "02_bone_quarry.yaml"),
    ("science_hall", "03_science_hall.yaml"),
    ("tool_actions", "tool_actions.yaml"),
    ("period_colors", "period_colors.yaml"),
    ("rock_type_colors", "rock_type_colors.yaml"),
    ("leveling", "leveling.yaml"),
)

DOCUMENT_IDS: tuple[str, ...] = tuple(doc_id for doc_id, _ in DOCUMENT_FILES)

from app.features.game_config.sections.actions import *  # noqa: F403
from app.features.game_config.sections.field_survey import *  # noqa: F403
from app.features.game_config.sections.leveling import *  # noqa: F403
from app.features.game_config.sections.modifiers import *  # noqa: F403
from app.features.game_config.sections.site_generation import *  # noqa: F403
from app.features.game_config.sections.tool_actions import *  # noqa: F403

class GameConfig(BaseModel):
    model_config = {"frozen": True}

    site_generation: SiteGenerationConfig
    field_survey: FieldSurveyConfig
    bone_quarry: SkillStubConfig
    science_hall: SkillStubConfig
    tool_actions: ToolActionsConfig
    period_colors: PeriodColorsConfig
    rock_type_colors: RockTypeColorsConfig
    leveling: LevelingConfig

    # Back-compat aliases for call sites during migration.
    @property
    def site_discovery(self) -> FieldSurveyConfig:
        return self.field_survey

    @property
    def site_stewardship(self) -> FieldSurveyConfig:
        return self.field_survey

    @property
    def fossil_generation(self) -> FieldSurveyConfig:
        return self.field_survey

    @property
    def fossil_detection(self) -> SkillStubConfig:
        return self.bone_quarry

    def skill_domain(self, skill_id: str) -> Any:
        """Return the config object for a skill id (rich or stub)."""
        mapping: dict[str, Any] = {
            "field_survey": self.field_survey,
            "bone_quarry": self.bone_quarry,
            "science_hall": self.science_hall,
            # Legacy ids redirect to merged skills.
            "site_discovery": self.field_survey,
            "site_stewardship": self.field_survey,
            "site_clearing": self.field_survey,
            "fossil_detection": self.bone_quarry,
            "fossil_excavation": self.bone_quarry,
            "fossil_transport": self.bone_quarry,
            "fossil_curation": self.bone_quarry,
            "fossil_preparation": self.science_hall,
            "fossil_analysis": self.science_hall,
            "dinosaur_modelling": self.science_hall,
            "dinosaur_mounting": self.science_hall,
            "academic_publishing": self.science_hall,
            "fossil_discovery": self.bone_quarry,
        }
        try:
            return mapping[skill_id]
        except KeyError as exc:
            raise KeyError(f"unknown skill id: {skill_id}") from exc


from app.features.game_config.loader import (
    build_game_config,
    canonical_checksum,
    load_game_config,
    load_yaml_documents,
    resolve_game_config_dir,
)
def _clear_game_config_cache() -> None:
    from app.features.game_config.provider import invalidate_game_config_cache

    invalidate_game_config_cache()


def get_game_config() -> GameConfig:
    """Process-wide config.

    Source depends on ``GAME_CONFIG_SOURCE`` (``db`` by default, ``yaml`` as the
    break-glass path). Clear with ``get_game_config.cache_clear()`` in tests.

    The import is deferred so this module never pulls in the database layer —
    the minimal-settings worker and the DB-free tests rely on that.
    """
    from app.features.game_config.provider import get_active_snapshot

    return get_active_snapshot().config


# Back-compat: callers and ~5 test modules already use the lru_cache API.
get_game_config.cache_clear = _clear_game_config_cache  # type: ignore[attr-defined]
