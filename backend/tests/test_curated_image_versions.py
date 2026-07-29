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


def test_resolve_generation_version_auto_increments(tmp_path: Path):
    from app.services.curated_image_service.versions import (
        ensure_version_meta,
        resolve_generation_version,
    )

    assert resolve_generation_version(tmp_path) == "v1"
    ensure_version_meta(
        tmp_path / "v1",
        default_prompt="p1",
        run_date=datetime(2025, 1, 1, tzinfo=timezone.utc),
    )
    assert resolve_generation_version(tmp_path) == "v2"
    ensure_version_meta(
        tmp_path / "v2",
        default_prompt="p2",
        run_date=datetime(2026, 1, 1, tzinfo=timezone.utc),
    )
    assert resolve_generation_version(tmp_path) == "v3"
    assert resolve_generation_version(tmp_path, version=1) == "v1"
    assert resolve_generation_version(tmp_path, version="v2") == "v2"


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


def test_resolve_dinosaur_card_image_url_catalog_forces_v1(tmp_path: Path, monkeypatch):
    import app.core.config as config_module
    from app.services.curated_image_service.resolve import resolve_dinosaur_card_image_url

    root = tmp_path / "dinosaurs"
    v1 = root / "v1"
    v2 = root / "v2"
    v1.mkdir(parents=True)
    v2.mkdir(parents=True)
    (v1 / "Tyrannosaurus.png").write_bytes(b"v1")
    (v2 / "Tyrannosaurus.png").write_bytes(b"v2")
    (v1 / "meta.yaml").write_text(
        "run_date: '2025-01-01T00:00:00+00:00'\nprompt: p\n", encoding="utf-8"
    )
    (v2 / "meta.yaml").write_text(
        "run_date: '2026-01-01T00:00:00+00:00'\nprompt: p\n", encoding="utf-8"
    )

    monkeypatch.setattr(config_module.settings, "dinosaur_images_dir", str(root))
    monkeypatch.setattr(config_module.settings, "public_base_url", "https://example.com")

    catalog = resolve_dinosaur_card_image_url(
        dinosaur_name="Tyrannosaurus",
        force_v1=True,
        fallback_url="https://fallback",
    )
    assert catalog is not None
    assert "/media/dinosaurs/v1/Tyrannosaurus.png" in catalog

    inventory = resolve_dinosaur_card_image_url(
        dinosaur_name="Tyrannosaurus",
        as_of=datetime(2026, 6, 1, tzinfo=timezone.utc),
        force_v1=False,
        fallback_url="https://fallback",
    )
    assert inventory is not None
    assert "/media/dinosaurs/v2/Tyrannosaurus.png" in inventory
