"""Seeding the control board into the database."""

from __future__ import annotations

import copy

import pytest
from pydantic import ValidationError

from app.core.game_config import build_game_config, load_game_config, load_yaml_documents
from app.models.game_config_revision import GameConfigRevision
from app.services.game_config_service import (
    GameConfigConflict,
    GameConfigLocked,
    list_revisions,
    publish_documents,
    read_active_config,
    read_active_version,
    rollback_to_version,
    seed_from_yaml,
    validate_documents,
)
from app.services.game_config_service.prune import prune_revisions
from sqlmodel import select


def test_seed_creates_version_one(session) -> None:
    summary = seed_from_yaml(session)

    assert summary.created is True
    assert summary.version == 1
    assert summary.changed_doc_ids  # every document is new

    stored = read_active_config(session)
    assert stored is not None
    assert stored.version == 1
    assert stored.checksum == summary.checksum
    assert read_active_version(session) == (1, summary.checksum)


def test_seeded_documents_rebuild_the_same_config(session) -> None:
    """The drift guarantee: what we stored still parses to today's config."""
    seed_from_yaml(session)
    stored = read_active_config(session)
    assert stored is not None

    assert build_game_config(stored.documents) == load_game_config()


def test_reseed_is_a_no_op(session) -> None:
    seed_from_yaml(session)
    summary = seed_from_yaml(session)

    assert summary.created is False
    assert summary.version == 1
    assert summary.changed_doc_ids == []
    assert len(list_revisions(session)) == 1


def test_reseed_reports_drift_without_writing(session) -> None:
    seed_from_yaml(session)

    documents = copy.deepcopy(load_yaml_documents())
    documents["field_survey"]["main_params"]["discovery_chance"] = 0.42
    publish_documents(session, documents=documents, base_version=1, note="tweak")

    summary = seed_from_yaml(session)
    assert summary.created is False
    assert summary.version == 2
    assert summary.changed_doc_ids == ["field_survey"]


def test_force_reseed_publishes_a_new_revision(session) -> None:
    seed_from_yaml(session)

    documents = copy.deepcopy(load_yaml_documents())
    documents["field_survey"]["main_params"]["discovery_chance"] = 0.42
    publish_documents(session, documents=documents, base_version=1, note="tweak")

    summary = seed_from_yaml(session, force=True)
    assert summary.created is True
    assert summary.version == 3

    stored = read_active_config(session)
    assert stored is not None
    assert build_game_config(stored.documents) == load_game_config()


def test_dry_run_writes_nothing(session) -> None:
    summary = seed_from_yaml(session, dry_run=True)

    assert summary.dry_run is True
    assert summary.created is False
    assert read_active_config(session) is None
    assert session.exec(select(GameConfigRevision)).all() == []


def test_publish_bumps_version_by_one(session) -> None:
    seed_from_yaml(session)
    documents = copy.deepcopy(load_yaml_documents())
    documents["field_survey"]["main_params"]["discovery_chance"] = 0.5

    stored = publish_documents(session, documents=documents, base_version=1)

    assert stored.version == 2
    assert read_active_version(session) == (2, stored.checksum)
    revisions = list_revisions(session)
    assert [r.version for r in revisions] == [2, 1]
    assert revisions[0].is_active is True
    assert revisions[1].is_active is False


def test_stale_base_version_conflicts(session) -> None:
    seed_from_yaml(session)
    documents = copy.deepcopy(load_yaml_documents())
    documents["field_survey"]["main_params"]["discovery_chance"] = 0.5
    publish_documents(session, documents=documents, base_version=1)

    documents["field_survey"]["main_params"]["discovery_chance"] = 0.6
    with pytest.raises(GameConfigConflict):
        publish_documents(session, documents=documents, base_version=1)


