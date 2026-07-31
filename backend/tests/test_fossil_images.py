"""Tests for curated fossil card images."""

from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session

import app.core.config as config_module
from app.core.app_factory import create_app
from app.models.fossil import Fossil
from app.services.curated_image_service.versions import ORIGINAL_VERSION
from app.services.fossil_image_service.sync import (
    build_curated_image_url,
    file_content_version,
    is_curated_image_url,
    match_image_files,
    needs_image_resync,
    resolve_local_source_dir_for_sync,
    upload_file_to_railway,
)


def _stub_meta_and_prune(monkeypatch, sync_module) -> None:
    monkeypatch.setattr(
        sync_module,
        "sync_meta_and_prune_remote",
        lambda **kwargs: {
            "meta_uploaded": 0,
            "remote": 0,
            "kept": 0,
            "pruned": 0,
        },
    )
    monkeypatch.setattr(
        sync_module,
        "sync_album_thumb_for_image",
        lambda **kwargs: False,
    )


def test_build_curated_image_url():
    assert (
        build_curated_image_url("https://example.com", f"{ORIGINAL_VERSION}/139292.webp")
        == f"https://example.com/media/fossils/{ORIGINAL_VERSION}/139292.webp"
    )
    assert (
        build_curated_image_url(
            "https://example.com",
            f"{ORIGINAL_VERSION}/139292.webp",
            version="abc123",
        )
        == f"https://example.com/media/fossils/{ORIGINAL_VERSION}/139292.webp?v=abc123"
    )


def test_is_curated_image_url():
    assert is_curated_image_url(
        f"https://mesozoica-production.up.railway.app/media/fossils/{ORIGINAL_VERSION}/139292.webp"
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
    assert (images_dir / ORIGINAL_VERSION / "139292.png").read_bytes() == b"image-bytes"


def test_upload_file_to_railway_dry_run(tmp_path: Path):
    local = tmp_path / "139292.png"
    local.write_bytes(b"x")
    upload_file_to_railway(
        local_path=local,
        remote_filename=f"{ORIGINAL_VERSION}/139292.png",
        public_base_url="https://example.com",
        sync_secret="",
        dry_run=True,
    )


def _seed_original_image(images_dir: Path, fossil_id: int = 139292, content: bytes = b"x") -> Path:
    version_dir = images_dir / ORIGINAL_VERSION
    version_dir.mkdir(parents=True, exist_ok=True)
    (version_dir / "meta.yaml").write_text(
        "run_date: '2025-01-01T00:00:00+00:00'\nprompt: p\n",
        encoding="utf-8",
    )
    path = version_dir / f"{fossil_id}.png"
    path.write_bytes(content)
    return path


def test_run_sync_updates_main_image_url(
    session: Session,
    tmp_path: Path,
    monkeypatch,
):
    from scripts import sync_fossil_images as sync_module

    _stub_meta_and_prune(monkeypatch, sync_module)
    images_dir = tmp_path / "images"
    image_path = _seed_original_image(images_dir)

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
        f"https://example.com/media/fossils/{ORIGINAL_VERSION}/139292.png"
        f"?v={file_content_version(image_path)}"
    )


def test_run_sync_skips_existing_remote_images(
    session: Session,
    tmp_path: Path,
    monkeypatch,
):
    from scripts import sync_fossil_images as sync_module

    _stub_meta_and_prune(monkeypatch, sync_module)
    images_dir = tmp_path / "images"
    image_path = _seed_original_image(images_dir)
    relative = f"{ORIGINAL_VERSION}/139292.png"

    row = Fossil(id=139292, dinosaur_id=1, identified_name="Tyrannosaurus rex")
    row.main_image_url = build_curated_image_url(
        "https://example.com",
        relative,
        version=file_content_version(image_path),
    )
    session.add(row)
    session.commit()

    monkeypatch.setattr(config_module.settings, "public_base_url", "https://example.com")
    monkeypatch.setenv("FOSSIL_IMAGES_SOURCE_DIR", str(images_dir))
    upload_calls: list[str] = []

    def fake_upload(**kwargs):
        upload_calls.append(kwargs["remote_filename"])

    monkeypatch.setattr(sync_module, "upload_file_to_railway", fake_upload)
    monkeypatch.setattr(
        "app.services.curated_image_service.common.head_remote_curated_image",
        lambda **kwargs: (True, image_path.stat().st_mtime + 60),
    )
    monkeypatch.setenv("ALLOW_LOCAL_CRON", "1")

    assert sync_module.run_sync(dry_run=False, overwrite=False) == 0
    assert upload_calls == []

    session.refresh(row)
    assert row.main_image_url == build_curated_image_url(
        "https://example.com",
        relative,
        version=file_content_version(image_path),
    )


