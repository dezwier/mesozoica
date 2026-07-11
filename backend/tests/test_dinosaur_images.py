"""Tests for curated dinosaur card images."""

from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session

import app.core.config as config_module
from app.core.app_factory import create_app
from app.models.dinosaur import Dinosaur
from app.services.dinosaur_image_service.sync import (
    DEFAULT_PRODUCTION_BASE_URL,
    build_curated_image_url,
    is_curated_image_url,
    match_image_files,
    normalize_public_base_url,
    resolve_local_source_dir_for_sync,
    resolve_public_base_url_for_sync,
    scan_local_image_files,
    upload_file_to_railway,
)


def test_build_curated_image_url():
    assert (
        build_curated_image_url("https://example.com", "Tyrannosaurus.webp")
        == "https://example.com/media/dinosaurs/Tyrannosaurus.webp"
    )


def test_is_curated_image_url():
    assert is_curated_image_url(
        "https://mesozoica-production.up.railway.app/media/dinosaurs/Tyrannosaurus.webp"
    )
    assert not is_curated_image_url(
        "https://upload.wikimedia.org/wikipedia/commons/t-rex.jpg"
    )
    assert not is_curated_image_url(None)


def test_match_image_files_case_insensitive():
    files = [Path("triceratops.png")]
    matched, unmatched = match_image_files(files, {"Triceratops"})
    assert len(matched) == 1
    assert matched[0].dinosaur_name == "Triceratops"
    assert matched[0].filename == "Triceratops.png"
    assert unmatched == []


def test_match_image_files_exact_name():
    files = [
        Path("Tyrannosaurus.webp"),
        Path("Unknown.jpg"),
    ]
    matched, unmatched = match_image_files(files, {"Tyrannosaurus"})
    assert len(matched) == 1
    assert matched[0].dinosaur_name == "Tyrannosaurus"
    assert matched[0].filename == "Tyrannosaurus.webp"
    assert len(unmatched) == 1
    assert unmatched[0].name == "Unknown.jpg"


def test_scan_local_image_files(tmp_path: Path):
    (tmp_path / "Tyrannosaurus.webp").write_bytes(b"x")
    (tmp_path / "notes.txt").write_text("skip")
    (tmp_path / "Bad.gif").write_bytes(b"x")
    files = scan_local_image_files(tmp_path)
    assert [path.name for path in files] == ["Tyrannosaurus.webp"]


def test_normalize_public_base_url():
    assert normalize_public_base_url("https://example.com/") == "https://example.com"
    with pytest.raises(ValueError):
        normalize_public_base_url("")


def test_resolve_local_source_dir_for_sync_ignores_server_path(monkeypatch, tmp_path: Path):
    repo_images = tmp_path / "dinosaur-images"
    repo_images.mkdir()
    (repo_images / "Eoraptor.png").write_bytes(b"x")

    monkeypatch.setenv("DINOSAUR_IMAGES_DIR", "/data/dinosaur-images")
    monkeypatch.setenv("DINOSAUR_IMAGES_SOURCE_DIR", str(repo_images))

    assert resolve_local_source_dir_for_sync() == repo_images.resolve()
    assert scan_local_image_files(resolve_local_source_dir_for_sync())


def test_resolve_public_base_url_for_sync_defaults_to_production(monkeypatch):
    monkeypatch.setattr(config_module.settings, "public_base_url", "http://127.0.0.1:8000")
    monkeypatch.delenv("RAILWAY_PUBLIC_DOMAIN", raising=False)
    assert resolve_public_base_url_for_sync() == DEFAULT_PRODUCTION_BASE_URL


def test_resolve_public_base_url_for_sync_uses_railway_domain(monkeypatch):
    monkeypatch.setattr(config_module.settings, "public_base_url", "http://127.0.0.1:8000")
    monkeypatch.setenv("RAILWAY_PUBLIC_DOMAIN", "mesozoica-production.up.railway.app")
    assert (
        resolve_public_base_url_for_sync()
        == "https://mesozoica-production.up.railway.app"
    )


def test_serves_curated_image_from_static_mount(tmp_path: Path, monkeypatch):
    images_dir = tmp_path / "images"
    images_dir.mkdir()
    (images_dir / "Tyrannosaurus.webp").write_bytes(b"fake-image")

    monkeypatch.setattr(config_module.settings, "dinosaur_images_dir", str(images_dir))

    app = create_app()
    with TestClient(app) as client:
        response = client.get("/media/dinosaurs/Tyrannosaurus.webp")

    assert response.status_code == 200
    assert response.content == b"fake-image"


def test_missing_curated_image_returns_404(tmp_path: Path, monkeypatch):
    images_dir = tmp_path / "images"
    images_dir.mkdir()
    monkeypatch.setattr(config_module.settings, "dinosaur_images_dir", str(images_dir))

    app = create_app()
    with TestClient(app) as client:
        response = client.get("/media/dinosaurs/Missing.webp")

    assert response.status_code == 404


def test_upload_dinosaur_image_endpoint(tmp_path: Path, monkeypatch):
    images_dir = tmp_path / "images"
    monkeypatch.setattr(config_module.settings, "dinosaur_images_dir", str(images_dir))
    monkeypatch.setattr(config_module.settings, "dinosaur_image_sync_secret", "test-secret")

    app = create_app()
    with TestClient(app) as client:
        unauthorized = client.put(
            "/api/v1/admin/dinosaur-images/Triceratops.png",
            content=b"image-bytes",
        )
        assert unauthorized.status_code == 401

        response = client.put(
            "/api/v1/admin/dinosaur-images/Triceratops.png",
            content=b"image-bytes",
            headers={"X-Dinosaur-Image-Sync-Key": "test-secret"},
        )

    assert response.status_code == 204
    assert (images_dir / "Triceratops.png").read_bytes() == b"image-bytes"


def test_upload_file_to_railway_dry_run(tmp_path: Path):
    local = tmp_path / "Tyrannosaurus.webp"
    local.write_bytes(b"x")
    upload_file_to_railway(
        local_path=local,
        remote_filename="Tyrannosaurus.webp",
        public_base_url="https://example.com",
        sync_secret="",
        dry_run=True,
    )


def test_run_sync_updates_main_image_url(
    session: Session,
    tmp_path: Path,
    monkeypatch,
):
    from scripts import sync_dinosaur_images as sync_module

    images_dir = tmp_path / "images"
    images_dir.mkdir()
    (images_dir / "Tyrannosaurus.webp").write_bytes(b"x")

    row = Dinosaur(
        name="Tyrannosaurus",
        wikipedia_page_id=1,
        wikipedia_title="Tyrannosaurus",
    )
    session.add(row)
    session.commit()

    monkeypatch.setattr(config_module.settings, "dinosaur_images_dir", str(images_dir))
    monkeypatch.setattr(config_module.settings, "public_base_url", "https://example.com")
    monkeypatch.setattr(config_module.settings, "dinosaur_image_sync_secret", "secret")
    monkeypatch.setenv("DINOSAUR_IMAGES_SOURCE_DIR", str(images_dir))
    monkeypatch.setattr(
        sync_module,
        "upload_file_to_railway",
        lambda **kwargs: None,
    )
    monkeypatch.setenv("ALLOW_LOCAL_CRON", "1")

    assert sync_module.run_sync(dry_run=False) == 0

    session.refresh(row)
    assert (
        row.main_image_url
        == "https://example.com/media/dinosaurs/Tyrannosaurus.webp"
    )
