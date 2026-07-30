"""Tests for curated site-type card images."""

from __future__ import annotations

from pathlib import Path

from sqlmodel import Session

from app.models.site_type import SiteType
from app.services.site_type_image_service.sync import (
    match_image_files,
    site_type_image_key,
)


def test_site_type_image_key_normalizes_period_and_rock_type():
    assert (
        site_type_image_key(period="Cretaceous", rock_type="Sandstone")
        == "cretaceous_sandstone"
    )
    assert (
        site_type_image_key(period="jurassic", rock_type="volcanic ash")
        == "jurassic_volcanic_ash"
    )


def test_match_image_files_by_period_rock_type_key():
    files = [
        Path("cretaceous_sandstone.png"),
        Path("unknown_pair.png"),
        Path("1.png"),
    ]
    site_types = [
        SiteType(id=1, period="cretaceous", rock_type="sandstone"),
        SiteType(id=2, period="jurassic", rock_type="mudstone"),
    ]
    matched, unmatched = match_image_files(files, site_types)
    assert len(matched) == 1
    assert matched[0].filename == "cretaceous_sandstone.png"
    assert matched[0].site_type_id == 1
    assert [path.name for path in unmatched] == ["unknown_pair.png", "1.png"]


def test_match_image_files_accepts_legacy_numeric_id_files():
    files = [Path("2.png")]
    site_types = [
        SiteType(id=1, period="cretaceous", rock_type="sandstone"),
        SiteType(id=2, period="jurassic", rock_type="mudstone"),
    ]
    matched, unmatched = match_image_files(files, site_types)
    assert len(matched) == 1
    assert matched[0].filename == "jurassic_mudstone.png"
    assert matched[0].site_type_id == 2
    assert unmatched == []


def test_match_image_files_accepts_legacy_sorted_order_index():
    files = [Path("1.png")]
    site_types = [
        SiteType(id=176, period="cretaceous", rock_type="breccia"),
        SiteType(id=177, period="cretaceous", rock_type="sandstone"),
    ]
    matched, unmatched = match_image_files(files, site_types)
    assert len(matched) == 1
    assert matched[0].filename == "cretaceous_breccia.png"
    assert matched[0].site_type_id == 176
    assert unmatched == []


def test_run_sync_clears_curated_url_when_local_file_missing(
    session: Session,
    tmp_path: Path,
    monkeypatch,
):
    import app.core.config as config_module
    from scripts import sync_site_type_images as sync_module

    images_dir = tmp_path / "images/site-types"
    v1 = images_dir / "Original"
    v1.mkdir(parents=True)
    (v1 / "cretaceous_sandstone.png").write_bytes(b"x")
    (v1 / "meta.yaml").write_text(
        "run_date: '2026-07-29T00:00:00+00:00'\nprompt: test\n",
        encoding="utf-8",
    )

    synced = SiteType(
        id=1,
        period="cretaceous",
        rock_type="sandstone",
    )
    stale = SiteType(
        id=2,
        period="jurassic",
        rock_type="mudstone",
        main_image_url="https://example.com/media/site-types/Original/jurassic_mudstone.png?v=old",
    )
    session.add(synced)
    session.add(stale)
    session.commit()

    monkeypatch.setattr(config_module.settings, "public_base_url", "https://example.com")
    monkeypatch.setenv("SITE_TYPE_IMAGES_SOURCE_DIR", str(images_dir))
    monkeypatch.setattr(sync_module, "upload_file_to_railway", lambda **kwargs: None)
    monkeypatch.setenv("ALLOW_LOCAL_CRON", "1")

    assert sync_module.run_sync(dry_run=False) == 0

    session.refresh(synced)
    session.refresh(stale)
    assert synced.main_image_url == (
        "https://example.com/media/site-types/Original/cretaceous_sandstone.png?v=9dd4e461268c"
    )
    assert stale.main_image_url is None


def test_run_rename_maps_legacy_id_files(session: Session, tmp_path: Path, monkeypatch):
    from scripts import rename_site_type_images as rename_module

    images_dir = tmp_path / "images/site-types"
    images_dir.mkdir(parents=True)
    (images_dir / "1.png").write_bytes(b"x")

    row = SiteType(id=1, period="cretaceous", rock_type="sandstone")
    session.add(row)
    session.commit()

    monkeypatch.setenv("SITE_TYPE_IMAGES_SOURCE_DIR", str(images_dir))
    monkeypatch.setenv("ALLOW_LOCAL_CRON", "1")

    assert rename_module.run_rename(dry_run=False) == 0
    assert not (images_dir / "1.png").exists()
    assert (images_dir / "cretaceous_sandstone.png").read_bytes() == b"x"
