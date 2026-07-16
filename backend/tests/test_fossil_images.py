"""Tests for curated fossil card images."""

from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session

import app.core.config as config_module
from app.core.app_factory import create_app
from app.models.fossil import Fossil
from app.services.fossil_image_service.sync import (
    build_curated_image_url,
    file_content_version,
    is_curated_image_url,
    match_image_files,
    needs_image_resync,
    resolve_local_source_dir_for_sync,
    upload_file_to_railway,
)


def test_build_curated_image_url():
    assert (
        build_curated_image_url("https://example.com", "139292.webp")
        == "https://example.com/media/fossils/139292.webp"
    )
    assert (
        build_curated_image_url(
            "https://example.com",
            "139292.webp",
            version="abc123",
        )
        == "https://example.com/media/fossils/139292.webp?v=abc123"
    )


def test_is_curated_image_url():
    assert is_curated_image_url(
        "https://mesozoica-production.up.railway.app/media/fossils/139292.webp"
    )
    assert not is_curated_image_url(
        "https://mesozoica-production.up.railway.app/media/dinosaurs/Tyrannosaurus.webp"
    )
    assert not is_curated_image_url(None)


def test_match_image_files_by_occurrence_no():
    files = [Path("139292.png"), Path("not-a-number.png"), Path("999999.png")]
    matched, unmatched = match_image_files(files, {139292})
    assert len(matched) == 1
    assert matched[0].fossil_id == 139292
    assert matched[0].filename == "139292.png"
    assert [path.name for path in unmatched] == ["not-a-number.png", "999999.png"]


def test_upload_fossil_image_endpoint(tmp_path: Path, monkeypatch):
    images_dir = tmp_path / "images"
    monkeypatch.setattr(config_module.settings, "fossil_images_dir", str(images_dir))
    monkeypatch.setattr(config_module.settings, "fossil_image_sync_secret", "test-secret")

    app = create_app()
    with TestClient(app) as client:
        unauthorized = client.put(
            "/api/v1/admin/fossil-images/139292.png",
            content=b"image-bytes",
        )
        assert unauthorized.status_code == 401

        response = client.put(
            "/api/v1/admin/fossil-images/139292.png",
            content=b"image-bytes",
            headers={"X-Fossil-Image-Sync-Key": "test-secret"},
        )

    assert response.status_code == 204
    assert (images_dir / "139292.png").read_bytes() == b"image-bytes"


def test_upload_file_to_railway_dry_run(tmp_path: Path):
    local = tmp_path / "139292.png"
    local.write_bytes(b"x")
    upload_file_to_railway(
        local_path=local,
        remote_filename="139292.png",
        public_base_url="https://example.com",
        sync_secret="",
        dry_run=True,
    )


def test_run_sync_updates_main_image_url(
    session: Session,
    tmp_path: Path,
    monkeypatch,
):
    from scripts import sync_fossil_images as sync_module

    images_dir = tmp_path / "images"
    images_dir.mkdir()
    (images_dir / "139292.png").write_bytes(b"x")

    row = Fossil(id=139292, dinosaur_id=1, identified_name="Tyrannosaurus rex")
    session.add(row)
    session.commit()

    monkeypatch.setattr(config_module.settings, "fossil_images_dir", str(images_dir))
    monkeypatch.setattr(config_module.settings, "public_base_url", "https://example.com")
    monkeypatch.setattr(config_module.settings, "fossil_image_sync_secret", "secret")
    monkeypatch.setenv("FOSSIL_IMAGES_SOURCE_DIR", str(images_dir))
    monkeypatch.setattr(
        sync_module,
        "upload_file_to_railway",
        lambda **kwargs: None,
    )
    monkeypatch.setenv("ALLOW_LOCAL_CRON", "1")

    assert sync_module.run_sync(dry_run=False) == 0

    session.refresh(row)
    assert row.main_image_url == (
        "https://example.com/media/fossils/139292.png?v=9dd4e461268c"
    )


def test_run_sync_skips_existing_remote_images(
    session: Session,
    tmp_path: Path,
    monkeypatch,
):
    from scripts import sync_fossil_images as sync_module

    images_dir = tmp_path / "images"
    images_dir.mkdir()
    image_path = images_dir / "139292.png"
    image_path.write_bytes(b"x")

    row = Fossil(id=139292, dinosaur_id=1, identified_name="Tyrannosaurus rex")
    row.main_image_url = build_curated_image_url(
        "https://example.com",
        "139292.png",
        version=file_content_version(image_path),
    )
    session.add(row)
    session.commit()

    monkeypatch.setenv("FOSSIL_IMAGES_SOURCE_DIR", str(images_dir))
    upload_calls: list[str] = []

    def fake_upload(**kwargs):
        upload_calls.append(kwargs["remote_filename"])

    monkeypatch.setattr(sync_module, "upload_file_to_railway", fake_upload)
    monkeypatch.setenv("ALLOW_LOCAL_CRON", "1")

    assert sync_module.run_sync(dry_run=False, overwrite=False) == 0
    assert upload_calls == []

    session.refresh(row)
    assert row.main_image_url == (
        "https://example.com/media/fossils/139292.png?v=9dd4e461268c"
    )


