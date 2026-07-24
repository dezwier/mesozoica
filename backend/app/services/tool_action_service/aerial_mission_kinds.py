"""Registry of aerial mission kinds (recon, scout, …)."""

from __future__ import annotations

from dataclasses import dataclass

from app.core.exceptions import ValidationError
from app.core.game_config import AerialMissionActionConfig, ToolActionsConfig, get_game_config
from app.models.tool_mission import (
    ACTION_KEY_AERIAL_RECON,
    ACTION_KEY_AERIAL_SCOUT,
    AERIAL_MISSION_ACTION_KEYS,
)


@dataclass(frozen=True)
class AerialMissionKind:
    action_key: str
    tool_name: str
    display_label: str


AERIAL_MISSION_KINDS: tuple[AerialMissionKind, ...] = (
    AerialMissionKind(
        action_key=ACTION_KEY_AERIAL_RECON,
        tool_name="Aerial Recon",
        display_label="Aerial Recon",
    ),
    AerialMissionKind(
        action_key=ACTION_KEY_AERIAL_SCOUT,
        tool_name="Aerial Scout",
        display_label="Aerial Scout",
    ),
)

_BY_ACTION_KEY = {k.action_key: k for k in AERIAL_MISSION_KINDS}
_BY_TOOL_NAME = {k.tool_name: k for k in AERIAL_MISSION_KINDS}


def is_aerial_action_key(action_key: str) -> bool:
    return action_key in _BY_ACTION_KEY


def kind_for_action_key(action_key: str) -> AerialMissionKind:
    kind = _BY_ACTION_KEY.get(action_key)
    if kind is None:
        raise ValidationError(f"Unknown aerial action_key: {action_key}")
    return kind


def kind_for_tool_name(tool_name: str) -> AerialMissionKind:
    kind = _BY_TOOL_NAME.get(tool_name)
    if kind is None:
        raise ValidationError(
            "This action is only available for Aerial Recon or Aerial Scout"
        )
    return kind


def config_for_action_key(
    action_key: str,
    tool_actions: ToolActionsConfig | None = None,
) -> AerialMissionActionConfig:
    """Return snapshotted knobs for [action_key] from game config."""
    actions = tool_actions if tool_actions is not None else get_game_config().tool_actions
    if action_key == ACTION_KEY_AERIAL_RECON:
        return actions.aerial_recon
    if action_key == ACTION_KEY_AERIAL_SCOUT:
        return actions.aerial_scout
    raise ValidationError(f"Unknown aerial action_key: {action_key}")


__all__ = [
    "AERIAL_MISSION_ACTION_KEYS",
    "AERIAL_MISSION_KINDS",
    "AerialMissionKind",
    "config_for_action_key",
    "is_aerial_action_key",
    "kind_for_action_key",
    "kind_for_tool_name",
]
