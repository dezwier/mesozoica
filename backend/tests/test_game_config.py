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


def test_load_game_config_matches_current_defaults() -> None:
    get_game_config.cache_clear()
    config = load_game_config()

    assert config.site_generation.lazy.min_sites_in_radius == 100
    assert config.site_generation.lazy.radius_km == 1.0
    assert config.site_generation.lazy.min_separation_km == 0.01
    assert config.site_generation.lazy.weight_global == 0.25
    assert config.site_generation.lazy.weight_nearby == 0.50
    assert config.site_generation.lazy.weight_closest == 0.25

    assert config.site_generation.bulk.max_items == 100
    assert config.site_generation.client.ensure_move_threshold_m == 500.0
    assert config.site_generation.client.nearby_radius_km == 1.0

    assert config.site_discovery.max_distance_m == 50.0
    assert config.site_discovery.client.auto_discover_radius_m == 50.0
    assert config.site_discovery.client.cache_radius_km == 1.0
    assert config.site_discovery.client.cache_refresh_move_threshold_m == 500.0
    assert config.site_discovery.client.discover_fail_retry_s == 20

    assert config.fossil_generation.dino_count_weights == {1: 0.60, 2: 0.30, 3: 0.10}
    assert config.fossil_generation.card_count_weights[1] == 0.25
    assert config.fossil_generation.card_count_weights[6] == 0.05
    assert config.fossil_generation.defaults.subcategory == "teeth"
    assert config.fossil_generation.defaults.completeness == "fragmentary"
    assert config.fossil_generation.defaults.quality == "moderate"

    assert config.fossil_discovery.enabled is False
    assert config.fossil_excavation.enabled is False


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