def test_run_sync_resyncs_when_local_content_changed(
    session: Session,
    tmp_path: Path,
    monkeypatch,
):
    from scripts import sync_fossil_images as sync_module

    images_dir = tmp_path / "images"
    images_dir.mkdir()
    image_path = images_dir / "139292.png"
    image_path.write_bytes(b"new-image-bytes")

    row = Fossil(id=139292, dinosaur_id=1, identified_name="Tyrannosaurus rex")
    row.main_image_url = (
        "https://example.com/media/fossils/139292.png?v=9dd4e461268c"
    )
    session.add(row)
    session.commit()

    monkeypatch.setattr(config_module.settings, "public_base_url", "https://example.com")
    monkeypatch.setenv("FOSSIL_IMAGES_SOURCE_DIR", str(images_dir))
    upload_calls: list[str] = []

    def fake_upload(**kwargs):
        upload_calls.append(kwargs["remote_filename"])

    monkeypatch.setattr(sync_module, "upload_file_to_railway", fake_upload)
    monkeypatch.setenv("ALLOW_LOCAL_CRON", "1")

    assert sync_module.run_sync(dry_run=False, overwrite=False) == 0
    assert upload_calls == ["139292.png"]

    session.refresh(row)
    assert row.main_image_url == (
        f"https://example.com/media/fossils/139292.png?v={file_content_version(image_path)}"
    )
    assert row.main_image_url != (
        "https://example.com/media/fossils/139292.png?v=9dd4e461268c"
    )


def test_needs_image_resync_detects_stale_content(tmp_path: Path):
    local = tmp_path / "139292.png"
    local.write_bytes(b"new")
    assert needs_image_resync(
        overwrite=False,
        local_path=local,
        main_image_url="https://example.com/media/fossils/139292.png?v=oldhash",
        public_base_url="https://example.com",
        filename="139292.png",
    )
    assert not needs_image_resync(
        overwrite=False,
        local_path=local,
        main_image_url=build_curated_image_url(
            "https://example.com",
            "139292.png",
            version=file_content_version(local),
        ),
        public_base_url="https://example.com",
        filename="139292.png",
    )


def test_run_sync_overwrite_uploads_existing_remote_images(
    session: Session,
    tmp_path: Path,
    monkeypatch,
):
    from scripts import sync_fossil_images as sync_module

    images_dir = tmp_path / "images"
    images_dir.mkdir()
    (images_dir / "139292.png").write_bytes(b"x")

    row = Fossil(id=139292, dinosaur_id=1, identified_name="Tyrannosaurus rex")
    session.add(row)
    session.commit()

    monkeypatch.setattr(config_module.settings, "public_base_url", "https://example.com")
    monkeypatch.setenv("FOSSIL_IMAGES_SOURCE_DIR", str(images_dir))
    upload_calls: list[str] = []

    def fake_upload(**kwargs):
        upload_calls.append(kwargs["remote_filename"])

    monkeypatch.setattr(sync_module, "upload_file_to_railway", fake_upload)
    monkeypatch.setenv("ALLOW_LOCAL_CRON", "1")

    assert sync_module.run_sync(dry_run=False, overwrite=True) == 0
    assert upload_calls == ["139292.png"]

    session.refresh(row)
    assert row.main_image_url == (
        "https://example.com/media/fossils/139292.png?v=9dd4e461268c"
    )


def test_run_sync_clears_curated_url_when_local_file_missing(
    session: Session,
    tmp_path: Path,
    monkeypatch,
):
    from scripts import sync_fossil_images as sync_module

    images_dir = tmp_path / "images"
    images_dir.mkdir()
    (images_dir / "139292.png").write_bytes(b"x")

    synced = Fossil(id=139292, dinosaur_id=1, identified_name="Tyrannosaurus rex")
    stale = Fossil(
        id=219975,
        dinosaur_id=1,
        identified_name="Tyrannosaurus rex",
        main_image_url="https://example.com/media/fossils/219975.png?v=oldhash",
    )
    session.add(synced)
    session.add(stale)
    session.commit()

    monkeypatch.setattr(config_module.settings, "public_base_url", "https://example.com")
    monkeypatch.setenv("FOSSIL_IMAGES_SOURCE_DIR", str(images_dir))
    monkeypatch.setattr(sync_module, "upload_file_to_railway", lambda **kwargs: None)
    monkeypatch.setenv("ALLOW_LOCAL_CRON", "1")

    assert sync_module.run_sync(dry_run=False) == 0

    session.refresh(synced)
    session.refresh(stale)
    assert synced.main_image_url == (
        "https://example.com/media/fossils/139292.png?v=9dd4e461268c"
    )
    assert stale.main_image_url is None


def test_resolve_local_source_dir_for_sync_uses_repo_folder(monkeypatch, tmp_path: Path):
    repo_images = tmp_path / "fossil-images"
    repo_images.mkdir()
    monkeypatch.setenv("FOSSIL_IMAGES_SOURCE_DIR", str(repo_images))
    monkeypatch.setenv("FOSSIL_IMAGES_DIR", "/data/fossil-images")

    assert resolve_local_source_dir_for_sync() == repo_images.resolve()
