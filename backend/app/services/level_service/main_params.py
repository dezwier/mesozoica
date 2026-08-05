"""Resolve skill main_params: base → level → weather_time → weather_type → tools."""

from __future__ import annotations

from typing import Any, Mapping

from app.core.game_config import (
    FieldSurveyConfig,
    LevelModifierEntry,
    ParamModifier,
    SkillStubConfig,
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
    """Apply level keyframes with linear value interpolation between them.

    Below the first keyframe → identity. At/above the last → that entry.
    Between two keyframes → lerp ``value`` (uses the lower keyframe's ``op``).
    """
    if not entries:
        return float(base)
    ordered = sorted(entries, key=lambda e: e.level)
    if skill_level < ordered[0].level:
        return float(base)
    if skill_level >= ordered[-1].level:
        return apply_modifier(base, ordered[-1])
    for lo, hi in zip(ordered, ordered[1:]):
        if skill_level > hi.level:
            continue
        if skill_level == lo.level or hi.level == lo.level:
            return apply_modifier(base, lo)
        t = (skill_level - lo.level) / (hi.level - lo.level)
        value = lo.value + t * (hi.value - lo.value)
        return apply_modifier(
            base,
            LevelModifierEntry(level=skill_level, op=lo.op, value=value),
        )
    return float(base)


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


def _field_survey_level_entries(
    cfg: FieldSurveyConfig, param: str
) -> list[LevelModifierEntry]:
    return list(cfg.level_modifiers.get(param, []))


def _field_survey_weather_time_entries(
    cfg: FieldSurveyConfig,
    param: str,
    weather_time: str | None,
) -> list[ParamModifier]:
    if not weather_time:
        return []
    periods = cfg.weather_time_modifiers.get(param) or {}
    return list(periods.get(weather_time, []))


def _field_survey_weather_type_entries(
    cfg: FieldSurveyConfig,
    param: str,
    weather_type: str | None,
) -> list[ParamModifier]:
    if not weather_type:
        return []
    key = "clear" if weather_type == "sunny" else weather_type
    types = cfg.weather_type_modifiers.get(param) or {}
    return list(types.get(key, []))


def _resolve_field_survey_param(
    cfg: FieldSurveyConfig,
    param: str,
    *,
    base: float,
    skill_level: int,
    weather_time: str | None,
    weather_type: str | None,
    tool_mods: Mapping[str, ParamModifier],
    clamp_unit: bool = False,
) -> float:
    return resolve_scalar_main_param(
        base=base,
        level_entries=_field_survey_level_entries(cfg, param),
        skill_level=skill_level,
        weather_time_entries=_field_survey_weather_time_entries(
            cfg, param, weather_time
        ),
        weather_type_entries=_field_survey_weather_type_entries(
            cfg, param, weather_type
        ),
        tool_mod=tool_mods.get(param),
        clamp_unit=clamp_unit,
    )


def resolve_field_survey_main_params(
    *,
    skill_level: int = 1,
    weather_time: str | None = None,
    weather_type: str | None = None,
    tool_mods: Mapping[str, ParamModifier] | None = None,
) -> dict[str, float]:
    """Effective field_survey main_params after level + ambient + tool modifiers."""
    cfg = get_game_config().field_survey
    mods = tool_mods or {}
    mp = cfg.main_params

    def _resolve(param: str, *, base: float, clamp_unit: bool = False) -> float:
        return _resolve_field_survey_param(
            cfg,
            param,
            base=base,
            skill_level=skill_level,
            weather_time=weather_time,
            weather_type=weather_type,
            tool_mods=mods,
            clamp_unit=clamp_unit,
        )

    return {
        "discovery_distance_m": _resolve(
            "discovery_distance_m", base=float(mp.discovery_distance_m)
        ),
        "discovery_chance": _resolve(
            "discovery_chance", base=float(mp.discovery_chance), clamp_unit=True
        ),
        "discovery_max_speed_kmh": _resolve(
            "discovery_max_speed_kmh", base=float(mp.discovery_max_speed_kmh)
        ),
        "discover_site_xp": _resolve(
            "discover_site_xp", base=float(mp.discover_site_xp)
        ),
        "discover_site_as_first_xp": _resolve(
            "discover_site_as_first_xp", base=float(mp.discover_site_as_first_xp)
        ),
        "explore_100m_actively_xp": _resolve("explore_100m_actively_xp", base=float(mp.explore_100m_actively_xp)),
        "explore_100m_passively_xp": _resolve("explore_100m_passively_xp", base=float(mp.explore_100m_passively_xp)),
        "documentation_accuracy": _resolve(
            "documentation_accuracy",
            base=float(mp.documentation_accuracy),
            clamp_unit=True,
        ),
        "rival_discovery_chance": _resolve(
            "rival_discovery_chance", base=float(mp.rival_discovery_chance)
        ),
        "documentation_distance_m": _resolve(
            "documentation_distance_m", base=float(mp.documentation_distance_m)
        ),
        "disguise_of_site_xp": _resolve(
            "disguise_of_site_xp",
            base=float(mp.disguise_of_site_xp),
        ),
        "document_progress_xp": _resolve(
            "document_progress_xp",
            base=float(mp.document_progress_xp),
        ),
        "document_site_xp": _resolve(
            "document_site_xp",
            base=float(mp.document_site_xp),
        ),
        "document_site_as_first_xp": _resolve(
            "document_site_as_first_xp",
            base=float(mp.document_site_as_first_xp),
        ),
        "identify_site_xp": _resolve(
            "identify_site_xp",
            base=float(mp.identify_site_xp),
        ),
    }


# Back-compat: discovery-only / stewardship-only slices of field_survey.
def resolve_site_discovery_main_params(
    *,
    skill_level: int = 1,
    weather_time: str | None = None,
    weather_type: str | None = None,
    tool_mods: Mapping[str, ParamModifier] | None = None,
) -> dict[str, float]:
    full = resolve_field_survey_main_params(
        skill_level=skill_level,
        weather_time=weather_time,
        weather_type=weather_type,
        tool_mods=tool_mods,
    )
    keys = (
        "discovery_distance_m",
        "discovery_chance",
        "discovery_max_speed_kmh",
        "discover_site_xp",
        "discover_site_as_first_xp",
        "explore_100m_actively_xp",
        "explore_100m_passively_xp",
    )
    return {k: full[k] for k in keys}


def resolve_site_stewardship_main_params(
    *,
    skill_level: int = 1,
    weather_time: str | None = None,
    weather_type: str | None = None,
    tool_mods: Mapping[str, ParamModifier] | None = None,
) -> dict[str, float]:
    full = resolve_field_survey_main_params(
        skill_level=skill_level,
        weather_time=weather_time,
        weather_type=weather_type,
        tool_mods=tool_mods,
    )
    keys = (
        "documentation_accuracy",
        "rival_discovery_chance",
        "documentation_distance_m",
        "disguise_of_site_xp",
        "document_progress_xp",
        "document_site_xp",
        "document_site_as_first_xp",
        "identify_site_xp",
    )
    return {k: full[k] for k in keys}


# Aliases used by older imports/tests.
site_discovery_level_entries = _field_survey_level_entries
site_discovery_weather_time_entries = _field_survey_weather_time_entries
site_discovery_weather_type_entries = _field_survey_weather_type_entries


def _stub_level_entries(
    cfg: SkillStubConfig, param: str
) -> list[LevelModifierEntry]:
    return list(cfg.level_modifiers.get(param, []))


def _stub_weather_time_entries(
    cfg: SkillStubConfig,
    param: str,
    weather_time: str | None,
) -> list[ParamModifier]:
    if not weather_time:
        return []
    periods = cfg.weather_time_modifiers.get(param) or {}
    return list(periods.get(weather_time, []))


def _stub_weather_type_entries(
    cfg: SkillStubConfig,
    param: str,
    weather_type: str | None,
) -> list[ParamModifier]:
    if not weather_type:
        return []
    key = "clear" if weather_type == "sunny" else weather_type
    types = cfg.weather_type_modifiers.get(param) or {}
    return list(types.get(key, []))


def resolve_bone_quarry_main_params(
    *,
    skill_level: int = 1,
    weather_time: str | None = None,
    weather_type: str | None = None,
    tool_mods: Mapping[str, ParamModifier] | None = None,
) -> dict[str, float]:
    """Effective bone_quarry scalar main_params after modifiers."""
    cfg = get_game_config().bone_quarry
    mods = tool_mods or {}
    raw = cfg.main_params.get("locate_fossil_in_situ_xp", 20)
    base = float(raw)
    return {
        "locate_fossil_in_situ_xp": resolve_scalar_main_param(
            base=base,
            level_entries=_stub_level_entries(cfg, "locate_fossil_in_situ_xp"),
            skill_level=skill_level,
            weather_time_entries=_stub_weather_time_entries(
                cfg, "locate_fossil_in_situ_xp", weather_time
            ),
            weather_type_entries=_stub_weather_type_entries(
                cfg, "locate_fossil_in_situ_xp", weather_type
            ),
            tool_mod=mods.get("locate_fossil_in_situ_xp"),
        ),
    }


# Back-compat alias.
resolve_fossil_detection_main_params = resolve_bone_quarry_main_params


def _looks_like_param_modifier(value: object) -> bool:
    return isinstance(value, dict) and "op" in value and "value" in value


def tool_mods_from_session_params(
    params: Mapping[str, Any] | None,
    *,
    when: str = "using",
    skill_id: str = "field_survey",
) -> dict[str, ParamModifier]:
    """Rebuild tool ParamModifiers for one skill from a session params snapshot.

    Supports multi-skill ``modifies_main_params``::

        { using: { field_survey: { discovery_chance: { op, value } } } }

    Also accepts single-skill shorthand / legacy ``when``+``params``, and a
    snapshotted top-level ``discovery_chance`` replace for field_survey.
    Legacy skill ids ``site_discovery`` / ``site_stewardship`` are treated as
    ``field_survey``.
    """
    if not params:
        return {}
    aliases = {
        "site_discovery": "field_survey",
        "site_stewardship": "field_survey",
        "site_clearing": "field_survey",
        "fossil_detection": "bone_quarry",
    }
    canonical = aliases.get(skill_id, skill_id)
    out: dict[str, ParamModifier] = {}
    raw_mods = params.get("modifies_main_params")
    if isinstance(raw_mods, dict):
        bucket = raw_mods.get(when)
        # Legacy: when + params (param map, not skill map)
        if not isinstance(bucket, dict):
            legacy_when = str(raw_mods.get("when") or "using").strip().lower()
            if legacy_when == when and isinstance(raw_mods.get("params"), dict):
                raw_skill = str(raw_mods.get("skill") or skill_id)
                bucket = {aliases.get(raw_skill, raw_skill): raw_mods["params"]}
        if isinstance(bucket, dict):
            skill_params = bucket.get(canonical)
            if skill_params is None:
                for legacy, target in aliases.items():
                    if target == canonical and legacy in bucket:
                        skill_params = bucket[legacy]
                        break
            # Shorthand: bucket is a param map for one skill
            if skill_params is None and all(
                _looks_like_param_modifier(v) for v in bucket.values()
            ):
                legacy_skill = str(raw_mods.get("skill") or skill_id)
                if aliases.get(legacy_skill, legacy_skill) == canonical:
                    skill_params = bucket
            if isinstance(skill_params, dict):
                for key, entry in skill_params.items():
                    if _looks_like_param_modifier(entry):
                        out[str(key)] = ParamModifier.model_validate(entry)
    if (
        when == "using"
        and canonical == "field_survey"
        and params.get("discovery_chance") is not None
    ):
        out.setdefault(
            "discovery_chance",
            ParamModifier(op="replace", value=float(params["discovery_chance"])),
        )
    return out
