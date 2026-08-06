"""Tests for named curated image version folders."""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

import pytest

from app.services.curated_image_service.versions import (
    BACKFILL_RUN_DATE,
    ORIGINAL_VERSION,
    SUMMER_26_VERSION,
    AUGUST_2026_VERSION,
    bundled_version_meta_dir,
    ensure_version_meta,
    latest_site_type_image_version,
    latest_version_by_run_date,
    latest_version_name_with_bundled,
    load_image_versions,
    migrate_flat_images_to_version,
    normalize_version_name,
    require_generation_version,
    resolve_versioned_image_path,
    safe_versioned_relative_path,
)
from app.services.image_generation_service.prompting import site_type_image_prompt_template


def test_normalize_version_name():
    assert normalize_version_name("Original") == "Original"
    assert normalize_version_name("Summer 26") == "Summer 26"
    assert normalize_version_name("v1") == ORIGINAL_VERSION
    assert normalize_version_name("v2") == SUMMER_26_VERSION
    with pytest.raises(ValueError):
        normalize_version_name(None)
    with pytest.raises(ValueError):
        normalize_version_name("")
    with pytest.raises(ValueError):
        normalize_version_name("../x")


def test_require_generation_version():
    assert require_generation_version("Summer 26") == "Summer 26"
    with pytest.raises(ValueError):
        require_generation_version(None)


def test_safe_versioned_relative_path():
    assert safe_versioned_relative_path("Original/cretaceous_claystone.png") == (
        "Original/cretaceous_claystone.png"
    )
    assert safe_versioned_relative_path("Summer 26/Orbit Survey.png") == (
        "Summer 26/Orbit Survey.png"
    )
    assert safe_versioned_relative_path("v1/x.png") == f"{ORIGINAL_VERSION}/x.png"


def test_safe_versioned_relative_path_rejects_traversal():
    with pytest.raises(ValueError):
        safe_versioned_relative_path("../Original/x.png")
    with pytest.raises(ValueError):
        safe_versioned_relative_path("Original/../x.png")
    with pytest.raises(ValueError):
        safe_versioned_relative_path("flat.png")


def test_migrate_flat_images_to_original(tmp_path: Path):
    root = tmp_path / "site-types"
    root.mkdir()
    (root / "cretaceous_sandstone.png").write_bytes(b"img")
    (root / "README.md").write_text("keep", encoding="utf-8")

    summary = migrate_flat_images_to_version(
        root,
        version_name=ORIGINAL_VERSION,
        default_prompt=site_type_image_prompt_template(),
        backfill_run_date=BACKFILL_RUN_DATE,
    )
    assert summary["moved"] == 1
    assert not (root / "cretaceous_sandstone.png").exists()
    assert (root / ORIGINAL_VERSION / "cretaceous_sandstone.png").read_bytes() == b"img"
    assert (root / "README.md").exists()

    versions = load_image_versions(root)
    assert len(versions) == 1
    assert versions[0].name == ORIGINAL_VERSION
    assert versions[0].run_date == BACKFILL_RUN_DATE
    assert versions[0].prompt and "{rock_type}" in versions[0].prompt


def test_ensure_version_meta_preserves_prompt_and_run_date(tmp_path: Path):
    version_path = tmp_path / SUMMER_26_VERSION
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


def test_latest_version_by_run_date(tmp_path: Path):
    ensure_version_meta(
        tmp_path / ORIGINAL_VERSION,
        default_prompt="p1",
        run_date=datetime(2025, 1, 1, tzinfo=timezone.utc),
    )
    ensure_version_meta(
        tmp_path / SUMMER_26_VERSION,
        default_prompt="p2",
        run_date=datetime(2026, 1, 1, tzinfo=timezone.utc),
    )
    latest = latest_version_by_run_date(tmp_path)
    assert latest is not None and latest.name == SUMMER_26_VERSION


def test_latest_version_name_with_bundled_when_storage_empty(tmp_path: Path):
    """Workers without a curated-image volume still resolve August 2026."""
    empty = tmp_path / "missing-volume"
    assert latest_version_name_with_bundled(empty, kind="site-types") == AUGUST_2026_VERSION


