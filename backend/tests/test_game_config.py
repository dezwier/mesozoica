"""Tests for shared game_config YAML control board."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from app.core.game_config import (
    DOCUMENT_FILES,
    DOCUMENT_IDS,
    ParamModifier,
    build_game_config,
    canonical_checksum,
    get_game_config,
    load_game_config,
    load_yaml_documents,
    resolve_game_config_dir,
)

# These ids are the literal keys inside User.skill_xp and User.skill_breakdown.
# Renaming one orphans every player's XP for that skill, silently — no error, the
# old key is simply never read again. 'leveling/skills' is in LOCKED_PATHS so the
# admin API refuses such an edit; this pins the ids themselves as a tripwire for
# anyone changing leveling.yaml directly or seeding with --force.
EXPECTED_SKILL_IDS = (
    "field_survey",
    "bone_quarry",
    "science_hall",
)


def test_skill_ids_unchanged() -> None:
    skills = load_game_config().leveling.skills
    assert tuple(skill.id for skill in skills) == EXPECTED_SKILL_IDS


def test_every_skill_has_its_own_document() -> None:
    """A skill without a config document has no tunable parameters at all."""
    skills = {skill.id for skill in load_game_config().leveling.skills}
    numbered = {
        doc_id for doc_id, filename in DOCUMENT_FILES if filename[0].isdigit()
    }
    assert skills == numbered


def test_document_files_cover_the_control_board() -> None:
    directory = resolve_game_config_dir()
    on_disk = {path.name for path in directory.glob("*.yaml")}
    assert {filename for _, filename in DOCUMENT_FILES} == on_disk
    assert len(DOCUMENT_IDS) == len(set(DOCUMENT_IDS)) == len(DOCUMENT_FILES)


def test_build_game_config_from_documents_matches_file_load() -> None:
    documents = load_yaml_documents()
    assert build_game_config(documents) == load_game_config()


def test_build_game_config_survives_json_round_trip() -> None:
    """The DB stores, and the API serves, JSON — parsing it back must not drift.

    Pins the known quirk that ``fossil_count`` integer keys become strings.
    """
    documents = load_yaml_documents()
    round_tripped = json.loads(json.dumps(documents, default=str))
    assert build_game_config(round_tripped) == load_game_config()


def test_canonical_checksum_is_stable_and_content_sensitive() -> None:
    documents = load_yaml_documents()
    assert canonical_checksum(documents) == canonical_checksum(load_yaml_documents())

    mutated = json.loads(json.dumps(documents, default=str))
    mutated["field_survey"]["main_params"]["discovery_chance"] = 0.42
    assert canonical_checksum(mutated) != canonical_checksum(documents)


def test_build_game_config_rejects_missing_document() -> None:
    documents = load_yaml_documents()
    del documents["leveling"]
    with pytest.raises(ValueError, match="Missing game config documents: leveling"):
        build_game_config(documents)


def test_resolve_default_game_config_dir() -> None:
    directory = resolve_game_config_dir()
    assert directory.is_dir()
    assert (directory / "site_generation.yaml").is_file()
    assert (directory / "01_field_survey.yaml").is_file()
    assert (directory / "02_bone_quarry.yaml").is_file()
    assert (directory / "03_science_hall.yaml").is_file()
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

    assert config.site_discovery.discovery_distance_m == 20.0
    assert config.site_discovery.max_distance_m == 20.0
    assert config.site_discovery.discovery_chance == 0.1
    assert config.site_discovery.discovery_max_speed_kmh == 10.0
    assert config.site_discovery.discover_site_xp == 20.0
    assert config.site_discovery.discover_site_as_first_xp == 20.0
    assert config.site_discovery.explore_100m_actively_xp == 20.0
    assert config.site_discovery.explore_100m_passively_xp == 10.0
    assert config.site_discovery.client.auto_discover_radius_m == 20.0
    assert config.site_discovery.client.cache_radius_km == 1.0
    assert config.site_discovery.client.cache_refresh_move_threshold_m == 500.0
    assert config.site_discovery.client.discover_fail_retry_s == 20
    assert config.site_discovery.client.discovery_reroll_interval_s == 10
    assert config.site_discovery.level_modifiers["discovery_max_speed_kmh"] == []
    reach_mods = config.site_discovery.level_modifiers["discovery_chance"]
    assert len(reach_mods) == 2
    assert reach_mods[0].level == 1 and reach_mods[0].value == 1
    assert reach_mods[-1].level == 99 and reach_mods[-1].value == 1.5
    assert config.site_discovery.level_modifiers["discovery_distance_m"] == reach_mods
    assert (
        config.site_stewardship.level_modifiers["documentation_distance_m"]
        == reach_mods
    )
    assert float(config.fossil_detection.main_params["locate_fossil_in_situ_xp"]) == 20.0
    night_xp = config.site_discovery.weather_time_modifiers["discover_site_xp"][
        "night"
    ]
    assert night_xp[0].op == "multiply" and night_xp[0].value == 1.5
    dawn_xp = config.fossil_detection.weather_time_modifiers["locate_fossil_in_situ_xp"][
        "dawn"
    ]
    assert dawn_xp[0].op == "multiply" and dawn_xp[0].value == 1.2

    assert config.site_stewardship.main_params.documentation_genera == 0.01
    assert config.site_stewardship.main_params.documentation_fossil == 0.01
    assert config.site_stewardship.main_params.documentation_completeness == 0.01
    assert config.site_stewardship.main_params.documentation_preservation == 0.01
    assert config.site_stewardship.main_params.documentation_depth == 0.01
    assert config.site_stewardship.main_params.documentation_distance_m == 50.0
    assert config.site_stewardship.main_params.document_progress_xp == 20.0
    assert config.site_stewardship.main_params.document_site_xp == 80.0
    assert config.site_stewardship.main_params.document_site_as_first_xp == 20.0
    assert config.site_stewardship.documentation_distance_m == 50.0
    assert config.site_stewardship.document_progress_xp == 20.0
    assert config.site_stewardship.document_site_xp == 80.0
    assert config.site_stewardship.document_site_as_first_xp == 20.0
    dino_acc_mods = config.site_stewardship.level_modifiers["documentation_genera"]
    assert len(dino_acc_mods) == 2
    assert dino_acc_mods[0].level == 1 and dino_acc_mods[0].op == "multiply"
    assert dino_acc_mods[0].value == 1
    assert dino_acc_mods[-1].level == 99 and dino_acc_mods[-1].value == 99
    rival_mods = config.site_stewardship.level_modifiers["rival_discovery_chance"]
    assert len(rival_mods) == 2
    assert rival_mods[0].level == 1 and rival_mods[0].op == "multiply"
    assert rival_mods[0].value == 1
    assert rival_mods[-1].level == 99 and rival_mods[-1].op == "multiply"
    assert rival_mods[-1].value == 0.5
    assert (
        len(config.site_stewardship.level_modifiers["documentation_fossil"]) == 2
    )
    assert config.site_stewardship.odd_noise.dino_count == 0.0
    assert config.site_stewardship.odd_noise.fossil_count == 0.5
    assert config.site_stewardship.odd_noise.completeness == 0.3
    assert config.site_stewardship.odd_noise.quality == 0.3
    assert config.site_stewardship.odd_noise.depth == 0.3
    assert config.site_stewardship.accuracy_noise.max_delta == 0.30
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
    assert config.fossil_detection is config.bone_quarry
    assert config.bone_quarry.enabled is True
    assert config.science_hall.enabled is False
    assert config.field_survey.skill_id == "field_survey"

    assert config.tool_actions.geo_compass.discovery_chance == 0.9
    assert config.tool_actions.geo_compass.modifies_main_params is not None
    geo_mods = config.tool_actions.geo_compass.modifies_main_params
    assert geo_mods.affects_skill("field_survey")
    assert "discovery_chance" in geo_mods.params_for("using", "field_survey")
    assert geo_mods.owning == {}
    nav_mods = config.tool_actions.site_navigator.modifies_main_params
    assert nav_mods is not None
    assert "discovery_chance" in nav_mods.params_for("using", "field_survey")
    assert config.tool_actions.aerial_recon.flight_discovery_chance == 0.01
    assert config.tool_actions.aerial_scout.flight_discovery_distance_m == 50

    ridge = config.tool_actions.ridge_glass
    assert ridge.duration_minutes == 60
    assert ridge.site_discovery_mod("discovery_distance_m") == ParamModifier(
        op="multiply", value=1.3
    )
    assert ridge.site_discovery_mod("discovery_chance") == ParamModifier(
        op="multiply", value=1.3
    )
    assert ridge.site_discovery_mod("discovery_max_speed_kmh") == ParamModifier(
        op="multiply", value=0.7
    )
    assert ridge.added_visibility_range_m is None
    assert ridge.added_discovery_rate is None
    ridge_mods = ridge.modifies_main_params
    assert ridge_mods is not None
    assert ridge_mods.affects_skill("field_survey")

    drive = config.tool_actions.expedition_drivetrain
    assert drive.duration_minutes == 60
    assert drive.site_discovery_mod("discovery_max_speed_kmh") == ParamModifier(
        op="multiply", value=3.0
    )
    assert drive.site_discovery_mod("discovery_distance_m") == ParamModifier(
        op="multiply", value=0.9
    )
    assert drive.site_discovery_mod("discovery_chance") == ParamModifier(
        op="multiply", value=0.9
    )
    drive_mods = drive.modifies_main_params
    assert drive_mods is not None
    assert drive_mods.affects_skill("field_survey")
    assert drive_mods.affects_skill("field_survey")
    assert drive_mods.params_for("using", "field_survey")[
        "documentation_distance_m"
    ] == ParamModifier(op="multiply", value=0.9)

    trail = config.tool_actions.trail_striders
    assert trail.site_discovery_mod("discovery_max_speed_kmh") == ParamModifier(
        op="multiply", value=2.0
    )
    assert trail.modifies_main_params is not None
    assert trail.modifies_main_params.params_for("using", "field_survey")[
        "documentation_distance_m"
    ] == ParamModifier(op="multiply", value=0.95)

    canyon = config.tool_actions.canyon_throttle
    assert canyon.site_discovery_mod("discovery_max_speed_kmh") == ParamModifier(
        op="multiply", value=4.0
    )
    assert canyon.modifies_main_params is not None
    assert canyon.modifies_main_params.params_for("using", "field_survey")[
        "documentation_distance_m"
    ] == ParamModifier(op="multiply", value=0.85)

    overland = config.tool_actions.overland_chassis
    assert overland.site_discovery_mod("discovery_max_speed_kmh") == ParamModifier(
        op="multiply", value=5.0
    )
    assert overland.modifies_main_params is not None
    assert overland.modifies_main_params.params_for("using", "field_survey")[
        "documentation_distance_m"
    ] == ParamModifier(op="multiply", value=0.8)

    nocturne = config.tool_actions.nocturne_lens
    assert nocturne.duration_minutes == 60
    assert nocturne.active_weather_times == ("night",)
    assert nocturne.site_discovery_mod("discovery_distance_m") == ParamModifier(
        op="multiply", value=1.4
    )
    assert nocturne.site_discovery_mod("discovery_chance") == ParamModifier(
        op="multiply", value=1.4
    )
    assert nocturne.site_discovery_mod("discovery_max_speed_kmh") is None

    modifying = [
        key for key, _ in config.tool_actions.tools_modifying_skill("field_survey")
    ]
    assert "ridge_glass" in modifying
    assert "trail_striders" in modifying
    assert "expedition_drivetrain" in modifying
    assert "canyon_throttle" in modifying
    assert "overland_chassis" in modifying
    assert "nocturne_lens" in modifying

    stewardship_modifying = [
        key
        for key, _ in config.tool_actions.tools_modifying_skill("field_survey")
    ]
    assert "trail_striders" in stewardship_modifying
    assert "expedition_drivetrain" in stewardship_modifying
    assert "canyon_throttle" in stewardship_modifying
    assert "overland_chassis" in stewardship_modifying

    assert len(config.leveling.skills) == 3
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
