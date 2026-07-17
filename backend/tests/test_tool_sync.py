"""Tests for tool catalog sync."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from sqlmodel import Session, select

from app.models.tool import Tool
from app.services.tool_service.sync import DEFAULT_TOOLS_JSON, sync_tools


def _write_tools_json(path: Path, entries: list[dict]) -> None:
    path.write_text(json.dumps(entries), encoding="utf-8")


def test_sync_tools_inserts_from_json(session: Session, tmp_path: Path):
    json_path = tmp_path / "tools.json"
    _write_tools_json(
        json_path,
        [
            {
                "name": "Orbit Survey",
                "category": "prospecting",
                "scientific_tool": "satellite imagery",
                "description": "Identifies exposed formations.",
                "rarity": 2,
            }
        ],
    )

    summary = sync_tools(session, json_path=json_path)

    assert summary.counters.inserted == 1
    row = session.exec(select(Tool).where(Tool.name == "Orbit Survey")).one()
    assert row.category == "prospecting"
    assert row.scientific_tool == "satellite imagery"
    assert row.rarity == 2


def test_sync_tools_preserves_main_image_url_on_update(session: Session, tmp_path: Path):
    json_path = tmp_path / "tools.json"
    session.add(
        Tool(
            name="Geo Hammer",
            category="excavation",
            scientific_tool="geological hammer",
            description="Old description.",
            rarity=1,
            main_image_url="https://example.com/media/tools/Geo Hammer.png?v=abc",
        )
    )
    session.commit()

    _write_tools_json(
        json_path,
        [
            {
                "name": "Geo Hammer",
                "category": "excavation",
                "scientific_tool": "geological hammer",
                "description": "Updated description.",
                "rarity": 1,
            }
        ],
    )

    summary = sync_tools(session, json_path=json_path)

    assert summary.counters.updated == 1
    row = session.exec(select(Tool).where(Tool.name == "Geo Hammer")).one()
    assert row.description == "Updated description."
    assert row.main_image_url == "https://example.com/media/tools/Geo Hammer.png?v=abc"


def test_sync_tools_filter_by_name(session: Session, tmp_path: Path):
    json_path = tmp_path / "tools.json"
    _write_tools_json(
        json_path,
        [
            {
                "name": "Orbit Survey",
                "category": "prospecting",
                "scientific_tool": "satellite imagery",
                "description": "A",
                "rarity": 2,
            },
            {
                "name": "Geo Hammer",
                "category": "excavation",
                "scientific_tool": "geological hammer",
                "description": "B",
                "rarity": 1,
            },
        ],
    )

    summary = sync_tools(session, json_path=json_path, tools=["Geo Hammer"])

    assert summary.counters.inserted == 1
    assert session.exec(select(Tool)).all()[0].name == "Geo Hammer"


def test_sync_tools_prune(session: Session, tmp_path: Path):
    json_path = tmp_path / "tools.json"
    session.add(
        Tool(
            name="Stale Tool",
            category="analysis",
            scientific_tool="microscope",
            description="Gone.",
            rarity=1,
        )
    )
    session.commit()

    _write_tools_json(
        json_path,
        [
            {
                "name": "Orbit Survey",
                "category": "prospecting",
                "scientific_tool": "satellite imagery",
                "description": "A",
                "rarity": 2,
            }
        ],
    )

    summary = sync_tools(session, json_path=json_path, prune=True)

    assert summary.counters.inserted == 1
    assert summary.counters.pruned == 1
    names = {row.name for row in session.exec(select(Tool)).all()}
    assert names == {"Orbit Survey"}


def test_default_tools_json_exists():
    assert DEFAULT_TOOLS_JSON.is_file()
    entries = json.loads(DEFAULT_TOOLS_JSON.read_text(encoding="utf-8"))
    assert len(entries) == 50
