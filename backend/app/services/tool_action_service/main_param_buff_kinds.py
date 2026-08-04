"""Registry of global main-param buff tools (Ridge Glass, mobility, Nocturne, …)."""

from __future__ import annotations

from dataclasses import dataclass

from app.core.exceptions import ValidationError
from app.core.game_config import (
    MainParamBuffActionConfig,
    ToolActionsConfig,
    get_game_config,
)
from app.models.tool_session import (
    ACTION_KEY_CANYON_THROTTLE,
    ACTION_KEY_EXPEDITION_DRIVETRAIN,
    ACTION_KEY_NOCTURNE_LENS,
    ACTION_KEY_OVERLAND_CHASSIS,
    ACTION_KEY_RIDGE_GLASS,
    ACTION_KEY_TRAIL_STRIDERS,
    GLOBAL_BUFF_ACTION_KEYS,
)


@dataclass(frozen=True)
class MainParamBuffKind:
    action_key: str
    tool_name: str
    display_label: str


MAIN_PARAM_BUFF_KINDS: tuple[MainParamBuffKind, ...] = (
    MainParamBuffKind(
        action_key=ACTION_KEY_RIDGE_GLASS,
        tool_name="Ridge Glass",
        display_label="Ridge Glass",
    ),
    MainParamBuffKind(
        action_key=ACTION_KEY_TRAIL_STRIDERS,
        tool_name="Trail Striders",
        display_label="Trail Striders",
    ),
    MainParamBuffKind(
        action_key=ACTION_KEY_EXPEDITION_DRIVETRAIN,
        tool_name="Expedition Drivetrain",
        display_label="Expedition Drivetrain",
    ),
    MainParamBuffKind(
        action_key=ACTION_KEY_CANYON_THROTTLE,
        tool_name="Canyon Throttle",
        display_label="Canyon Throttle",
    ),
    MainParamBuffKind(
        action_key=ACTION_KEY_OVERLAND_CHASSIS,
        tool_name="Overland Chassis",
        display_label="Overland Chassis",
    ),
    MainParamBuffKind(
        action_key=ACTION_KEY_NOCTURNE_LENS,
        tool_name="Nocturne Lens",
        display_label="Nocturne Lens",
    ),
)

_BY_ACTION_KEY = {k.action_key: k for k in MAIN_PARAM_BUFF_KINDS}
_BY_TOOL_NAME = {k.tool_name: k for k in MAIN_PARAM_BUFF_KINDS}


def is_main_param_buff_action_key(action_key: str) -> bool:
    return action_key in _BY_ACTION_KEY


def is_main_param_buff_tool_name(tool_name: str) -> bool:
    return tool_name in _BY_TOOL_NAME


def kind_for_action_key(action_key: str) -> MainParamBuffKind:
    kind = _BY_ACTION_KEY.get(action_key)
    if kind is None:
        raise ValidationError(f"Unknown main-param buff action_key: {action_key}")
    return kind


def kind_for_tool_name(tool_name: str) -> MainParamBuffKind:
    kind = _BY_TOOL_NAME.get(tool_name)
    if kind is None:
        raise ValidationError(
            "This action is only available for a main-param buff tool"
        )
    return kind


def action_key_for_tool_name(tool_name: str) -> str:
    return kind_for_tool_name(tool_name).action_key


def config_for_action_key(
    action_key: str,
    tool_actions: ToolActionsConfig | None = None,
) -> MainParamBuffActionConfig:
    """Return snapshotted knobs for [action_key] from game config."""
    actions = tool_actions if tool_actions is not None else get_game_config().tool_actions
    try:
        return actions.main_param_buff_config_for(action_key)
    except KeyError as exc:
        raise ValidationError(
            f"Unknown main-param buff action_key: {action_key}"
        ) from exc


__all__ = [
    "GLOBAL_BUFF_ACTION_KEYS",
    "MAIN_PARAM_BUFF_KINDS",
    "MainParamBuffKind",
    "action_key_for_tool_name",
    "config_for_action_key",
    "is_main_param_buff_action_key",
    "is_main_param_buff_tool_name",
    "kind_for_action_key",
    "kind_for_tool_name",
]
