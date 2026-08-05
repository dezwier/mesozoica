"""Tests for skill main_params resolution."""

from __future__ import annotations

import pytest

from app.core.game_config import LevelModifierEntry, ParamModifier, get_game_config
from app.services.level_service.main_params import (
    apply_level_modifiers,
    apply_modifier,
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


def test_field_survey_estimation_and_rival_from_sparse_keyframes() -> None:
    get_game_config.cache_clear()
    l1 = resolve_site_stewardship_main_params(skill_level=1)
    l50 = resolve_site_stewardship_main_params(skill_level=50)
    l99 = resolve_site_stewardship_main_params(skill_level=99)
    assert l1["documentation_accuracy"] == pytest.approx(0.01)
    assert l50["documentation_accuracy"] == pytest.approx(0.50)
    assert l99["documentation_accuracy"] == pytest.approx(0.99)
    assert l1["rival_discovery_chance"] == pytest.approx(1.0)
    assert l50["rival_discovery_chance"] == pytest.approx(0.75)
    assert l99["rival_discovery_chance"] == pytest.approx(0.5)


def test_resolve_site_discovery_reach_scales_with_level() -> None:
    get_game_config.cache_clear()
    cfg = get_game_config().site_discovery
    l1 = resolve_site_discovery_main_params(skill_level=1)
    l50 = resolve_site_discovery_main_params(skill_level=50)
    l99 = resolve_site_discovery_main_params(skill_level=99)
    # ×1.0 at L1 → ×1.5 at L99 (lerp; L50 ≈ ×1.25).
    assert l1["discovery_distance_m"] == pytest.approx(cfg.discovery_distance_m)
    assert l1["discovery_chance"] == pytest.approx(cfg.discovery_chance)
    assert l50["discovery_distance_m"] == pytest.approx(cfg.discovery_distance_m * 1.25)
    assert l50["discovery_chance"] == pytest.approx(cfg.discovery_chance * 1.25)
    assert l99["discovery_distance_m"] == pytest.approx(cfg.discovery_distance_m * 1.5)
    assert l99["discovery_chance"] == pytest.approx(cfg.discovery_chance * 1.5)
    # XP params stay identity.
    assert l50["discover_site_xp"] == cfg.discover_site_xp
    assert l50["discover_site_as_first_xp"] == cfg.discover_site_as_first_xp
    assert l50["explore_100m_actively_xp"] == cfg.explore_100m_actively_xp
    assert l50["explore_100m_passively_xp"] == cfg.explore_100m_passively_xp
    assert l50["discovery_max_speed_kmh"] == cfg.discovery_max_speed_kmh

    stew = resolve_site_stewardship_main_params(skill_level=99)
    assert stew["documentation_distance_m"] == pytest.approx(
        get_game_config().site_stewardship.documentation_distance_m * 1.5
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
    base = cfg.discover_site_xp

    day = resolve_site_discovery_main_params(skill_level=1, weather_time="day")
    assert day["discover_site_xp"] == pytest.approx(base)

    golden = resolve_site_discovery_main_params(
        skill_level=1, weather_time="golden_hour"
    )
    assert golden["discover_site_xp"] == pytest.approx(base * 1.3)

    dusk = resolve_site_discovery_main_params(skill_level=1, weather_time="dusk")
    assert dusk["discover_site_xp"] == pytest.approx(base * 1.1)

    dawn = resolve_site_discovery_main_params(skill_level=1, weather_time="dawn")
    assert dawn["discover_site_xp"] == pytest.approx(base * 1.1)

    night = resolve_site_discovery_main_params(
        skill_level=1, weather_time="night"
    )
    assert night["discover_site_xp"] == pytest.approx(base * 1.2)

    # discover_site_as_first / walk km XP are time-invariant.
    for period in ("day", "golden_hour", "dawn", "dusk", "night"):
        resolved = resolve_site_discovery_main_params(
            skill_level=1, weather_time=period
        )
        assert resolved["discover_site_as_first_xp"] == pytest.approx(cfg.discover_site_as_first_xp)
        assert resolved["explore_100m_actively_xp"] == pytest.approx(cfg.explore_100m_actively_xp)
        assert resolved["explore_100m_passively_xp"] == pytest.approx(cfg.explore_100m_passively_xp)


def test_resolve_fossil_detection_xp_weather_time() -> None:
    get_game_config.cache_clear()
    from app.services.level_service.main_params import (
        resolve_fossil_detection_main_params,
    )

    base = float(
        get_game_config().fossil_detection.main_params["locate_fossil_in_situ_xp"]
    )
    day = resolve_fossil_detection_main_params(skill_level=1, weather_time="day")
    assert day["locate_fossil_in_situ_xp"] == pytest.approx(base)
    night = resolve_fossil_detection_main_params(
        skill_level=1, weather_time="night"
    )
    assert night["locate_fossil_in_situ_xp"] == pytest.approx(base * 1.2)


def test_resolve_site_discovery_weather_time_visibility() -> None:
    get_game_config.cache_clear()
    cfg = get_game_config().site_discovery
    base = cfg.discovery_distance_m

    day = resolve_site_discovery_main_params(skill_level=1, weather_time="day")
    assert day["discovery_distance_m"] == pytest.approx(base * 1.1)
    assert day["discovery_chance"] == pytest.approx(cfg.discovery_chance * 1.1)

    golden = resolve_site_discovery_main_params(
        skill_level=1, weather_time="golden_hour"
    )
    assert golden["discovery_distance_m"] == pytest.approx(base * 1.3)
    assert golden["discovery_chance"] == pytest.approx(cfg.discovery_chance * 1.3)

    dusk = resolve_site_discovery_main_params(skill_level=1, weather_time="dusk")
    assert dusk["discovery_distance_m"] == pytest.approx(base)

    dawn = resolve_site_discovery_main_params(skill_level=1, weather_time="dawn")
    assert dawn["discovery_distance_m"] == pytest.approx(base)

    night = resolve_site_discovery_main_params(
        skill_level=1, weather_time="night"
    )
    assert night["discovery_distance_m"] == pytest.approx(base * 0.6)
    assert night["discovery_chance"] == pytest.approx(cfg.discovery_chance * 0.6)


def test_resolve_site_stewardship_weather_time_mirrors_discovery() -> None:
    get_game_config.cache_clear()
    from app.services.level_service.main_params import (
        resolve_site_stewardship_main_params,
    )

    cfg = get_game_config().site_stewardship.main_params
    vis = float(cfg.documentation_distance_m)
    xp = float(cfg.document_progress_xp)

    day = resolve_site_stewardship_main_params(skill_level=1, weather_time="day")
    assert day["documentation_distance_m"] == pytest.approx(vis * 1.1)
    assert day["document_progress_xp"] == pytest.approx(xp)

    golden = resolve_site_stewardship_main_params(
        skill_level=1, weather_time="golden_hour"
    )
    assert golden["documentation_distance_m"] == pytest.approx(vis * 1.3)
    assert golden["document_progress_xp"] == pytest.approx(xp * 1.3)

    dusk = resolve_site_stewardship_main_params(
        skill_level=1, weather_time="dusk"
    )
    assert dusk["documentation_distance_m"] == pytest.approx(vis)
    assert dusk["document_progress_xp"] == pytest.approx(xp * 1.1)

    night = resolve_site_stewardship_main_params(
        skill_level=1, weather_time="night"
    )
    assert night["documentation_distance_m"] == pytest.approx(vis * 0.6)
    assert night["document_progress_xp"] == pytest.approx(xp * 1.2)


def test_resolve_site_discovery_weather_type_visibility() -> None:
    get_game_config.cache_clear()
    cfg = get_game_config().site_discovery
    base = cfg.discovery_distance_m
    chance = cfg.discovery_chance

    clear = resolve_site_discovery_main_params(
        skill_level=1, weather_type="clear"
    )
    assert clear["discovery_distance_m"] == pytest.approx(base * 1.1)
    assert clear["discovery_chance"] == pytest.approx(chance * 1.1)

    cloudy = resolve_site_discovery_main_params(
        skill_level=1, weather_type="cloudy"
    )
    assert cloudy["discovery_distance_m"] == pytest.approx(base * 1.05)

    overcast = resolve_site_discovery_main_params(
        skill_level=1, weather_type="overcast"
    )
    assert overcast["discovery_distance_m"] == pytest.approx(base)

    drizzle = resolve_site_discovery_main_params(
        skill_level=1, weather_type="drizzle"
    )
    assert drizzle["discovery_distance_m"] == pytest.approx(base * 0.95)

    rain = resolve_site_discovery_main_params(skill_level=1, weather_type="rain")
    assert rain["discovery_distance_m"] == pytest.approx(base * 0.9)

    hail = resolve_site_discovery_main_params(skill_level=1, weather_type="hail")
    assert hail["discovery_distance_m"] == pytest.approx(base * 0.9)

    fog = resolve_site_discovery_main_params(skill_level=1, weather_type="fog")
    assert fog["discovery_distance_m"] == pytest.approx(base * 0.85)

    storm = resolve_site_discovery_main_params(
        skill_level=1, weather_type="thunderstorm"
    )
    assert storm["discovery_distance_m"] == pytest.approx(base * 0.8)


def test_weather_time_and_type_stack_before_tools() -> None:
    get_game_config.cache_clear()
    cfg = get_game_config().site_discovery
    base = cfg.discovery_distance_m
    resolved = resolve_site_discovery_main_params(
        skill_level=1,
        weather_time="night",
        weather_type="thunderstorm",
        tool_mods={
            "discovery_distance_m": ParamModifier(op="add", value=20),
        },
    )
    # base * 0.6 * 0.8 + 20 (ambient before tools)
    assert resolved["discovery_distance_m"] == pytest.approx(base * 0.6 * 0.8 + 20)


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
                    "documentation_accuracy": {"op": "add", "value": 0.1},
                },
            },
            "using": {
                "field_survey": {
                    "discovery_chance": {"op": "replace", "value": 0.9}
                },
                "bone_quarry": {
                    "discovery_distance_m": {"op": "add", "value": 5}
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
        "documentation_accuracy"
    ].value == pytest.approx(0.1)
    assert mods.params_for("using", "bone_quarry")[
        "discovery_distance_m"
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
