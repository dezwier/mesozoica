"""Registry of global main-param buff tools (Ridge Glass, Drivetrain, Nocturne, …)."""

from __future__ import annotations

from dataclasses import dataclass

from app.core.exceptions import ValidationError
from app.core.game_config import (
    MainParamBuffActionConfig,
    ToolActionsConfig,
    get_game_config,
)
from app.models.tool_session import (
    ACTION_KEY_EXPEDITION_DRIVETRAIN,
    ACTION_KEY_NOCTURNE_LENS,
    ACTION_KEY_RIDGE_GLASS,
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
        action_key=ACTION_KEY_EXPEDITION_DRIVETRAIN,
        tool_name="Expedition Drivetrain",
        display_label="Expedition Drivetrain",
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
    if action_key == ACTION_KEY_RIDGE_GLASS:
        return actions.ridge_glass
    if action_key == ACTION_KEY_EXPEDITION_DRIVETRAIN:
        return actions.expedition_drivetrain
    if action_key == ACTION_KEY_NOCTURNE_LENS:
        return actions.nocturne_lens
    raise ValidationError(f"Unknown main-param buff action_key: {action_key}")


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
