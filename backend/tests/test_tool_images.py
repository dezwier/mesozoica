"""Tests for curated tool card images."""

from __future__ import annotations

from pathlib import Path

from app.services.tool_image_service.sync import (
    build_curated_image_url,
    is_curated_image_url,
    match_image_files,
)


def test_build_curated_image_url():
    assert (
        build_curated_image_url("https://example.com", "Orbit Survey.png")
        == "https://example.com/media/tools/Orbit%20Survey.png"
    )


def test_is_curated_image_url():
    assert is_curated_image_url(
        "https://mesozoica-production.up.railway.app/media/tools/Orbit Survey.png"
    )
    assert not is_curated_image_url(None)


def test_match_image_files_case_insensitive():
    files = [Path("geo hammer.png")]
    matched, unmatched = match_image_files(files, {"Geo Hammer"})
    assert len(matched) == 1
    assert matched[0].tool_name == "Geo Hammer"
    assert matched[0].filename == "Geo Hammer.png"
    assert unmatched == []
