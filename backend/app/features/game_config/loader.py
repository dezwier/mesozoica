"""File loading, document composition, and checksums for game configuration."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path

import yaml

from app.features.game_config.domain import (
    DOCUMENT_FILES,
    DOCUMENT_IDS,
    FieldSurveyConfig,
    GameConfig,
    LevelingConfig,
    PeriodColorsConfig,
    RockTypeColorsConfig,
    SiteGenerationConfig,
    SkillStubConfig,
    ToolActionsConfig,
)

RawDocuments = dict[str, dict[str, object]]
_DEFAULT_CONFIG_DIR = Path(__file__).resolve().parents[2] / "game_config"


def _load_yaml(path: Path) -> dict[str, object]:
    with path.open(encoding="utf-8") as handle:
        data = yaml.safe_load(handle)
    if data is None:
        return {}
    if not isinstance(data, dict):
        raise ValueError(f"Invalid game config (expected mapping): {path}")
    return data


def resolve_game_config_dir() -> Path:
    override = os.environ.get("GAME_CONFIG_DIR", "").strip()
    return Path(override) if override else _DEFAULT_CONFIG_DIR


def load_yaml_documents(config_dir: Path | None = None) -> RawDocuments:
    directory = config_dir or resolve_game_config_dir()
    if not directory.is_dir():
        raise FileNotFoundError(f"Missing game config directory: {directory}")
    return {doc_id: _load_yaml(directory / filename) for doc_id, filename in DOCUMENT_FILES}


def build_game_config(documents: RawDocuments) -> GameConfig:
    missing = [doc_id for doc_id in DOCUMENT_IDS if doc_id not in documents]
    if missing:
        raise ValueError(f"Missing game config documents: {', '.join(missing)}")
    return GameConfig(
        site_generation=SiteGenerationConfig.model_validate(documents["site_generation"]),
        field_survey=FieldSurveyConfig.model_validate(documents["field_survey"]),
        bone_quarry=SkillStubConfig.model_validate(documents["bone_quarry"]),
        science_hall=SkillStubConfig.model_validate(documents["science_hall"]),
        tool_actions=ToolActionsConfig.model_validate(documents["tool_actions"]),
        period_colors=PeriodColorsConfig.model_validate(documents["period_colors"]),
        rock_type_colors=RockTypeColorsConfig.model_validate(documents["rock_type_colors"]),
        leveling=LevelingConfig.model_validate(documents["leveling"]),
    )


def canonical_checksum(documents: RawDocuments) -> str:
    payload = json.dumps(documents, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def load_game_config(config_dir: Path | None = None) -> GameConfig:
    return build_game_config(load_yaml_documents(config_dir))
