"""Tests for shared game_config YAML control board."""

from __future__ import annotations

from pathlib import Path

import pytest

from app.core.game_config import (
    get_game_config,
    load_game_config,
    resolve_game_config_dir,
)


def test_resolve_default_game_config_dir() -> None:
    directory = resolve_game_config_dir()
    assert directory.is_dir()
    assert (directory / "site_generation.yaml").is_file()
    assert (directory / "site_discovery.yaml").is_file()
    assert (directory / "fossil_generation.yaml").is_file()
    assert (directory / "leveling.yaml").is_file()


def test_load_game_config_matches_current_defaults() -> None:
    get_game_config.cache_clear()
    config = load_game_config()

    assert config.site_generation.lazy.max_sites_per_cell == 100
    assert config.site_generation.lazy.cell_size_m == 500.0
    assert config.site_generation.lazy.min_separation_km == 0.03
    assert config.site_generation.lazy.weight_global == 0.33
    assert config.site_generation.lazy.weight_nearby == 0.33
    assert config.site_generation.lazy.weight_closest == 0.34

    assert config.site_generation.bulk.max_items == 200
    assert config.site_generation.client.nearby_radius_km == 0.5

    assert config.site_discovery.max_distance_m == 50.0
    assert config.site_discovery.discovery_chance == 0.1
    assert config.site_discovery.client.auto_discover_radius_m == 50.0
    assert config.site_discovery.client.cache_radius_km == 1.0
    assert config.site_discovery.client.cache_refresh_move_threshold_m == 500.0
    assert config.site_discovery.client.discover_fail_retry_s == 20

    assert config.fossil_generation.odd_noise.dino_count == 0.0
    assert config.fossil_generation.odd_noise.fossil_count == 0.5
    assert config.fossil_generation.odd_noise.completeness == 0.3
    assert config.fossil_generation.odd_noise.quality == 0.3
    assert config.fossil_generation.odd_noise.depth == 0.3
    assert [
        (t.max_odd, t.count) for t in config.fossil_generation.dino_count_thresholds
    ] == [
        (0.10, 0),
        (0.60, 1),
        (0.80, 2),
        (0.90, 3),
        (0.95, 4),
        (1.00, 5),
    ]
    assert config.fossil_generation.card_count_weights[1] == 0.25
    assert config.fossil_generation.card_count_weights[6] == 0.05
    assert config.fossil_generation.defaults.subcategory == "teeth"
    assert config.fossil_generation.defaults.completeness == "fragmentary"
    assert config.fossil_generation.defaults.quality == "moderate"
    assert len(config.fossil_generation.depth_buckets) == 5
    assert config.fossil_generation.depth_buckets[0].min_cm == 0
    assert config.fossil_generation.depth_buckets[0].max_cm == 0
    assert config.fossil_generation.depth_buckets[0].weight == 0.10
    assert config.fossil_generation.depth_buckets[-1].min_cm == 501
    assert config.fossil_generation.depth_buckets[-1].max_cm == 1000

    assert config.fossil_discovery.enabled is False
    assert config.fossil_excavation.enabled is False

    assert config.leveling.rewards.site_discover_site_discovery_xp == 10
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
