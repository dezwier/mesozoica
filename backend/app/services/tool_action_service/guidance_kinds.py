"""Registry of site-guidance tool kinds (compass, proximity, navigator)."""

from __future__ import annotations

from dataclasses import dataclass

from app.core.exceptions import ValidationError
from app.core.game_config import GuidanceActionConfig, ToolActionsConfig, get_game_config
from app.models.tool_session import (
    ACTION_KEY_GEO_COMPASS,
    ACTION_KEY_PROXIMITY_SCANNER,
    ACTION_KEY_SITE_NAVIGATOR,
    GUIDANCE_ACTION_KEYS,
)


@dataclass(frozen=True)
class GuidanceToolKind:
    action_key: str
    tool_name: str
    display_label: str
    show_needle: bool
    show_distance: bool
    has_discovery_boost: bool


GUIDANCE_TOOL_KINDS: tuple[GuidanceToolKind, ...] = (
    GuidanceToolKind(
        action_key=ACTION_KEY_GEO_COMPASS,
        tool_name="Geo Compass",
        display_label="Geo Compass",
        show_needle=True,
        show_distance=False,
        has_discovery_boost=True,
    ),
    GuidanceToolKind(
        action_key=ACTION_KEY_PROXIMITY_SCANNER,
        tool_name="Proximity Scanner",
        display_label="Proximity Scanner",
        show_needle=False,
        show_distance=True,
        has_discovery_boost=False,
    ),
    GuidanceToolKind(
        action_key=ACTION_KEY_SITE_NAVIGATOR,
        tool_name="Site Navigator",
        display_label="Site Navigator",
        show_needle=True,
        show_distance=True,
        has_discovery_boost=True,
    ),
)

_BY_ACTION_KEY = {k.action_key: k for k in GUIDANCE_TOOL_KINDS}
_BY_TOOL_NAME = {k.tool_name: k for k in GUIDANCE_TOOL_KINDS}


def is_guidance_action_key(action_key: str) -> bool:
    return action_key in _BY_ACTION_KEY


def kind_for_action_key(action_key: str) -> GuidanceToolKind:
    kind = _BY_ACTION_KEY.get(action_key)
    if kind is None:
        raise ValidationError(f"Unknown guidance action_key: {action_key}")
    return kind


def kind_for_tool_name(tool_name: str) -> GuidanceToolKind:
    kind = _BY_TOOL_NAME.get(tool_name)
    if kind is None:
        raise ValidationError(
            "This action is only available for Geo Compass, "
            "Proximity Scanner, or Site Navigator"
        )
    return kind


def config_for_action_key(
    action_key: str,
    tool_actions: ToolActionsConfig | None = None,
) -> GuidanceActionConfig:
    actions = tool_actions if tool_actions is not None else get_game_config().tool_actions
    if action_key == ACTION_KEY_GEO_COMPASS:
        return actions.geo_compass
    if action_key == ACTION_KEY_PROXIMITY_SCANNER:
        return actions.proximity_scanner
    if action_key == ACTION_KEY_SITE_NAVIGATOR:
        return actions.site_navigator
    raise ValidationError(f"Unknown guidance action_key: {action_key}")


__all__ = [
    "GUIDANCE_ACTION_KEYS",
    "GUIDANCE_TOOL_KINDS",
    "GuidanceToolKind",
    "config_for_action_key",
    "is_guidance_action_key",
    "kind_for_action_key",
    "kind_for_tool_name",
]
