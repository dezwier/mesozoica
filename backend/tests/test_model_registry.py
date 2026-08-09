"""Persistence metadata registration remains explicit and fingerprinted."""

import hashlib
import json

from sqlmodel import SQLModel

import app.model_registry  # noqa: F401


EXPECTED_TABLES = {
    "dinosaur",
    "dinosaur_type",
    "dinosaur_type_revision",
    "field_ensure_job",
    "field_survey_job",
    "fossil",
    "game_config_release",
    "game_config_revision",
    "rag_source_snapshot",
    "site",
    "site_type",
    "tool",
    "tool_session",
    "tool_session_event",
    "tool_type",
    "user",
    "user_auth_identity",
    "user_device_token",
    "user_dinosaur",
    "user_fossil",
    "user_notification",
    "user_site",
    "user_tool",
    "user_user",
    "weather",
}


def test_feature_model_registry_registers_existing_tables() -> None:
    assert set(SQLModel.metadata.tables) == EXPECTED_TABLES


def test_sqlmodel_table_and_column_metadata_fingerprint() -> None:
    payload = []
    for name, table in sorted(SQLModel.metadata.tables.items()):
        columns = [
            (column.name, str(column.type), column.nullable, column.primary_key, column.unique)
            for column in table.columns
        ]
        payload.append((name, columns))
    fingerprint = hashlib.sha256(
        json.dumps(payload, sort_keys=True).encode()
    ).hexdigest()
    assert fingerprint == "4d3a7c1a0b6b13689a1679a3d5b14dd27b28ad7604c3784e095dc144d22e6449"
