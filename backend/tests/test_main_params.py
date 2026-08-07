"""Tests for skill main_params resolution.

Weather / level multiplier *amounts* come from YAML — assert resolution
behavior against the loaded config rather than hardcoding knob values.
"""

from __future__ import annotations

import pytest

from app.core.game_config import LevelModifierEntry, ParamModifier, get_game_config
from app.services.level_service.main_params import (
    apply_ambient_modifiers,
    apply_level_modifiers,
    apply_modifier,
    resolve_fossil_detection_main_params,
    resolve_site_discovery_main_params,
    resolve_site_stewardship_main_params,
)


def test_apply_modifier_ops() -> None:
    assert apply_modifier(0.1, ParamModifier(op="replace", value=0.9)) == 0.9
    assert apply_modifier(0.1, ParamModifier(op="add", value=0.05)) == pytest.approx(
        0.15
    )
    assert apply_modifier(0.1, ParamModifier(op="multiply", value=2.0)) == 0.2


def test_apply_level_modifiers_lerps_between_endpoints() -> None:
    entries = [
        LevelModifierEntry(level=1, op="multiply", value=1.0),
        LevelModifierEntry(level=99, op="multiply", value=0.5),
    ]
    assert apply_level_modifiers(1.0, entries, skill_level=1) == pytest.approx(1.0)
    assert apply_level_modifiers(1.0, entries, skill_level=50) == pytest.approx(0.75)
    assert apply_level_modifiers(1.0, entries, skill_level=99) == pytest.approx(0.5)
    # Below first keyframe → identity.
    assert apply_level_modifiers(1.0, entries, skill_level=0) == pytest.approx(1.0)


def _expected_from_level(
    base: float,
    entries: list[LevelModifierEntry] | None,
    *,
    skill_level: int,
    clamp_unit: bool = False,
) -> float:
    value = apply_level_modifiers(base, entries, skill_level=skill_level)
    if clamp_unit:
        return min(1.0, max(0.0, value))
    return value


def _expected_ambient(
    base: float,
    entries: list[ParamModifier] | None,
) -> float:
    return apply_ambient_modifiers(base, entries)


def test_field_survey_estimation_and_rival_follow_level_modifiers() -> None:
    get_game_config.cache_clear()
    cfg = get_game_config().site_stewardship
    mp = cfg.main_params
    for level in (1, 50, 99):
        resolved = resolve_site_stewardship_main_params(skill_level=level)
        assert resolved["document_accuracy"] == pytest.approx(
            _expected_from_level(
                float(mp.document_accuracy),
                list(cfg.level_modifiers.get("document_accuracy", [])),
                skill_level=level,
                clamp_unit=True,
            )
        )
        assert resolved["rival_discovery_chance"] == pytest.approx(
            _expected_from_level(
                float(mp.rival_discovery_chance),
                list(cfg.level_modifiers.get("rival_discovery_chance", [])),
                skill_level=level,
            )
        )


def test_resolve_site_discovery_reach_scales_with_level() -> None:
    get_game_config.cache_clear()
    cfg = get_game_config().site_discovery
    stew = get_game_config().site_stewardship
    for level in (1, 50, 99):
        resolved = resolve_site_discovery_main_params(skill_level=level)
        assert resolved["visibility_distance_m"] == pytest.approx(
            _expected_from_level(
                float(cfg.visibility_distance_m),
                list(cfg.level_modifiers.get("visibility_distance_m", [])),
                skill_level=level,
            )
        )
        assert resolved["discovery_chance"] == pytest.approx(
            _expected_from_level(
                float(cfg.discovery_chance),
                list(cfg.level_modifiers.get("discovery_chance", [])),
                skill_level=level,
                clamp_unit=True,
            )
        )
        # Empty level lists → identity for XP / speed.
        assert resolved["discover_site_xp"] == pytest.approx(cfg.discover_site_xp)
        assert resolved["discover_site_as_first_xp"] == pytest.approx(
            cfg.discover_site_as_first_xp
        )
        assert resolved["explore_100m_actively_xp"] == pytest.approx(
            cfg.explore_100m_actively_xp
        )
        assert resolved["explore_100m_passively_xp"] == pytest.approx(
            cfg.explore_100m_passively_xp
        )
        assert resolved["discovery_max_speed_kmh"] == pytest.approx(
            cfg.discovery_max_speed_kmh
        )

    stew99 = resolve_site_stewardship_main_params(skill_level=99)
    assert stew99["visibility_distance_m"] == pytest.approx(
        _expected_from_level(
            float(stew.visibility_distance_m),
            list(stew.level_modifiers.get("visibility_distance_m", [])),
            skill_level=99,
        )
    )


