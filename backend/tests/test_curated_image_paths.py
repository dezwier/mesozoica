"""Tests for shared curated image path resolution."""

from __future__ import annotations

from pathlib import Path

import app.core.config as config_module
from app.services.curated_image_service.common import (
    file_content_version,
    needs_curated_image_resync,
    remote_curated_image_exists,
    resolve_curated_storage_dir,
    resolve_local_source_dir_for_sync,
)
from app.services.dinosaur_image_service.sync import resolve_local_source_dir_for_sync as resolve_dino_source
from app.services.fossil_image_service.sync import resolve_local_source_dir_for_sync as resolve_fossil_source
from app.services.site_type_image_service.sync import resolve_local_source_dir_for_sync as resolve_site_type_source
from app.services.tool_image_service.sync import resolve_local_source_dir_for_sync as resolve_tool_source


def test_remote_curated_image_exists(monkeypatch):
    class FakeResponse:
        def __init__(self, status_code: int, headers: dict[str, str] | None = None):
            self.status_code = status_code
            self.headers = headers or {}

    def fake_head(url: str, **kwargs):
        if url.endswith("/media/dinosaurs/Tyrannosaurus.webp"):
            return FakeResponse(200, {"last-modified": "Thu, 01 Jan 2026 00:00:00 GMT"})
        if url.endswith("/media/tools/Orbit%20Survey.png"):
            return FakeResponse(200)
        return FakeResponse(404)

    monkeypatch.setattr(
        "app.services.curated_image_service.common.httpx.head",
        fake_head,
    )

    assert remote_curated_image_exists(
        public_base_url="https://example.com",
        curated_media_path="/media/dinosaurs/",
        filename="Tyrannosaurus.webp",
    )
    assert remote_curated_image_exists(
        public_base_url="https://example.com",
        curated_media_path="/media/tools/",
        filename="Orbit Survey.png",
    )
    assert not remote_curated_image_exists(
        public_base_url="https://example.com",
        curated_media_path="/media/dinosaurs/",
        filename="Missing.webp",
    )


def test_needs_curated_image_resync_when_remote_missing(monkeypatch, tmp_path: Path):
    image = tmp_path / "Orbit Survey.png"
    image.write_bytes(b"tool-bytes")
    version = file_content_version(image)

    monkeypatch.setattr(
        "app.services.curated_image_service.common.head_remote_curated_image",
        lambda **kwargs: (False, None),
    )

    assert needs_curated_image_resync(
        overwrite=False,
        local_path=image,
        main_image_url=f"https://example.com/media/tools/Orbit Survey.png?v={version}",
        public_base_url="https://example.com",
        filename="Orbit Survey.png",
        curated_media_path="/media/tools/",
    )


def test_needs_curated_image_resync_skips_when_remote_is_newer_or_equal(
    monkeypatch, tmp_path: Path
):
    image = tmp_path / "Orbit Survey.png"
    image.write_bytes(b"tool-bytes")
    local_mtime = image.stat().st_mtime
    version = file_content_version(image)

    monkeypatch.setattr(
        "app.services.curated_image_service.common.head_remote_curated_image",
        lambda **kwargs: (True, local_mtime + 10),
    )

    assert not needs_curated_image_resync(
        overwrite=False,
        local_path=image,
        main_image_url=f"https://example.com/media/tools/Orbit Survey.png?v={version}",
        public_base_url="https://example.com",
        filename="Orbit Survey.png",
        curated_media_path="/media/tools/",
    )


def test_needs_curated_image_resync_when_local_is_newer(monkeypatch, tmp_path: Path):
    image = tmp_path / "Orbit Survey.png"
    image.write_bytes(b"tool-bytes")
    local_mtime = image.stat().st_mtime

    monkeypatch.setattr(
        "app.services.curated_image_service.common.head_remote_curated_image",
        lambda **kwargs: (True, local_mtime - 60),
    )

    assert needs_curated_image_resync(
        overwrite=False,
        local_path=image,
        main_image_url="https://example.com/media/tools/Orbit Survey.png?v=old",
        public_base_url="https://example.com",
        filename="Orbit Survey.png",
        curated_media_path="/media/tools/",
    )


def test_needs_curated_image_resync_skips_when_remote_has_no_mtime(
    monkeypatch, tmp_path: Path
):
    image = tmp_path / "Orbit Survey.png"
    image.write_bytes(b"changed-bytes")

    monkeypatch.setattr(
        "app.services.curated_image_service.common.head_remote_curated_image",
        lambda **kwargs: (True, None),
    )

    assert not needs_curated_image_resync(
        overwrite=False,
        local_path=image,
        main_image_url="https://example.com/media/tools/Orbit Survey.png?v=old",
        public_base_url="https://example.com",
        filename="Orbit Survey.png",
        curated_media_path="/media/tools/",
    )


