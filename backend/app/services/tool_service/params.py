"""Tool parameter defaults and effective per-instance values."""

from __future__ import annotations

from typing import Any

from app.core.game_config import get_game_config
from app.models.tool import Tool
from app.models.tool_type import ToolType

_EMPTY: dict[str, Any] = {}


def yaml_defaults_for_tool_type(tool_type: ToolType) -> dict[str, Any]:
    cfg = get_game_config().tool_actions
    by_name = {
        "Aerial Recon": cfg.aerial_recon.model_dump(mode="json"),
        "Aerial Scout": cfg.aerial_scout.model_dump(mode="json"),
        "Geo Compass": cfg.geo_compass.model_dump(mode="json"),
        "Proximity Scanner": cfg.proximity_scanner.model_dump(mode="json"),
        "Site Navigator": cfg.site_navigator.model_dump(mode="json"),
        "Orbit Survey": cfg.orbit_survey.model_dump(mode="json"),
        "Formation Map": cfg.formation_map.model_dump(mode="json"),
    }
    payload = by_name.get(tool_type.name, _EMPTY)
    return dict(payload)


def base_params_for_tool_type(tool_type: ToolType) -> dict[str, Any]:
    configured = tool_type.default_params_json or {}
    if configured:
        return dict(configured)
    return yaml_defaults_for_tool_type(tool_type)


def effective_params_for_instance(tool_type: ToolType, instance: Tool) -> dict[str, Any]:
    payload = base_params_for_tool_type(tool_type)
    payload.update(instance.params_json or {})
    return payload
