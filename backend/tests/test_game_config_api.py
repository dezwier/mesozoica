"""Tests for the shared game-config control board endpoint."""

from app.core.game_config import GameConfig
from app.services.game_config_service import (
    build_canonical_config,
    get_game_config_version,
)


def test_game_config_returns_version_and_all_sections(client):
    response = client.get("/api/v1/game-config")
    assert response.status_code == 200

    body = response.json()
    assert body["version"] == get_game_config_version()
    assert response.headers.get("ETag") == f'"{body["version"]}"'

    # Served config is the canonical, validated projection of the control board.
    assert body["config"].keys() == build_canonical_config().keys()
    assert "site_discovery" in body["config"]
    assert "main_params" in body["config"]["site_discovery"]


def test_game_config_serves_canonical_validated_config(client):
    body = client.get("/api/v1/game-config").json()
    # The served config round-trips back through the schema unchanged.
    assert body["config"] == build_canonical_config()
    GameConfig.model_validate(body["config"])


def test_game_config_conditional_request_returns_304(client):
    first = client.get("/api/v1/game-config")
    etag = first.headers["ETag"]

    cached = client.get("/api/v1/game-config", headers={"If-None-Match": etag})
    assert cached.status_code == 304
    assert cached.headers.get("ETag") == etag

    stale = client.get("/api/v1/game-config", headers={"If-None-Match": '"deadbeef"'})
    assert stale.status_code == 200
