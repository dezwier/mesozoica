"""Tests for shared curated image path resolution."""

from __future__ import annotations

from pathlib import Path

import app.core.config as config_module
from app.services.curated_image_service.common import (
    resolve_curated_storage_dir,
    resolve_local_source_dir_for_sync,
)
from app.services.dinosaur_image_service.sync import resolve_local_source_dir_for_sync as resolve_dino_source
from app.services.fossil_image_service.sync import resolve_local_source_dir_for_sync as resolve_fossil_source
from app.services.site_type_image_service.sync import resolve_local_source_dir_for_sync as resolve_site_type_source


def test_resolve_curated_storage_dir_uses_explicit_server_path():
    path = resolve_curated_storage_dir(
        configured_dir="/data/dinosaur-images",
        default_relative="../dinosaur-images",
        data_root="",
        subdir_name="dinosaur-images",
    )
    assert path == Path("/data/dinosaur-images")


def test_resolve_curated_storage_dir_uses_data_root_for_defaults(monkeypatch):
    monkeypatch.setattr(config_module.settings, "curated_images_data_root", "/data")
    monkeypatch.setattr(config_module.settings, "fossil_images_dir", "../fossil-images")

    assert config_module.settings.resolved_fossil_images_dir == Path("/data/fossil-images")


def test_resolve_curated_storage_dir_explicit_overrides_data_root():
    path = resolve_curated_storage_dir(
        configured_dir="/data/dinosaur-images",
        default_relative="../dinosaur-images",
        data_root="/data",
        subdir_name="dinosaur-images",
    )
    assert path == Path("/data/dinosaur-images")


def test_resolve_local_source_dir_ignores_server_storage_path(monkeypatch, tmp_path: Path):
    repo_images = tmp_path / "fossil-images"
    repo_images.mkdir()
    (repo_images / "139292.png").write_bytes(b"x")

    monkeypatch.setenv("FOSSIL_IMAGES_DIR", "/data/fossil-images")
    monkeypatch.setenv("FOSSIL_IMAGES_SOURCE_DIR", str(repo_images))

    assert resolve_fossil_source() == repo_images.resolve()
    assert resolve_local_source_dir_for_sync(
        source_env_var="FOSSIL_IMAGES_SOURCE_DIR",
        default_repo_subdir="fossil-images",
    ) == repo_images.resolve()


def test_resolve_dino_source_ignores_server_storage_path(monkeypatch, tmp_path: Path):
    repo_images = tmp_path / "dinosaur-images"
    repo_images.mkdir()
    (repo_images / "Tyrannosaurus.webp").write_bytes(b"x")

    monkeypatch.setenv("DINOSAUR_IMAGES_DIR", "/data/dinosaur-images")
    monkeypatch.setenv("DINOSAUR_IMAGES_SOURCE_DIR", str(repo_images))

    assert resolve_dino_source() == repo_images.resolve()


def test_resolve_site_type_source_uses_repo_subdir(monkeypatch, tmp_path: Path):
    repo_images = tmp_path / "site-type-images"
    repo_images.mkdir()
    (repo_images / "1.png").write_bytes(b"x")

    monkeypatch.setenv("SITE_TYPE_IMAGES_SOURCE_DIR", str(repo_images))

    assert resolve_site_type_source() == repo_images.resolve()
