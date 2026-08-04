"""Tests for the shared game-config control board endpoint (Phase 1 delivery)."""

from app.core.game_config import load_game_config_raw
from app.services.game_config_service import get_game_config_version


def test_game_config_returns_version_and_all_sections(client):
    response = client.get("/api/v1/game-config")
    assert response.status_code == 200

    body = response.json()
    assert body["version"] == get_game_config_version()
    assert response.headers.get("ETag") == f'"{body["version"]}"'

    # The served sections must match the raw control board the client would
    # otherwise parse from its bundled YAML fallback.
    assert body["config"].keys() == load_game_config_raw().keys()
    assert "site_discovery" in body["config"]
    assert "main_params" in body["config"]["site_discovery"]


def test_game_config_values_match_control_board(client):
    body = client.get("/api/v1/game-config").json()
    raw = load_game_config_raw()
    assert (
        body["config"]["site_discovery"]["main_params"]["discovery_chance"]
        == raw["site_discovery"]["main_params"]["discovery_chance"]
    )


def test_game_config_conditional_request_returns_304(client):
    first = client.get("/api/v1/game-config")
    etag = first.headers["ETag"]

    cached = client.get("/api/v1/game-config", headers={"If-None-Match": etag})
    assert cached.status_code == 304
    assert cached.headers.get("ETag") == etag

    stale = client.get("/api/v1/game-config", headers={"If-None-Match": '"deadbeef"'})
    assert stale.status_code == 200