def test_invalid_documents_do_not_create_a_revision(session) -> None:
    seed_from_yaml(session)
    documents = copy.deepcopy(load_yaml_documents())
    # weight_global/nearby/closest must sum to 1.0
    documents["site_generation"]["lazy"]["weight_global"] = 0.9

    with pytest.raises(ValidationError):
        publish_documents(session, documents=documents, base_version=1)

    assert read_active_version(session) == (1, read_active_config(session).checksum)
    assert len(list_revisions(session)) == 1


def test_missing_document_is_rejected(session) -> None:
    documents = copy.deepcopy(load_yaml_documents())
    del documents["leveling"]
    with pytest.raises(ValueError, match="Missing game config documents"):
        validate_documents(documents)


def test_locked_paths_reject_edits(session) -> None:
    seed_from_yaml(session)
    documents = copy.deepcopy(load_yaml_documents())
    documents["leveling"]["career_titles"][0] = "Supreme Dino Boss"

    with pytest.raises(GameConfigLocked, match="career_titles"):
        publish_documents(session, documents=documents, base_version=1)


def test_locked_paths_reject_skill_rename(session) -> None:
    seed_from_yaml(session)
    documents = copy.deepcopy(load_yaml_documents())
    documents["leveling"]["skills"][0]["id"] = "renamed_skill"

    with pytest.raises(GameConfigLocked, match="leveling/skills"):
        publish_documents(session, documents=documents, base_version=1)


def test_locked_paths_reject_palette_edits(session) -> None:
    seed_from_yaml(session)
    documents = copy.deepcopy(load_yaml_documents())
    documents["period_colors"]["site_markers"]["jurassic"] = "#123456"

    with pytest.raises(GameConfigLocked, match="period_colors"):
        publish_documents(session, documents=documents, base_version=1)


def test_locked_paths_reject_tool_prose_edits(session) -> None:
    seed_from_yaml(session)
    documents = copy.deepcopy(load_yaml_documents())
    documents["tool_actions"]["aerial_recon"]["stats_explanation"] = "new blurb"

    with pytest.raises(GameConfigLocked, match="stats_explanation"):
        publish_documents(session, documents=documents, base_version=1)


def test_unlocked_knob_next_to_a_locked_path_is_editable(session) -> None:
    """tool_actions mixes knobs and prose — only the prose is locked."""
    seed_from_yaml(session)
    documents = copy.deepcopy(load_yaml_documents())
    documents["tool_actions"]["aerial_recon"]["flight_speed_kmh"] = 55

    stored = publish_documents(session, documents=documents, base_version=1)
    assert stored.version == 2
    assert build_game_config(stored.documents).tool_actions.aerial_recon.flight_speed_kmh == 55


def test_rollback_creates_a_forward_revision(session) -> None:
    seed_from_yaml(session)
    v1 = read_active_config(session)
    assert v1 is not None

    documents = copy.deepcopy(load_yaml_documents())
    documents["field_survey"]["main_params"]["discovery_chance"] = 0.5
    publish_documents(session, documents=documents, base_version=1)

    restored = rollback_to_version(session, to_version=1)

    assert restored.version == 3
    assert restored.checksum == v1.checksum
    assert restored.documents == v1.documents
    assert [r.version for r in list_revisions(session)] == [3, 2, 1]


def test_rollback_unknown_version(session) -> None:
    seed_from_yaml(session)
    with pytest.raises(ValueError, match="unknown game config version"):
        rollback_to_version(session, to_version=99)


def test_prune_keeps_newest_and_active(session) -> None:
    seed_from_yaml(session)
    documents = copy.deepcopy(load_yaml_documents())
    for index in range(4):
        documents["field_survey"]["main_params"]["discovery_chance"] = 0.1 + index / 100
        publish_documents(session, documents=documents, base_version=1 + index)

    assert len(list_revisions(session)) == 5

    deleted = prune_revisions(session, keep=2)
    assert deleted == 3

    remaining = list_revisions(session)
    assert [r.version for r in remaining] == [5, 4]
    assert remaining[0].is_active is True
