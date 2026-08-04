"""The HTTP surface: public config delivery, the version header, admin writes.

The service layer is covered by test_game_config_seed.py and the provider by
test_game_config_provider.py — this file exercises what only shows up over HTTP:
status codes, ETag revalidation, auth, and the response middleware.
"""

from __future__ import annotations

import copy

import pytest

from app.core import game_config_provider as provider
from app.core.app_factory import GAME_CONFIG_VERSION_HEADER
from app.core.game_config import load_yaml_documents
from app.core.security import create_access_token
from app.models.user import User
from app.services.game_config_service import publish_documents, seed_from_yaml

PUBLIC = "/api/v1/game-config"
ADMIN = "/api/v1/admin/game-config"


@pytest.fixture
def db_source(monkeypatch):
    """Point the provider at the database (the suite defaults to YAML)."""
    monkeypatch.setattr(provider, "GAME_CONFIG_SOURCE", "db")
    provider.invalidate_game_config_cache()
    yield
    provider.invalidate_game_config_cache()


def _headers(session, *, username: str, is_admin: bool) -> dict[str, str]:
    user = User(
        username=username,
        email=f"{username}@example.com",
        password="x",
        is_admin=is_admin,
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    return {"Authorization": f"Bearer {create_access_token({'sub': str(user.id)})}"}


def _tweaked(chance: float) -> dict:
    documents = copy.deepcopy(load_yaml_documents())
    documents["field_survey"]["main_params"]["discovery_chance"] = chance
    return documents


# --------------------------------------------------------------------------
# Public delivery
# --------------------------------------------------------------------------


def test_public_config_needs_no_auth_and_serves_every_document(client) -> None:
    response = client.get(PUBLIC)

    assert response.status_code == 200
    body = response.json()
    assert set(body["documents"]) == set(load_yaml_documents())
    assert body["checksum"]
    assert response.headers["ETag"] == f'"cfg-{body["version"]}-{body["checksum"][:12]}"'
    assert response.headers["Cache-Control"] == "no-cache"


def test_public_config_falls_back_to_bundled_yaml_when_unseeded(client) -> None:
    body = client.get(PUBLIC).json()

    assert body["source"] == "yaml"
    assert body["version"] == provider.YAML_VERSION
    assert body["activated_at"] is None


def test_public_config_revalidates_with_if_none_match(client) -> None:
    etag = client.get(PUBLIC).headers["ETag"]

    response = client.get(PUBLIC, headers={"If-None-Match": etag})

    assert response.status_code == 304
    assert response.headers["ETag"] == etag


def test_public_config_returns_full_body_for_a_stale_etag(client) -> None:
    response = client.get(PUBLIC, headers={"If-None-Match": '"cfg-999-deadbeef1234"'})

    assert response.status_code == 200
    assert response.json()["documents"]


def test_public_version_probe_matches_the_full_payload(client) -> None:
    full = client.get(PUBLIC)
    probe = client.get(f"{PUBLIC}/version")

    assert probe.status_code == 200
    assert probe.json() == {
        "version": full.json()["version"],
        "checksum": full.json()["checksum"],
        "activated_at": full.json()["activated_at"],
    }
    assert probe.headers["ETag"] == full.headers["ETag"]
    assert "documents" not in probe.json()


def test_public_config_serves_the_stored_revision(client, session, db_source) -> None:
    seed_from_yaml(session)
    provider.invalidate_game_config_cache()

    body = client.get(PUBLIC).json()

    assert body["source"] == "db"
    assert body["version"] == 1
    assert body["activated_at"] is not None


def test_public_config_reflects_a_publish(client, session, db_source) -> None:
    seed_from_yaml(session)
    provider.invalidate_game_config_cache()
    first = client.get(PUBLIC)

    publish_documents(session, documents=_tweaked(0.77), base_version=1)
    provider.invalidate_game_config_cache()
    second = client.get(PUBLIC)

    assert second.json()["version"] == 2
    assert second.headers["ETag"] != first.headers["ETag"]
    assert (
        second.json()["documents"]["field_survey"]["main_params"]["discovery_chance"]
        == 0.77
    )


# --------------------------------------------------------------------------
# Version header middleware
# --------------------------------------------------------------------------


def test_api_responses_carry_the_active_config_version(client) -> None:
    response = client.get(PUBLIC)

    assert response.headers[GAME_CONFIG_VERSION_HEADER] == str(
        response.json()["version"]
    )


def test_divergent_client_version_is_logged_not_rejected(client) -> None:
    """Regression: the divergence branch must not blow up on a missing import."""
    response = client.get(PUBLIC, headers={GAME_CONFIG_VERSION_HEADER: "999"})

    assert response.status_code == 200
    assert response.headers[GAME_CONFIG_VERSION_HEADER] == str(
        response.json()["version"]
    )


def test_repeated_divergence_stays_healthy(client) -> None:
    """The throttle keeps state across requests; every response must still pass."""
    for _ in range(3):
        response = client.get(
            f"{PUBLIC}/version", headers={GAME_CONFIG_VERSION_HEADER: "424242"}
        )
        assert response.status_code == 200


def test_non_numeric_client_version_is_ignored(client) -> None:
    response = client.get(PUBLIC, headers={GAME_CONFIG_VERSION_HEADER: "not-a-number"})

    assert response.status_code == 200


def test_non_api_routes_are_not_stamped(client) -> None:
    response = client.get("/")

    assert response.status_code == 200
    assert GAME_CONFIG_VERSION_HEADER not in response.headers


# --------------------------------------------------------------------------
# Admin auth
# --------------------------------------------------------------------------


def test_admin_config_requires_authentication(client) -> None:
    assert client.get(ADMIN).status_code in (401, 403)


def test_admin_config_rejects_non_admin(client, session) -> None:
    headers = _headers(session, username="cfg_plain", is_admin=False)

    assert client.get(ADMIN, headers=headers).status_code == 403


def test_admin_write_rejects_non_admin(client, session) -> None:
    seed_from_yaml(session)
    headers = _headers(session, username="cfg_plain_write", is_admin=False)

    response = client.put(ADMIN, headers=headers, json={"documents": _tweaked(0.4)})

    assert response.status_code == 403


# --------------------------------------------------------------------------
# Admin reads
# --------------------------------------------------------------------------


def test_admin_config_404s_before_seeding(client, session) -> None:
    headers = _headers(session, username="cfg_admin_empty", is_admin=True)

    assert client.get(ADMIN, headers=headers).status_code == 404


def test_admin_config_returns_the_active_revision(client, session) -> None:
    seed_from_yaml(session)
    headers = _headers(session, username="cfg_admin_read", is_admin=True)

    body = client.get(ADMIN, headers=headers).json()

    assert body["version"] == 1
    assert body["source"] == "db"
    assert set(body["documents"]) == set(load_yaml_documents())


def test_admin_schema_lists_documents_and_locked_paths(client, session) -> None:
    headers = _headers(session, username="cfg_admin_schema", is_admin=True)

    body = client.get(f"{ADMIN}/schema", headers=headers).json()

    assert {doc["doc_id"] for doc in body["documents"]} == set(load_yaml_documents())
    assert "period_colors" in body["locked_paths"]
    assert "tool_actions/*/stats_explanation" in body["locked_paths"]
    skills = {doc["doc_id"] for doc in body["documents"] if doc["is_skill"]}
    assert "field_survey" in skills
    assert "leveling" not in skills


def test_admin_revisions_flag_the_active_one(client, session) -> None:
    seed_from_yaml(session)
    publish_documents(session, documents=_tweaked(0.6), base_version=1)
    headers = _headers(session, username="cfg_admin_revs", is_admin=True)

    body = client.get(f"{ADMIN}/revisions", headers=headers).json()

    assert [row["version"] for row in body] == [2, 1]
    assert [row["is_active"] for row in body] == [True, False]
    assert body[1]["source"] == "seed"


def test_admin_revisions_respects_limit(client, session) -> None:
    seed_from_yaml(session)
    publish_documents(session, documents=_tweaked(0.6), base_version=1)
    headers = _headers(session, username="cfg_admin_limit", is_admin=True)

    body = client.get(f"{ADMIN}/revisions?limit=1", headers=headers).json()

    assert [row["version"] for row in body] == [2]
    assert client.get(f"{ADMIN}/revisions?limit=0", headers=headers).status_code == 422


def test_admin_reads_a_single_revision(client, session) -> None:
    seed_from_yaml(session)
    publish_documents(session, documents=_tweaked(0.6), base_version=1)
    headers = _headers(session, username="cfg_admin_one", is_admin=True)

    body = client.get(f"{ADMIN}/revisions/1", headers=headers).json()

    assert body["version"] == 1
    assert (
        body["documents"]["field_survey"]["main_params"]["discovery_chance"]
        != 0.6
    )


def test_admin_unknown_revision_404s(client, session) -> None:
    seed_from_yaml(session)
    headers = _headers(session, username="cfg_admin_missing", is_admin=True)

    assert client.get(f"{ADMIN}/revisions/999", headers=headers).status_code == 404


# --------------------------------------------------------------------------
# Admin validate
# --------------------------------------------------------------------------


def test_validate_accepts_the_bundled_board(client, session) -> None:
    headers = _headers(session, username="cfg_admin_ok", is_admin=True)

    body = client.post(
        f"{ADMIN}/validate", headers=headers, json={"documents": load_yaml_documents()}
    ).json()

    assert body == {"valid": True, "errors": []}


def test_validate_reports_a_bad_value_without_writing(client, session) -> None:
    seed_from_yaml(session)
    headers = _headers(session, username="cfg_admin_bad", is_admin=True)
    documents = _tweaked("not-a-number")

    body = client.post(
        f"{ADMIN}/validate", headers=headers, json={"documents": documents}
    ).json()

    assert body["valid"] is False
    assert body["errors"]
    assert client.get(ADMIN, headers=headers).json()["version"] == 1


def test_validate_reports_a_missing_document(client, session) -> None:
    headers = _headers(session, username="cfg_admin_gap", is_admin=True)
    documents = load_yaml_documents()
    del documents["leveling"]

    body = client.post(
        f"{ADMIN}/validate", headers=headers, json={"documents": documents}
    ).json()

    assert body["valid"] is False
    assert "leveling" in str(body["errors"])


# --------------------------------------------------------------------------
# Admin publish
# --------------------------------------------------------------------------


def test_publish_bundle_creates_the_next_version(client, session) -> None:
    seed_from_yaml(session)
    headers = _headers(session, username="cfg_admin_pub", is_admin=True)

    response = client.put(
        ADMIN,
        headers=headers,
        json={"documents": _tweaked(0.81), "base_version": 1, "note": "buff discovery"},
    )

    assert response.status_code == 200
    assert response.json()["version"] == 2
    revisions = client.get(f"{ADMIN}/revisions", headers=headers).json()
    assert revisions[0]["note"] == "buff discovery"
    assert revisions[0]["source"] == "admin"


def test_publish_records_the_editing_admin(client, session) -> None:
    seed_from_yaml(session)
    headers = _headers(session, username="cfg_admin_attrib", is_admin=True)

    client.put(
        ADMIN, headers=headers, json={"documents": _tweaked(0.55), "base_version": 1}
    )

    latest = client.get(f"{ADMIN}/revisions", headers=headers).json()[0]
    assert latest["created_by_user_id"] is not None


def test_publish_with_a_stale_base_version_conflicts(client, session) -> None:
    seed_from_yaml(session)
    publish_documents(session, documents=_tweaked(0.6), base_version=1)
    headers = _headers(session, username="cfg_admin_conflict", is_admin=True)

    response = client.put(
        ADMIN, headers=headers, json={"documents": _tweaked(0.9), "base_version": 1}
    )

    assert response.status_code == 409


def test_publish_rejects_a_locked_path(client, session) -> None:
    seed_from_yaml(session)
    headers = _headers(session, username="cfg_admin_locked", is_admin=True)
    documents = copy.deepcopy(load_yaml_documents())
    documents["period_colors"]["site_markers"]["jurassic"] = "#123456"

    response = client.put(
        ADMIN, headers=headers, json={"documents": documents, "base_version": 1}
    )

    assert response.status_code == 400
    assert "period_colors" in response.json()["detail"]


def test_publish_rejects_an_invalid_value(client, session) -> None:
    seed_from_yaml(session)
    headers = _headers(session, username="cfg_admin_invalid", is_admin=True)

    response = client.put(
        ADMIN,
        headers=headers,
        json={"documents": _tweaked("not-a-number"), "base_version": 1},
    )

    assert response.status_code == 422
    assert client.get(ADMIN, headers=headers).json()["version"] == 1


# --------------------------------------------------------------------------
# Admin single-document patch
# --------------------------------------------------------------------------


def test_patch_document_carries_the_others_over(client, session) -> None:
    seed_from_yaml(session)
    headers = _headers(session, username="cfg_admin_patch", is_admin=True)
    document = copy.deepcopy(load_yaml_documents()["field_survey"])
    document["main_params"]["discovery_chance"] = 0.66

    response = client.patch(
        f"{ADMIN}/documents/field_survey",
        headers=headers,
        json={"data": document, "base_version": 1},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["version"] == 2
    assert body["documents"]["field_survey"]["main_params"]["discovery_chance"] == 0.66
    assert body["documents"]["leveling"] == load_yaml_documents()["leveling"]


def test_patch_document_defaults_the_note(client, session) -> None:
    seed_from_yaml(session)
    headers = _headers(session, username="cfg_admin_patchnote", is_admin=True)
    document = copy.deepcopy(load_yaml_documents()["field_survey"])
    document["main_params"]["discovery_chance"] = 0.44

    client.patch(
        f"{ADMIN}/documents/field_survey",
        headers=headers,
        json={"data": document, "base_version": 1},
    )

    latest = client.get(f"{ADMIN}/revisions", headers=headers).json()[0]
    assert latest["note"] == "edit field_survey"


def test_patch_unknown_document_404s(client, session) -> None:
    seed_from_yaml(session)
    headers = _headers(session, username="cfg_admin_nodoc", is_admin=True)

    response = client.patch(
        f"{ADMIN}/documents/not_a_document", headers=headers, json={"data": {}}
    )

    assert response.status_code == 404


def test_patch_rejects_a_locked_path(client, session) -> None:
    seed_from_yaml(session)
    headers = _headers(session, username="cfg_admin_patchlock", is_admin=True)
    document = copy.deepcopy(load_yaml_documents()["leveling"])
    document["career_titles"][0] = "Supreme Dino Boss"

    response = client.patch(
        f"{ADMIN}/documents/leveling",
        headers=headers,
        json={"data": document, "base_version": 1},
    )

    assert response.status_code == 400
    assert "career_titles" in response.json()["detail"]


def test_patch_before_seeding_404s(client, session) -> None:
    headers = _headers(session, username="cfg_admin_patchempty", is_admin=True)

    response = client.patch(
        f"{ADMIN}/documents/field_survey", headers=headers, json={"data": {}}
    )

    assert response.status_code == 404


# --------------------------------------------------------------------------
# Admin rollback
# --------------------------------------------------------------------------


def test_rollback_republishes_old_content_as_a_new_version(client, session) -> None:
    seed_from_yaml(session)
    baseline = load_yaml_documents()["field_survey"]["main_params"][
        "discovery_chance"
    ]
    publish_documents(session, documents=_tweaked(0.95), base_version=1)
    headers = _headers(session, username="cfg_admin_roll", is_admin=True)

    response = client.post(
        f"{ADMIN}/rollback", headers=headers, json={"to_version": 1, "note": "undo"}
    )

    assert response.status_code == 200
    body = response.json()
    assert body["version"] == 3
    assert (
        body["documents"]["field_survey"]["main_params"]["discovery_chance"]
        == baseline
    )


def test_rollback_to_unknown_version_404s(client, session) -> None:
    seed_from_yaml(session)
    headers = _headers(session, username="cfg_admin_rollmiss", is_admin=True)

    response = client.post(
        f"{ADMIN}/rollback", headers=headers, json={"to_version": 42}
    )

    assert response.status_code == 404


# --------------------------------------------------------------------------
# End to end
# --------------------------------------------------------------------------


def test_admin_publish_is_visible_to_the_public_endpoint(
    client, session, db_source
) -> None:
    """The whole point of the feature: an admin edit reaches the app."""
    seed_from_yaml(session)
    provider.invalidate_game_config_cache()
    assert client.get(PUBLIC).json()["version"] == 1

    headers = _headers(session, username="cfg_admin_e2e", is_admin=True)
    client.put(
        ADMIN, headers=headers, json={"documents": _tweaked(0.73), "base_version": 1}
    )

    body = client.get(PUBLIC).json()
    assert body["version"] == 2
    assert (
        body["documents"]["field_survey"]["main_params"]["discovery_chance"] == 0.73
    )
