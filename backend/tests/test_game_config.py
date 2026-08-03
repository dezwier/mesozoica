"""Tests for shared game_config YAML control board."""

from __future__ import annotations

from pathlib import Path

import pytest

from app.core.game_config import (
    ParamModifier,
    get_game_config,
    load_game_config,
    resolve_game_config_dir,
)


def test_resolve_default_game_config_dir() -> None:
    directory = resolve_game_config_dir()
    assert directory.is_dir()
    assert (directory / "site_generation.yaml").is_file()
    assert (directory / "01_site_discovery.yaml").is_file()
    assert (directory / "02_site_stewardship.yaml").is_file()
    assert (directory / "04_fossil_detection.yaml").is_file()
    assert (directory / "leveling.yaml").is_file()


def test_load_game_config_matches_current_defaults() -> None:
    get_game_config.cache_clear()
    config = load_game_config()

    assert config.site_generation.lazy.max_sites_per_cell == 50
    assert config.site_generation.lazy.cell_size_m == 500.0
    assert config.site_generation.lazy.min_separation_km == 0.03
    assert config.site_generation.lazy.weight_global == 0.33
    assert config.site_generation.lazy.weight_nearby == 0.33
    assert config.site_generation.lazy.weight_closest == 0.34

    assert config.site_generation.bulk.max_items == 200
    assert config.site_generation.client.nearby_radius_km == 0.5

    assert config.site_discovery.visibility_distance_m == 20.0
    assert config.site_discovery.max_distance_m == 20.0
    assert config.site_discovery.discovery_chance == 0.1
    assert config.site_discovery.max_discovery_speed_kmh == 10.0
    assert config.site_discovery.site_discovery_xp == 10.0
    assert config.site_discovery.active_km_xp == 30.0
    assert config.site_discovery.passive_km_xp == 5.0
    assert config.site_discovery.client.auto_discover_radius_m == 20.0
    assert config.site_discovery.client.cache_radius_km == 1.0
    assert config.site_discovery.client.cache_refresh_move_threshold_m == 500.0
    assert config.site_discovery.client.discover_fail_retry_s == 20
    assert config.site_discovery.client.discovery_reroll_interval_s == 10
    assert config.site_discovery.level_modifiers["discovery_chance"] == []
    assert float(config.fossil_detection.main_params["fossil_discovery_xp"]) == 5.0
    night_xp = config.site_discovery.weather_time_modifiers["site_discovery_xp"][
        "night"
    ]
    assert night_xp[0].op == "multiply" and night_xp[0].value == 1.5
    dawn_xp = config.fossil_detection.weather_time_modifiers["fossil_discovery_xp"][
        "dawn"
    ]
    assert dawn_xp[0].op == "multiply" and dawn_xp[0].value == 1.2

    assert config.site_stewardship.main_params.dino_accuracy == 0.01
    assert config.site_stewardship.main_params.fossil_accuracy == 0.01
    assert config.site_stewardship.main_params.completeness_accuracy == 0.01
    assert config.site_stewardship.main_params.quality_accuracy == 0.01
    assert config.site_stewardship.main_params.depth_accuracy == 0.01
    dino_acc_mods = config.site_stewardship.level_modifiers["dino_accuracy"]
    assert len(dino_acc_mods) == 99
    assert dino_acc_mods[0].level == 1 and dino_acc_mods[0].op == "multiply"
    assert dino_acc_mods[0].value == 1
    assert dino_acc_mods[-1].level == 99 and dino_acc_mods[-1].value == 99
    rival_mods = config.site_stewardship.level_modifiers["rival_discovery"]
    assert len(rival_mods) == 99
    assert rival_mods[0].level == 1 and rival_mods[0].op == "multiply"
    assert rival_mods[0].value == 1
    assert rival_mods[-1].level == 99 and rival_mods[-1].op == "multiply"
    assert rival_mods[-1].value == 0.5
    assert (
        len(config.site_stewardship.level_modifiers["fossil_accuracy"]) == 99
    )
    assert config.site_stewardship.odd_noise.dino_count == 0.0
    assert config.site_stewardship.odd_noise.fossil_count == 0.5
    assert config.site_stewardship.odd_noise.completeness == 0.3
    assert config.site_stewardship.odd_noise.quality == 0.3
    assert config.site_stewardship.odd_noise.depth == 0.3
    assert [(t.max_odd, t.count) for t in config.site_stewardship.dino_count] == [
        (0.10, 0),
        (0.60, 1),
        (0.80, 2),
        (0.90, 3),
        (0.95, 4),
        (1.00, 5),
    ]
    assert config.site_stewardship.fossil_count[1] == 0.25
    assert config.site_stewardship.fossil_count[6] == 0.05
    assert config.site_stewardship.defaults.subcategory == "teeth"
    assert config.site_stewardship.defaults.completeness == "fragmentary"
    assert config.site_stewardship.defaults.quality == "moderate"
    assert len(config.site_stewardship.depth_weights) == 5
    assert config.site_stewardship.depth_weights[0].min_cm == 0
    assert config.site_stewardship.depth_weights[0].max_cm == 0
    assert config.site_stewardship.depth_weights[0].weight == 0.10
    assert config.site_stewardship.depth_weights[-1].min_cm == 501
    assert config.site_stewardship.depth_weights[-1].max_cm == 1000
    assert abs(sum(config.site_stewardship.completeness_weights.values()) - 1.0) < 1e-6
    assert abs(sum(config.site_stewardship.quality_weights.values()) - 1.0) < 1e-6

    # Back-compat aliases
    assert config.fossil_generation is config.site_stewardship
    assert config.fossil_detection.enabled is False
    assert config.fossil_excavation.enabled is False
    assert config.site_clearing.enabled is False

    assert config.tool_actions.geo_compass.discovery_chance == 0.9
    assert config.tool_actions.geo_compass.modifies_main_params is not None
    geo_mods = config.tool_actions.geo_compass.modifies_main_params
    assert geo_mods.affects_skill("site_discovery")
    assert "discovery_chance" in geo_mods.params_for("using", "site_discovery")
    assert geo_mods.owning == {}
    nav_mods = config.tool_actions.site_navigator.modifies_main_params
    assert nav_mods is not None
    assert "discovery_chance" in nav_mods.params_for("using", "site_discovery")
    assert config.tool_actions.aerial_recon.flight_discovery_chance == 0.01
    assert config.tool_actions.aerial_scout.flight_discovery_distance_m == 50

    ridge = config.tool_actions.ridge_glass
    assert ridge.duration_minutes == 60
    assert ridge.site_discovery_mod("visibility_distance_m") == ParamModifier(
        op="multiply", value=1.3
    )
    assert ridge.site_discovery_mod("discovery_chance") == ParamModifier(
        op="multiply", value=1.3
    )
    assert ridge.site_discovery_mod("max_discovery_speed_kmh") == ParamModifier(
        op="multiply", value=0.7
    )
    assert ridge.added_visibility_range_m is None
    assert ridge.added_discovery_rate is None
    ridge_mods = ridge.modifies_main_params
    assert ridge_mods is not None
    assert ridge_mods.affects_skill("site_discovery")

    drive = config.tool_actions.expedition_drivetrain
    assert drive.duration_minutes == 60
    assert drive.site_discovery_mod("max_discovery_speed_kmh") == ParamModifier(
        op="multiply", value=2.5
    )
    drive_mods = drive.modifies_main_params
    assert drive_mods is not None
    assert drive_mods.affects_skill("site_discovery")

    modifying = [
        key for key, _ in config.tool_actions.tools_modifying_skill("site_discovery")
    ]
    assert "ridge_glass" in modifying
    assert "expedition_drivetrain" in modifying

    assert len(config.leveling.skills) == 12
    assert len(config.leveling.career_titles) == 99


def test_get_game_config_is_cached() -> None:
    get_game_config.cache_clear()
    first = get_game_config()
    second = get_game_config()
    assert first is second


def test_game_config_dir_env_override(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("GAME_CONFIG_DIR", str(tmp_path))
    assert resolve_game_config_dir() == tmp_path
    get_game_config.cache_clear()
    with pytest.raises(FileNotFoundError):
        load_game_config()
    get_game_config.cache_clear()
