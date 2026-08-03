"""Resolve skill main_params: base → level → weather_time → weather_type → tools."""

from __future__ import annotations

from typing import Any, Mapping

from app.core.game_config import (
    LevelModifierEntry,
    ParamModifier,
    SiteDiscoveryConfig,
    get_game_config,
)


def apply_modifier(base: float, mod: ParamModifier | LevelModifierEntry) -> float:
    if mod.op == "replace":
        return float(mod.value)
    if mod.op == "add":
        return float(base) + float(mod.value)
    if mod.op == "multiply":
        return float(base) * float(mod.value)
    raise ValueError(f"unknown modifier op: {mod.op}")


def apply_level_modifiers(
    base: float,
    entries: list[LevelModifierEntry] | None,
    *,
    skill_level: int,
) -> float:
    """Apply the highest level entry with ``level <= skill_level`` (identity if none)."""
    if not entries:
        return float(base)
    applicable = [e for e in entries if e.level <= skill_level]
    if not applicable:
        return float(base)
    best = max(applicable, key=lambda e: e.level)
    return apply_modifier(base, best)


def apply_ambient_modifiers(
    base: float,
    entries: list[ParamModifier] | None,
) -> float:
    """Apply all ambient (weather_time / weather_type) entries in order."""
    value = float(base)
    if not entries:
        return value
    for mod in entries:
        value = apply_modifier(value, mod)
    return value


# Back-compat alias used by older call sites / tests.
apply_weather_time_modifiers = apply_ambient_modifiers


def apply_tool_modifier(base: float, mod: ParamModifier | None) -> float:
    if mod is None:
        return float(base)
    return apply_modifier(base, mod)


def resolve_scalar_main_param(
    *,
    base: float,
    level_entries: list[LevelModifierEntry] | None,
    skill_level: int,
    weather_time_entries: list[ParamModifier] | None = None,
    weather_type_entries: list[ParamModifier] | None = None,
    tool_mod: ParamModifier | None = None,
    clamp_unit: bool = False,
) -> float:
    value = apply_level_modifiers(base, level_entries, skill_level=skill_level)
    value = apply_ambient_modifiers(value, weather_time_entries)
    value = apply_ambient_modifiers(value, weather_type_entries)
    value = apply_tool_modifier(value, tool_mod)
    if clamp_unit:
        return min(1.0, max(0.0, value))
    return value


def site_discovery_level_entries(
    cfg: SiteDiscoveryConfig, param: str
) -> list[LevelModifierEntry]:
    return list(cfg.level_modifiers.get(param, []))


def site_discovery_weather_time_entries(
    cfg: SiteDiscoveryConfig,
    param: str,
    weather_time: str | None,
) -> list[ParamModifier]:
    if not weather_time:
        return []
    periods = cfg.weather_time_modifiers.get(param) or {}
    return list(periods.get(weather_time, []))


def site_discovery_weather_type_entries(
    cfg: SiteDiscoveryConfig,
    param: str,
    weather_type: str | None,
) -> list[ParamModifier]:
    if not weather_type:
        return []
    key = "clear" if weather_type == "sunny" else weather_type
    types = cfg.weather_type_modifiers.get(param) or {}
    return list(types.get(key, []))


def resolve_site_discovery_main_params(
    *,
    skill_level: int = 1,
    weather_time: str | None = None,
    weather_type: str | None = None,
    tool_mods: Mapping[str, ParamModifier] | None = None,
) -> dict[str, float]:
    """Effective site_discovery main_params after level + ambient + tool modifiers."""
    cfg = get_game_config().site_discovery
    mods = tool_mods or {}
    return {
        "visibility_distance_m": resolve_scalar_main_param(
            base=cfg.visibility_distance_m,
            level_entries=site_discovery_level_entries(
                cfg, "visibility_distance_m"
            ),
            skill_level=skill_level,
            weather_time_entries=site_discovery_weather_time_entries(
                cfg, "visibility_distance_m", weather_time
            ),
            weather_type_entries=site_discovery_weather_type_entries(
                cfg, "visibility_distance_m", weather_type
            ),
            tool_mod=mods.get("visibility_distance_m"),
        ),
        "discovery_chance": resolve_scalar_main_param(
            base=cfg.discovery_chance,
            level_entries=site_discovery_level_entries(cfg, "discovery_chance"),
            skill_level=skill_level,
            weather_time_entries=site_discovery_weather_time_entries(
                cfg, "discovery_chance", weather_time
            ),
            weather_type_entries=site_discovery_weather_type_entries(
                cfg, "discovery_chance", weather_type
            ),
            tool_mod=mods.get("discovery_chance"),
            clamp_unit=True,
        ),
        "max_discovery_speed_kmh": resolve_scalar_main_param(
            base=cfg.max_discovery_speed_kmh,
            level_entries=site_discovery_level_entries(
                cfg, "max_discovery_speed_kmh"
            ),
            skill_level=skill_level,
            weather_time_entries=site_discovery_weather_time_entries(
                cfg, "max_discovery_speed_kmh", weather_time
            ),
            weather_type_entries=site_discovery_weather_type_entries(
                cfg, "max_discovery_speed_kmh", weather_type
            ),
            tool_mod=mods.get("max_discovery_speed_kmh"),
        ),
    }


def _looks_like_param_modifier(value: object) -> bool:
    return isinstance(value, dict) and "op" in value and "value" in value


def tool_mods_from_session_params(
    params: Mapping[str, Any] | None,
    *,
    when: str = "using",
    skill_id: str = "site_discovery",
) -> dict[str, ParamModifier]:
    """Rebuild tool ParamModifiers for one skill from a session params snapshot.

    Supports multi-skill ``modifies_main_params``::

        { using: { site_discovery: { discovery_chance: { op, value } } } }

    Also accepts single-skill shorthand / legacy ``when``+``params``, and a
    snapshotted top-level ``discovery_chance`` replace for site_discovery.
    """
    if not params:
        return {}
    out: dict[str, ParamModifier] = {}
    raw_mods = params.get("modifies_main_params")
    if isinstance(raw_mods, dict):
        bucket = raw_mods.get(when)
        # Legacy: when + params (param map, not skill map)
        if not isinstance(bucket, dict):
            legacy_when = str(raw_mods.get("when") or "using").strip().lower()
            if legacy_when == when and isinstance(raw_mods.get("params"), dict):
                bucket = {raw_mods.get("skill") or skill_id: raw_mods["params"]}
        if isinstance(bucket, dict):
            skill_params = bucket.get(skill_id)
            # Shorthand: bucket is a param map for one skill
            if skill_params is None and all(
                _looks_like_param_modifier(v) for v in bucket.values()
            ):
                legacy_skill = str(raw_mods.get("skill") or skill_id)
                if legacy_skill == skill_id:
                    skill_params = bucket
            if isinstance(skill_params, dict):
                for key, entry in skill_params.items():
                    if _looks_like_param_modifier(entry):
                        out[str(key)] = ParamModifier.model_validate(entry)
    if (
        when == "using"
        and skill_id == "site_discovery"
        and params.get("discovery_chance") is not None
    ):
        out.setdefault(
            "discovery_chance",
            ParamModifier(op="replace", value=float(params["discovery_chance"])),
        )
    return out