def test_resolve_site_discovery_tool_replace() -> None:
    get_game_config.cache_clear()
    resolved = resolve_site_discovery_main_params(
        skill_level=1,
        tool_mods={
            "discovery_chance": ParamModifier(op="replace", value=0.9),
        },
    )
    assert resolved["discovery_chance"] == 0.9


def test_resolve_discover_site_xp_weather_time() -> None:
    get_game_config.cache_clear()
    cfg = get_game_config().site_discovery
    base = float(cfg.discover_site_xp)
    mods = cfg.weather_time_modifiers.get("discover_site_xp") or {}

    for period in ("day", "golden_hour", "dawn", "dusk", "night"):
        resolved = resolve_site_discovery_main_params(
            skill_level=1, weather_time=period
        )
        assert resolved["discover_site_xp"] == pytest.approx(
            _expected_ambient(base, list(mods.get(period, [])))
        )
        # discover_site_as_first_xp has no weather_time modifiers.
        assert resolved["discover_site_as_first_xp"] == pytest.approx(
            cfg.discover_site_as_first_xp
        )
        active_xp_mods = cfg.weather_time_modifiers.get("explore_100m_actively_xp") or {}
        assert resolved["explore_100m_actively_xp"] == pytest.approx(
            _expected_ambient(
                cfg.explore_100m_actively_xp,
                list(active_xp_mods.get(period, [])),
            )
        )
        assert resolved["explore_100m_passively_xp"] == pytest.approx(
            cfg.explore_100m_passively_xp
        )


def test_resolve_fossil_detection_xp_weather_time() -> None:
    get_game_config.cache_clear()
    cfg = get_game_config().fossil_detection
    base = float(cfg.main_params["locate_fossil_in_situ_xp"])
    mods = cfg.weather_time_modifiers.get("locate_fossil_in_situ_xp") or {}

    for period in ("day", "night", "golden_hour", "dawn", "dusk"):
        resolved = resolve_fossil_detection_main_params(
            skill_level=1, weather_time=period
        )
        assert resolved["locate_fossil_in_situ_xp"] == pytest.approx(
            _expected_ambient(base, list(mods.get(period, [])))
        )


def test_resolve_site_discovery_weather_time_visibility() -> None:
    get_game_config.cache_clear()
    cfg = get_game_config().site_discovery
    base = float(cfg.visibility_distance_m)
    chance = float(cfg.discovery_chance)
    dist_mods = cfg.weather_time_modifiers.get("visibility_distance_m") or {}
    chance_mods = cfg.weather_time_modifiers.get("discovery_chance") or {}

    for period in ("day", "golden_hour", "dawn", "dusk", "night"):
        resolved = resolve_site_discovery_main_params(
            skill_level=1, weather_time=period
        )
        assert resolved["visibility_distance_m"] == pytest.approx(
            _expected_ambient(base, list(dist_mods.get(period, [])))
        )
        assert resolved["discovery_chance"] == pytest.approx(
            min(
                1.0,
                max(
                    0.0,
                    _expected_ambient(chance, list(chance_mods.get(period, []))),
                ),
            )
        )


def test_resolve_site_stewardship_weather_time_mirrors_config() -> None:
    get_game_config.cache_clear()
    cfg = get_game_config().site_stewardship
    mp = cfg.main_params
    vis = float(mp.visibility_distance_m)
    speed = float(mp.document_speed)
    vis_mods = cfg.weather_time_modifiers.get("visibility_distance_m") or {}
    speed_mods = cfg.weather_time_modifiers.get("document_speed") or {}

    for period in ("day", "golden_hour", "dawn", "dusk", "night"):
        resolved = resolve_site_stewardship_main_params(
            skill_level=1, weather_time=period
        )
        assert resolved["visibility_distance_m"] == pytest.approx(
            _expected_ambient(vis, list(vis_mods.get(period, [])))
        )
        assert resolved["document_speed"] == pytest.approx(
            _expected_ambient(speed, list(speed_mods.get(period, [])))
        )


