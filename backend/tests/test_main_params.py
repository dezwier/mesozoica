"""Tests for skill main_params resolution."""

from __future__ import annotations

import pytest

from app.core.game_config import LevelModifierEntry, ParamModifier, get_game_config
from app.services.level_service.main_params import (
    apply_modifier,
    resolve_site_discovery_main_params,
)


def test_apply_modifier_ops() -> None:
    assert apply_modifier(0.1, ParamModifier(op="replace", value=0.9)) == 0.9
    assert apply_modifier(0.1, ParamModifier(op="add", value=0.05)) == pytest.approx(
        0.15
    )
    assert apply_modifier(0.1, ParamModifier(op="multiply", value=2.0)) == 0.2


def test_resolve_site_discovery_identity_level() -> None:
    get_game_config.cache_clear()
    cfg = get_game_config().site_discovery
    resolved = resolve_site_discovery_main_params(skill_level=50)
    assert resolved["visibility_distance_m"] == cfg.visibility_distance_m
    assert resolved["discovery_chance"] == cfg.discovery_chance
    assert resolved["max_discovery_speed_kmh"] == cfg.max_discovery_speed_kmh


def test_resolve_site_discovery_tool_replace() -> None:
    get_game_config.cache_clear()
    resolved = resolve_site_discovery_main_params(
        skill_level=1,
        tool_mods={
            "discovery_chance": ParamModifier(op="replace", value=0.9),
        },
    )
    assert resolved["discovery_chance"] == 0.9


def test_resolve_site_discovery_weather_time_visibility() -> None:
    get_game_config.cache_clear()
    cfg = get_game_config().site_discovery
    base = cfg.visibility_distance_m

    day = resolve_site_discovery_main_params(skill_level=1, weather_time="day")
    assert day["visibility_distance_m"] == pytest.approx(base)

    dusk = resolve_site_discovery_main_params(skill_level=1, weather_time="dusk")
    assert dusk["visibility_distance_m"] == pytest.approx(base * 0.8)

    dawn = resolve_site_discovery_main_params(skill_level=1, weather_time="dawn")
    assert dawn["visibility_distance_m"] == pytest.approx(base * 0.8)

    night = resolve_site_discovery_main_params(
        skill_level=1, weather_time="night"
    )
    assert night["visibility_distance_m"] == pytest.approx(base * 0.5)


def test_weather_time_applies_before_tools() -> None:
    get_game_config.cache_clear()
    cfg = get_game_config().site_discovery
    base = cfg.visibility_distance_m
    resolved = resolve_site_discovery_main_params(
        skill_level=1,
        weather_time="night",
        tool_mods={
            "visibility_distance_m": ParamModifier(op="add", value=20),
        },
    )
    # base * 0.5 + 20 (weather before tools)
    assert resolved["visibility_distance_m"] == pytest.approx(base * 0.5 + 20)


def test_level_modifier_entry_shape() -> None:
    entry = LevelModifierEntry(level=10, op="add", value=0.05)
    assert entry.level == 10
    assert apply_modifier(0.1, entry) == pytest.approx(0.15)


def test_modifies_main_params_multi_skill() -> None:
    from app.core.game_config import ModifiesMainParams

    mods = ModifiesMainParams.model_validate(
        {
            "owning": {
                "site_discovery": {
                    "discovery_chance": {"op": "add", "value": 0.05}
                },
                "site_survey": {
                    "fossil_count": {"op": "multiply", "value": 1.1}
                },
            },
            "using": {
                "site_discovery": {
                    "discovery_chance": {"op": "replace", "value": 0.9}
                },
                "fossil_detection": {
                    "visibility_distance_m": {"op": "add", "value": 5}
                },
            },
        }
    )
    assert mods.affects_skill("site_discovery")
    assert mods.affects_skill("site_survey")
    assert mods.affects_skill("fossil_detection")
    assert mods.params_for("owning", "site_discovery")[
        "discovery_chance"
    ].value == pytest.approx(0.05)
    assert mods.params_for("using", "fossil_detection")[
        "visibility_distance_m"
    ].value == 5


def test_modifies_main_params_single_skill_shorthand() -> None:
    from app.core.game_config import ModifiesMainParams

    mods = ModifiesMainParams.model_validate(
        {
            "skill": "site_discovery",
            "using": {"discovery_chance": {"op": "replace", "value": 0.9}},
        }
    )
    assert "discovery_chance" in mods.params_for("using", "site_discovery")