def test_bundled_site_type_run_dates_match_images_repo():
    """Bundled metas must stay in sync with images/site-types/*/meta.yaml."""
    import yaml

    # tests/ → backend/ → repo root
    repo_images = Path(__file__).resolve().parents[2] / "images" / "site-types"
    if not repo_images.is_dir():
        pytest.skip("repo images/site-types not present")
    bundled = bundled_version_meta_dir("site-types")
    for version_dir in sorted(repo_images.iterdir(), key=lambda p: p.name.lower()):
        meta = version_dir / "meta.yaml"
        if not meta.is_file():
            continue
        src = yaml.safe_load(meta.read_text(encoding="utf-8")) or {}
        dest_meta = bundled / version_dir.name / "meta.yaml"
        assert dest_meta.is_file(), (
            f"missing bundled meta for {version_dir.name}; "
            "run: make sync-bundled-version-meta"
        )
        dest = yaml.safe_load(dest_meta.read_text(encoding="utf-8")) or {}
        assert str(dest.get("run_date")) == str(src.get("run_date"))


def test_latest_site_type_image_version_prefers_august_2026():
    assert latest_site_type_image_version() == AUGUST_2026_VERSION


def test_resolve_versioned_image_path_by_name(tmp_path: Path):
    original = tmp_path / ORIGINAL_VERSION
    summer = tmp_path / SUMMER_26_VERSION
    original.mkdir(parents=True)
    summer.mkdir(parents=True)
    (original / "Tyrannosaurus.png").write_bytes(b"v1")
    (summer / "Tyrannosaurus.png").write_bytes(b"v2")
    (original / "meta.yaml").write_text(
        "run_date: '2025-01-01T00:00:00+00:00'\nprompt: p\n", encoding="utf-8"
    )
    (summer / "meta.yaml").write_text(
        "run_date: '2026-01-01T00:00:00+00:00'\nprompt: p\n", encoding="utf-8"
    )

    chosen = resolve_versioned_image_path(
        tmp_path, "Tyrannosaurus", version=SUMMER_26_VERSION, case_insensitive=True
    )
    assert chosen is not None
    assert chosen[0].name == SUMMER_26_VERSION
    assert chosen[1].read_bytes() == b"v2"

    catalog = resolve_versioned_image_path(
        tmp_path, "Tyrannosaurus", version=ORIGINAL_VERSION, case_insensitive=True
    )
    assert catalog is not None
    assert catalog[0].name == ORIGINAL_VERSION


def test_resolve_dinosaur_card_image_url_uses_version(tmp_path: Path, monkeypatch):
    import app.core.config as config_module
    from app.services.curated_image_service.resolve import resolve_dinosaur_card_image_url

    root = tmp_path / "dinosaurs"
    original = root / ORIGINAL_VERSION
    summer = root / SUMMER_26_VERSION
    original.mkdir(parents=True)
    summer.mkdir(parents=True)
    (original / "Tyrannosaurus.png").write_bytes(b"v1")
    (summer / "Tyrannosaurus.png").write_bytes(b"v2")
    (original / "meta.yaml").write_text(
        "run_date: '2025-01-01T00:00:00+00:00'\nprompt: p\n", encoding="utf-8"
    )
    (summer / "meta.yaml").write_text(
        "run_date: '2026-01-01T00:00:00+00:00'\nprompt: p\n", encoding="utf-8"
    )

    monkeypatch.setattr(config_module.settings, "dinosaur_images_dir", str(root))
    monkeypatch.setattr(config_module.settings, "public_base_url", "https://example.com")

    catalog = resolve_dinosaur_card_image_url(
        dinosaur_name="Tyrannosaurus",
        version=ORIGINAL_VERSION,
        fallback_url="https://fallback",
    )
    assert catalog is not None
    assert "/media/dinosaurs/Original/Tyrannosaurus.png" in catalog

    inventory = resolve_dinosaur_card_image_url(
        dinosaur_name="Tyrannosaurus",
        version=SUMMER_26_VERSION,
        fallback_url="https://fallback",
    )
    assert inventory is not None
    assert "/media/dinosaurs/Summer%2026/Tyrannosaurus.png" in inventory