def test_run_sync_resyncs_when_local_is_newer_than_remote(
    session: Session,
    tmp_path: Path,
    monkeypatch,
):
    from scripts import sync_fossil_images as sync_module

    _stub_meta_and_prune(monkeypatch, sync_module)
    images_dir = tmp_path / "images"
    image_path = _seed_original_image(images_dir, content=b"new-image-bytes")
    relative = f"{ORIGINAL_VERSION}/139292.png"

    row = Fossil(id=139292, dinosaur_id=1, identified_name="Tyrannosaurus rex")
    row.main_image_url = (
        f"https://example.com/media/fossils/{ORIGINAL_VERSION}/139292.png?v=9dd4e461268c"
    )
    session.add(row)
    session.commit()

    monkeypatch.setattr(config_module.settings, "public_base_url", "https://example.com")
    monkeypatch.setenv("FOSSIL_IMAGES_SOURCE_DIR", str(images_dir))
    upload_calls: list[str] = []

    def fake_upload(**kwargs):
        upload_calls.append(kwargs["remote_filename"])

    monkeypatch.setattr(sync_module, "upload_file_to_railway", fake_upload)
    monkeypatch.setattr(
        "app.services.curated_image_service.common.head_remote_curated_image",
        lambda **kwargs: (True, image_path.stat().st_mtime - 60),
    )
    monkeypatch.setenv("ALLOW_LOCAL_CRON", "1")

    assert sync_module.run_sync(dry_run=False, overwrite=False) == 0
    assert upload_calls == [relative]

    session.refresh(row)
    assert row.main_image_url == (
        f"https://example.com/media/fossils/{relative}"
        f"?v={file_content_version(image_path)}"
    )
    assert row.main_image_url != (
        f"https://example.com/media/fossils/{ORIGINAL_VERSION}/139292.png?v=9dd4e461268c"
    )


def test_needs_image_resync_uses_remote_mtime(tmp_path: Path, monkeypatch):
    local = tmp_path / "139292.png"
    local.write_bytes(b"new")
    relative = f"{ORIGINAL_VERSION}/139292.png"
    local_mtime = local.stat().st_mtime

    monkeypatch.setattr(
        "app.services.curated_image_service.common.head_remote_curated_image",
        lambda **kwargs: (True, local_mtime - 60),
    )
    assert needs_image_resync(
        overwrite=False,
        local_path=local,
        main_image_url=f"https://example.com/media/fossils/{relative}?v=oldhash",
        public_base_url="https://example.com",
        filename=relative,
    )

    monkeypatch.setattr(
        "app.services.curated_image_service.common.head_remote_curated_image",
        lambda **kwargs: (True, local_mtime + 60),
    )
    assert not needs_image_resync(
        overwrite=False,
        local_path=local,
        main_image_url=build_curated_image_url(
            "https://example.com",
            relative,
            version=file_content_version(local),
        ),
        public_base_url="https://example.com",
        filename=relative,
    )


def test_run_sync_overwrite_uploads_existing_remote_images(
    session: Session,
    tmp_path: Path,
    monkeypatch,
):
    from scripts import sync_fossil_images as sync_module

    _stub_meta_and_prune(monkeypatch, sync_module)
    images_dir = tmp_path / "images"
    image_path = _seed_original_image(images_dir)
    relative = f"{ORIGINAL_VERSION}/139292.png"

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
    assert upload_calls == [relative]

    session.refresh(row)
    assert row.main_image_url == (
        f"https://example.com/media/fossils/{relative}"
        f"?v={file_content_version(image_path)}"
    )


def test_run_sync_clears_curated_url_when_local_file_missing(
    session: Session,
    tmp_path: Path,
    monkeypatch,
):
    from scripts import sync_fossil_images as sync_module

    _stub_meta_and_prune(monkeypatch, sync_module)
    images_dir = tmp_path / "images"
    image_path = _seed_original_image(images_dir)
    relative = f"{ORIGINAL_VERSION}/139292.png"

    synced = Fossil(id=139292, dinosaur_id=1, identified_name="Tyrannosaurus rex")
    stale = Fossil(
        id=219975,
        dinosaur_id=1,
        identified_name="Tyrannosaurus rex",
        main_image_url=f"https://example.com/media/fossils/{ORIGINAL_VERSION}/219975.png?v=oldhash",
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
        f"https://example.com/media/fossils/{relative}"
        f"?v={file_content_version(image_path)}"
    )
    assert stale.main_image_url is None


def test_resolve_local_source_dir_for_sync_uses_repo_folder(monkeypatch, tmp_path: Path):
    repo_images = tmp_path / "images" / "fossils"
    repo_images.mkdir(parents=True)
    monkeypatch.setenv("FOSSIL_IMAGES_SOURCE_DIR", str(repo_images))
    monkeypatch.setenv("FOSSIL_IMAGES_DIR", "/data/images/fossils")

    assert resolve_local_source_dir_for_sync() == repo_images.resolve()
