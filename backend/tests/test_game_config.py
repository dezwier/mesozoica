"""Tests for shared game_config YAML control board."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from app.core.game_config import (
    DOCUMENT_FILES,
    DOCUMENT_IDS,
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


def test_load_game_config_structure() -> None:
    """Smoke-load the control board: shape and wiring, not knob values.

    Tunable floats (XP, distances, weather multipliers, tool mods) live in YAML
    and change often — pin structure/invariants here instead.
    """
    get_game_config.cache_clear()
    config = load_game_config()

    lazy = config.site_generation.lazy
    assert lazy.max_sites_per_cell > 0
    assert lazy.cell_size_m > 0
    assert lazy.min_separation_km > 0
    assert (
        abs(lazy.weight_global + lazy.weight_nearby + lazy.weight_closest - 1.0)
        < 1e-6
    )
    assert config.site_generation.bulk.max_items > 0
    assert config.site_generation.client.nearby_radius_km > 0

    disc = config.site_discovery
    assert disc.visibility_distance_m > 0
    assert 0 < disc.discovery_chance <= 1
    assert disc.discovery_max_speed_kmh > 0
    assert disc.discover_site_xp > 0
    assert disc.client.auto_discover_radius_m > 0
    assert disc.level_modifiers["discovery_max_speed_kmh"] == []
    for key in ("discovery_chance", "visibility_distance_m"):
        mods = disc.level_modifiers[key]
        assert len(mods) >= 2
        assert mods[0].level <= mods[-1].level
    assert (
        disc.level_modifiers["visibility_distance_m"]
        == disc.level_modifiers["discovery_chance"]
    )
    assert "locate_fossil_in_situ_xp" in config.fossil_detection.main_params
    assert "night" in disc.weather_time_modifiers.get("discover_site_xp", {})
    assert "dawn" in config.fossil_detection.weather_time_modifiers.get(
        "locate_fossil_in_situ_xp", {}
    )

    stew = config.site_stewardship
    assert 0 < stew.main_params.document_accuracy <= 1
    assert stew.main_params.visibility_distance_m > 0
    assert stew.visibility_distance_m == stew.main_params.visibility_distance_m
    assert stew.document_speed == stew.main_params.document_speed == 0.01
    acc_mods = stew.level_modifiers["document_accuracy"]
    assert len(acc_mods) >= 2 and acc_mods[0].op == "multiply"
    rival_mods = stew.level_modifiers["rival_discovery_chance"]
    assert len(rival_mods) >= 2 and rival_mods[0].op == "multiply"
    assert "documentation_genera" not in stew.level_modifiers
    assert stew.accuracy_noise.max_delta > 0
    assert len(stew.dino_count) >= 2
    assert stew.dino_count[0].count == 0
    assert stew.dino_count[-1].count >= stew.dino_count[0].count
    assert stew.fossil_count
    assert stew.defaults.subcategory
    assert len(stew.depth_weights) >= 2
    assert abs(sum(stew.completeness_weights.values()) - 1.0) < 1e-6
    assert abs(sum(stew.quality_weights.values()) - 1.0) < 1e-6

    # Back-compat aliases
    assert config.fossil_generation is config.site_stewardship
    assert config.fossil_detection is config.bone_quarry
    assert config.bone_quarry.enabled is True
    assert config.science_hall.enabled is False
    assert config.field_survey.skill_id == "field_survey"

    tools = config.tool_actions
    assert tools.geo_compass.modifies_main_params is not None
    geo_mods = tools.geo_compass.modifies_main_params
    assert geo_mods.affects_skill("field_survey")
    assert "discovery_chance" in geo_mods.params_for("using", "field_survey")
    assert geo_mods.owning == {}
    nav_mods = tools.site_navigator.modifies_main_params
    assert nav_mods is not None
    assert "discovery_chance" in nav_mods.params_for("using", "field_survey")
    assert tools.aerial_recon.flight_discovery_chance > 0
    assert tools.aerial_scout.flight_discovery_distance_m > 0

    ridge = tools.ridge_glass
    assert ridge.duration_minutes > 0
    assert ridge.site_discovery_mod("visibility_distance_m") is not None
    assert ridge.site_discovery_mod("discovery_chance") is not None
    assert ridge.site_discovery_mod("discovery_max_speed_kmh") is not None
    assert ridge.added_visibility_range_m is None
    assert ridge.added_discovery_rate is None
    assert ridge.modifies_main_params is not None
    assert ridge.modifies_main_params.affects_skill("field_survey")

    for key in (
        "expedition_drivetrain",
        "trail_striders",
        "canyon_throttle",
        "overland_chassis",
    ):
        action = getattr(tools, key)
        assert action.site_discovery_mod("discovery_max_speed_kmh") is not None
        assert action.modifies_main_params is not None
        assert "visibility_distance_m" in action.modifies_main_params.params_for(
            "using", "field_survey"
        )

    nocturne = tools.nocturne_lens
    assert nocturne.duration_minutes > 0
    assert nocturne.active_weather_times == ("night",)
    assert nocturne.site_discovery_mod("visibility_distance_m") is not None
    assert nocturne.site_discovery_mod("discovery_chance") is not None
    assert nocturne.site_discovery_mod("discovery_max_speed_kmh") is None

    modifying = {
        key for key, _ in tools.tools_modifying_skill("field_survey")
    }
    assert {
        "ridge_glass",
        "trail_striders",
        "expedition_drivetrain",
        "canyon_throttle",
        "overland_chassis",
        "nocturne_lens",
    } <= modifying

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
