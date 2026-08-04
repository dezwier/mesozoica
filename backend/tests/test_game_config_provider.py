"""The process-wide config provider: source selection, TTL, fallback ladder."""

from __future__ import annotations

import copy

import pytest

from app.core import game_config_provider as provider
from app.core.game_config import get_game_config, load_game_config, load_yaml_documents
from app.services.game_config_service import publish_documents, seed_from_yaml


@pytest.fixture
def db_source(monkeypatch):
    """Point the provider at the database (the suite defaults to YAML)."""
    monkeypatch.setattr(provider, "GAME_CONFIG_SOURCE", "db")
    provider.invalidate_game_config_cache()
    yield
    provider.invalidate_game_config_cache()


def _tweaked_documents(chance: float) -> dict:
    documents = copy.deepcopy(load_yaml_documents())
    documents["site_discovery"]["main_params"]["discovery_chance"] = chance
    return documents


def test_yaml_source_never_touches_the_database(monkeypatch) -> None:
    monkeypatch.setattr(provider, "GAME_CONFIG_SOURCE", "yaml")
    provider.invalidate_game_config_cache()

    def explode() -> None:
        raise AssertionError("database must not be read on the yaml source")

    monkeypatch.setattr(provider, "_db_active_version", explode)
    monkeypatch.setattr(provider, "_db_snapshot", explode)

    snapshot = provider.get_active_snapshot()
    assert snapshot.source == "yaml"
    assert snapshot.version == provider.YAML_VERSION
    assert snapshot.config == load_game_config()


def test_db_source_serves_the_seeded_config(session, db_source) -> None:
    seed_from_yaml(session)

    snapshot = provider.get_active_snapshot()
    assert snapshot.source == "db"
    assert snapshot.version == 1
    assert snapshot.config == load_game_config()
    assert get_game_config() == load_game_config()


def test_unseeded_database_falls_back_to_yaml(session, db_source) -> None:
    snapshot = provider.get_active_snapshot()
    assert snapshot.source == "yaml"
    assert snapshot.version == provider.YAML_VERSION


def test_version_bump_is_picked_up_after_the_ttl(session, db_source, monkeypatch) -> None:
    seed_from_yaml(session)
    assert provider.get_active_snapshot().version == 1

    publish_documents(
        session, documents=_tweaked_documents(0.42), base_version=1
    )
    # publish_documents invalidates this process, so re-prime from a clean cache
    # to isolate the TTL behaviour.
    provider.invalidate_game_config_cache()
    monkeypatch.setattr(provider, "GAME_CONFIG_REFRESH_S", 10_000.0)
    first = provider.get_active_snapshot()
    assert first.version == 2
    assert first.config.site_discovery.discovery_chance == 0.42

    # A further publish from "another process" is not seen inside the TTL.
    publish_documents(
        session, documents=_tweaked_documents(0.7), base_version=2
    )
    provider._checked_at = provider.time.monotonic()
    provider._snapshot = first
    assert provider.get_active_snapshot().version == 2

    # ...but is once the TTL lapses.
    monkeypatch.setattr(provider, "GAME_CONFIG_REFRESH_S", 0.0)
    third = provider.get_active_snapshot()
    assert third.version == 3
    assert third.config.site_discovery.discovery_chance == 0.7


def test_unchanged_version_skips_the_document_fetch(
    session, db_source, monkeypatch
) -> None:
    seed_from_yaml(session)
    provider.get_active_snapshot()

    calls = {"n": 0}
    real = provider._db_snapshot

    def counting():
        calls["n"] += 1
        return real()

    monkeypatch.setattr(provider, "_db_snapshot", counting)
    monkeypatch.setattr(provider, "GAME_CONFIG_REFRESH_S", 0.0)

    for _ in range(3):
        assert provider.get_active_snapshot().version == 1
    assert calls["n"] == 0


def test_database_error_serves_last_good_marked_stale(
    session, db_source, monkeypatch
) -> None:
    seed_from_yaml(session)
    good = provider.get_active_snapshot()
    assert good.source == "db"

    def boom():
        raise RuntimeError("connection reset")

    monkeypatch.setattr(provider, "_db_active_version", boom)
    monkeypatch.setattr(provider, "GAME_CONFIG_REFRESH_S", 0.0)

    degraded = provider.get_active_snapshot()
    assert degraded.source == "db-stale"
    assert degraded.version == good.version
    assert degraded.config == good.config


def test_database_error_without_cache_falls_back_to_yaml(
    session, db_source, monkeypatch
) -> None:
    def boom():
        raise RuntimeError("connection reset")

    monkeypatch.setattr(provider, "_db_active_version", boom)

    snapshot = provider.get_active_snapshot()
    assert snapshot.source == "yaml"
    assert snapshot.config == load_game_config()


def test_publish_invalidates_the_writing_process(session, db_source) -> None:
    seed_from_yaml(session)
    assert provider.get_active_snapshot().version == 1

    publish_documents(
        session, documents=_tweaked_documents(0.33), base_version=1
    )

    # No TTL wait: the writer sees its own change immediately.
    snapshot = provider.get_active_snapshot()
    assert snapshot.version == 2
    assert snapshot.config.site_discovery.discovery_chance == 0.33


def test_get_game_config_cache_clear_still_works(session, db_source) -> None:
    seed_from_yaml(session)
    assert get_game_config().site_discovery.discovery_chance == 0.1

    publish_documents(
        session, documents=_tweaked_documents(0.9), base_version=1
    )
    get_game_config.cache_clear()

    assert get_game_config().site_discovery.discovery_chance == 0.9
