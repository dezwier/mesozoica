"""Tests for versioned curated site-type / tool images."""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

from app.services.curated_image_service.versions import (
    BACKFILL_RUN_DATE,
    ensure_version_meta,
    load_image_versions,
    migrate_flat_images_to_v1,
    normalize_version_name,
    pick_version_for_date,
    safe_versioned_relative_path,
)
from app.services.image_generation_service.prompting import site_type_image_prompt_template


def test_normalize_version_name():
    assert normalize_version_name(None) == "v1"
    assert normalize_version_name("2") == "v2"
    assert normalize_version_name("v3") == "v3"
    assert normalize_version_name(4) == "v4"


def test_safe_versioned_relative_path():
    assert safe_versioned_relative_path("v1/cretaceous_claystone.png") == (
        "v1/cretaceous_claystone.png"
    )
    assert safe_versioned_relative_path("V2/Orbit Survey.png") == "v2/Orbit Survey.png"


def test_safe_versioned_relative_path_rejects_traversal():
    import pytest

    with pytest.raises(ValueError):
        safe_versioned_relative_path("../v1/x.png")
    with pytest.raises(ValueError):
        safe_versioned_relative_path("v1/../x.png")
    with pytest.raises(ValueError):
        safe_versioned_relative_path("flat.png")


def test_migrate_flat_images_to_v1(tmp_path: Path):
    root = tmp_path / "site-types"
    root.mkdir()
    (root / "cretaceous_sandstone.png").write_bytes(b"img")
    (root / "README.md").write_text("keep", encoding="utf-8")

    summary = migrate_flat_images_to_v1(
        root,
        default_prompt=site_type_image_prompt_template(),
        backfill_run_date=BACKFILL_RUN_DATE,
    )
    assert summary["moved"] == 1
    assert not (root / "cretaceous_sandstone.png").exists()
    assert (root / "v1" / "cretaceous_sandstone.png").read_bytes() == b"img"
    assert (root / "README.md").exists()

    versions = load_image_versions(root)
    assert len(versions) == 1
    assert versions[0].name == "v1"
    assert versions[0].run_date == BACKFILL_RUN_DATE
    assert versions[0].prompt and "{rock_type}" in versions[0].prompt


def test_ensure_version_meta_preserves_prompt_and_run_date(tmp_path: Path):
    version_path = tmp_path / "v2"
    ensure_version_meta(
        version_path,
        default_prompt="first prompt {rock_type}",
        run_date=datetime(2025, 1, 1, tzinfo=timezone.utc),
    )
    ensure_version_meta(
        version_path,
        default_prompt="second prompt should not overwrite",
        run_date=datetime(2026, 1, 1, tzinfo=timezone.utc),
        preserve_existing_run_date=True,
    )
    versions = load_image_versions(tmp_path)
    assert versions[0].prompt == "first prompt {rock_type}"
    assert versions[0].run_date == datetime(2025, 1, 1, tzinfo=timezone.utc)


def test_pick_version_for_date_selects_newest_eligible(tmp_path: Path):
    ensure_version_meta(
        tmp_path / "v1",
        default_prompt="p1",
        run_date=datetime(2025, 1, 1, tzinfo=timezone.utc),
    )
    ensure_version_meta(
        tmp_path / "v2",
        default_prompt="p2",
        run_date=datetime(2026, 1, 1, tzinfo=timezone.utc),
    )
    versions = load_image_versions(tmp_path)

    early = pick_version_for_date(
        versions,
        as_of=datetime(2025, 4, 1, tzinfo=timezone.utc),
    )
    assert early is not None and early.name == "v1"

    late = pick_version_for_date(
        versions,
        as_of=datetime(2026, 2, 1, tzinfo=timezone.utc),
    )
    assert late is not None and late.name == "v2"

    forced = pick_version_for_date(versions, as_of=late.run_date, force_v1=True)
    assert forced is not None and forced.name == "v1"