def test_resolve_site_discovery_weather_type_visibility() -> None:
    get_game_config.cache_clear()
    cfg = get_game_config().site_discovery
    base = float(cfg.visibility_distance_m)
    chance = float(cfg.discovery_chance)
    dist_mods = cfg.weather_type_modifiers.get("visibility_distance_m") or {}
    chance_mods = cfg.weather_type_modifiers.get("discovery_chance") or {}

    for weather_type in (
        "clear",
        "cloudy",
        "overcast",
        "drizzle",
        "rain",
        "hail",
        "fog",
        "thunderstorm",
        "snow",
    ):
        resolved = resolve_site_discovery_main_params(
            skill_level=1, weather_type=weather_type
        )
        assert resolved["visibility_distance_m"] == pytest.approx(
            _expected_ambient(base, list(dist_mods.get(weather_type, [])))
        )
        assert resolved["discovery_chance"] == pytest.approx(
            min(
                1.0,
                max(
                    0.0,
                    _expected_ambient(
                        chance, list(chance_mods.get(weather_type, []))
                    ),
                ),
            )
        )


def test_weather_time_and_type_stack_before_tools() -> None:
    get_game_config.cache_clear()
    cfg = get_game_config().site_discovery
    base = float(cfg.visibility_distance_m)
    time_mods = list(
        (cfg.weather_time_modifiers.get("visibility_distance_m") or {}).get(
            "night", []
        )
    )
    type_mods = list(
        (cfg.weather_type_modifiers.get("visibility_distance_m") or {}).get(
            "thunderstorm", []
        )
    )
    expected = _expected_ambient(base, time_mods)
    expected = _expected_ambient(expected, type_mods)
    expected = apply_modifier(expected, ParamModifier(op="add", value=20))

    resolved = resolve_site_discovery_main_params(
        skill_level=1,
        weather_time="night",
        weather_type="thunderstorm",
        tool_mods={
            "visibility_distance_m": ParamModifier(op="add", value=20),
        },
    )
    assert resolved["visibility_distance_m"] == pytest.approx(expected)


def test_level_modifier_entry_shape() -> None:
    entry = LevelModifierEntry(level=10, op="add", value=0.05)
    assert entry.level == 10
    assert apply_modifier(0.1, entry) == pytest.approx(0.15)


def test_modifies_main_params_multi_skill() -> None:
    from app.core.game_config import ModifiesMainParams

    mods = ModifiesMainParams.model_validate(
        {
            "owning": {
                "field_survey": {
                    "discovery_chance": {"op": "add", "value": 0.05},
                    "document_accuracy": {"op": "add", "value": 0.1},
                },
            },
            "using": {
                "field_survey": {
                    "discovery_chance": {"op": "replace", "value": 0.9}
                },
                "bone_quarry": {
                    "visibility_distance_m": {"op": "add", "value": 5}
                },
            },
        }
    )
    assert mods.affects_skill("field_survey")
    assert mods.affects_skill("bone_quarry")
    assert mods.params_for("owning", "field_survey")[
        "discovery_chance"
    ].value == pytest.approx(0.05)
    assert mods.params_for("owning", "field_survey")[
        "document_accuracy"
    ].value == pytest.approx(0.1)
    assert mods.params_for("using", "bone_quarry")[
        "visibility_distance_m"
    ].value == 5


def test_modifies_main_params_single_skill_shorthand() -> None:
    from app.core.game_config import ModifiesMainParams

    mods = ModifiesMainParams.model_validate(
        {
            "skill": "field_survey",
            "using": {"discovery_chance": {"op": "replace", "value": 0.9}},
        }
    )
    assert "discovery_chance" in mods.params_for("using", "field_survey")
