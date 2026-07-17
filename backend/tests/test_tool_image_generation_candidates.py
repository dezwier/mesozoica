"""Tests for tool image generation candidate selection."""

from __future__ import annotations

from pathlib import Path

from sqlmodel import Session

from app.models.tool import Tool
from app.services.tool_image_generation_service.generate import _select_candidates


def test_select_candidates_skips_existing_local_image(
    session: Session, tmp_path: Path, monkeypatch
):
    session.add(
        Tool(
            name="Orbit Survey",
            category="prospecting",
            scientific_tool="satellite imagery",
            description="A",
            rarity=2,
        )
    )
    session.add(
        Tool(
            name="Geo Hammer",
            category="excavation",
            scientific_tool="geological hammer",
            description="B",
            rarity=1,
        )
    )
    session.commit()

    (tmp_path / "Orbit Survey.png").write_bytes(b"x")
    existing_stems = {"orbit survey"}

    candidates, skipped_existing = _select_candidates(
        session,
        output_dir=tmp_path,
        existing_stems=existing_stems,
    )

    assert skipped_existing == 1
    assert len(candidates) == 1
    assert candidates[0].name == "Geo Hammer"