def test_resolve_curated_storage_dir_uses_explicit_server_path():
    path = resolve_curated_storage_dir(
        configured_dir="/data/images/dinosaurs",
        default_relative="../images/dinosaurs",
        data_root="",
        subdir_name="images/dinosaurs",
    )
    assert path == Path("/data/images/dinosaurs")


def test_resolve_curated_storage_dir_uses_data_root_for_defaults(monkeypatch):
    monkeypatch.setattr(config_module.settings, "curated_images_data_root", "/data")
    monkeypatch.setattr(config_module.settings, "fossil_images_dir", "../images/fossils")

    assert config_module.settings.resolved_fossil_images_dir == Path("/data/images/fossils")


def test_resolve_curated_storage_dir_falls_back_to_legacy_volume(tmp_path: Path):
    root = tmp_path / "data"
    legacy = root / "tool-images"
    legacy.mkdir(parents=True)
    (legacy / "Orbit Survey.png").write_bytes(b"tool")

    path = resolve_curated_storage_dir(
        configured_dir="../images/tools",
        default_relative="../images/tools",
        data_root=str(root),
        subdir_name="images/tools",
    )
    assert path == legacy.resolve()


def test_resolve_curated_storage_dir_prefers_new_layout_when_populated(tmp_path: Path):
    root = tmp_path / "data"
    primary = root / "images" / "tools"
    legacy = root / "tool-images"
    primary.mkdir(parents=True)
    legacy.mkdir(parents=True)
    (primary / "Orbit Survey.png").write_bytes(b"new")
    (legacy / "Orbit Survey.png").write_bytes(b"old")

    path = resolve_curated_storage_dir(
        configured_dir="../images/tools",
        default_relative="../images/tools",
        data_root=str(root),
        subdir_name="images/tools",
    )
    assert path == primary.resolve()


def test_resolve_curated_storage_dir_explicit_overrides_data_root():
    path = resolve_curated_storage_dir(
        configured_dir="/data/images/dinosaurs",
        default_relative="../images/dinosaurs",
        data_root="/data",
        subdir_name="images/dinosaurs",
    )
    assert path == Path("/data/images/dinosaurs")


def test_resolve_local_source_dir_ignores_server_storage_path(monkeypatch, tmp_path: Path):
    repo_images = tmp_path / "images" / "fossils"
    repo_images.mkdir(parents=True)
    (repo_images / "139292.png").write_bytes(b"x")

    monkeypatch.setenv("FOSSIL_IMAGES_DIR", "/data/images/fossils")
    monkeypatch.setenv("FOSSIL_IMAGES_SOURCE_DIR", str(repo_images))

    assert resolve_fossil_source() == repo_images.resolve()
    assert resolve_local_source_dir_for_sync(
        source_env_var="FOSSIL_IMAGES_SOURCE_DIR",
        default_repo_subdir="images/fossils",
    ) == repo_images.resolve()


def test_resolve_dino_source_ignores_server_storage_path(monkeypatch, tmp_path: Path):
    repo_images = tmp_path / "images" / "dinosaurs"
    repo_images.mkdir(parents=True)
    (repo_images / "Tyrannosaurus.webp").write_bytes(b"x")

    monkeypatch.setenv("DINOSAUR_IMAGES_DIR", "/data/images/dinosaurs")
    monkeypatch.setenv("DINOSAUR_IMAGES_SOURCE_DIR", str(repo_images))

    assert resolve_dino_source() == repo_images.resolve()


def test_resolve_site_type_source_uses_repo_subdir(monkeypatch, tmp_path: Path):
    repo_images = tmp_path / "images" / "site-types"
    repo_images.mkdir(parents=True)
    (repo_images / "1.png").write_bytes(b"x")

    monkeypatch.setenv("SITE_TYPE_IMAGES_SOURCE_DIR", str(repo_images))

    assert resolve_site_type_source() == repo_images.resolve()


def test_resolve_tool_source_uses_repo_subdir(monkeypatch, tmp_path: Path):
    repo_images = tmp_path / "images" / "tools"
    repo_images.mkdir(parents=True)
    (repo_images / "Orbit Survey.png").write_bytes(b"x")

    monkeypatch.setenv("TOOL_IMAGES_SOURCE_DIR", str(repo_images))

    assert resolve_tool_source() == repo_images.resolve()
