"""Tests for curated image list/delete/prune used by sync scripts."""

from __future__ import annotations

from pathlib import Path

import pytest

from app.services.curated_image_service.admin_files import (
    resolve_upload_relative_path,
)
from app.services.curated_image_service.sync_prune import (
    delete_local_managed_file,
    list_managed_relative_paths,
    prune_remote_managed_paths,
    safe_managed_relative_path,
    sync_meta_and_prune_remote,
)
from app.services.curated_image_service.versions import META_FILENAME, ORIGINAL_VERSION


def test_list_managed_relative_paths_includes_images_and_meta(tmp_path: Path):
    original = tmp_path / ORIGINAL_VERSION
    original.mkdir()
    (original / "Tyrannosaurus.png").write_bytes(b"dino")
    (original / META_FILENAME).write_text("prompt: x\nrun_date: 2026-01-01T00:00:00Z\n")
    (tmp_path / "loose.png").write_bytes(b"flat")

    assert list_managed_relative_paths(tmp_path) == [
        "Original/Tyrannosaurus.png",
        "Original/meta.yaml",
        "loose.png",
    ]


def test_safe_managed_relative_path_rejects_traversal():
    with pytest.raises(ValueError):
        safe_managed_relative_path("../escape.png")
    with pytest.raises(ValueError):
        safe_managed_relative_path("Original/../escape.png")


def test_delete_local_managed_file_removes_empty_version_dir(tmp_path: Path):
    version = tmp_path / "v1"
    version.mkdir()
    image = version / "old.png"
    image.write_bytes(b"x")

    assert delete_local_managed_file(tmp_path, "v1/old.png") is True
    assert not image.exists()
    assert not version.exists()


def test_resolve_upload_allows_versioned_meta():
    assert resolve_upload_relative_path("Original/meta.yaml") == "Original/meta.yaml"


def test_prune_remote_managed_paths_deletes_orphans(monkeypatch):
    deleted: list[str] = []

    monkeypatch.setattr(
        "app.services.curated_image_service.sync_prune.list_remote_managed_paths",
        lambda **kwargs: [
            "Original/keep.png",
            "Original/meta.yaml",
            "v1/orphan.png",
            "Summer 26/gone.png",
        ],
    )

    def fake_delete(*, remote_filename: str, dry_run: bool = False, **kwargs):
        del kwargs
        assert dry_run is False
        deleted.append(remote_filename)

    monkeypatch.setattr(
        "app.services.curated_image_service.sync_prune.delete_remote_managed_file",
        fake_delete,
    )

    summary = prune_remote_managed_paths(
        keep_relative_paths={"Original/keep.png", "Original/meta.yaml"},
        public_base_url="https://example.com",
        sync_secret="secret",
        admin_upload_path="/api/v1/admin/tool-images",
        sync_header_name="X-Tool-Image-Sync-Key",
        sync_secret_env_var="TOOL_IMAGE_SYNC_SECRET",
    )

    assert summary == {"remote": 4, "kept": 2, "pruned": 2}
    assert deleted == ["Summer 26/gone.png", "v1/orphan.png"]


def test_prune_remote_managed_paths_is_case_insensitive(monkeypatch):
    deleted: list[str] = []

    monkeypatch.setattr(
        "app.services.curated_image_service.sync_prune.list_remote_managed_paths",
        lambda **kwargs: [
            "Original/Tyrannosaurus.png",
            "Original/meta.yaml",
            "v1/orphan.png",
        ],
    )
    monkeypatch.setattr(
        "app.services.curated_image_service.sync_prune.delete_remote_managed_file",
        lambda *, remote_filename, **kwargs: deleted.append(remote_filename),
    )

    summary = prune_remote_managed_paths(
        # Local disk often stores lowercase names; uploads use DB casing.
        keep_relative_paths={"Original/tyrannosaurus.png", "Original/meta.yaml"},
        public_base_url="https://example.com",
        sync_secret="secret",
        admin_upload_path="/api/v1/admin/dinosaur-images",
        sync_header_name="X-Dinosaur-Image-Sync-Key",
        sync_secret_env_var="DINOSAUR_IMAGE_SYNC_SECRET",
    )

    assert summary["pruned"] == 1
    assert deleted == ["v1/orphan.png"]


def test_sync_meta_and_prune_remote_uploads_meta_then_prunes(tmp_path: Path, monkeypatch):
    original = tmp_path / ORIGINAL_VERSION
    original.mkdir()
    (original / "keep.png").write_bytes(b"img")
    (original / META_FILENAME).write_text("prompt: p\nrun_date: 2026-01-01T00:00:00Z\n")

    uploaded: list[str] = []
    pruned_keep: set[str] = set()

    def fake_upload(*, local_path: Path, remote_filename: str, dry_run: bool = False, **kwargs):
        del kwargs, dry_run
        assert local_path.name == META_FILENAME
        uploaded.append(remote_filename)

    monkeypatch.setattr(
        "app.services.curated_image_service.sync_prune.prune_remote_managed_paths",
        lambda *, keep_relative_paths, **kwargs: (
            pruned_keep.update(keep_relative_paths)
            or {"remote": 3, "kept": len(keep_relative_paths), "pruned": 1}
        ),
    )

    summary = sync_meta_and_prune_remote(
        root=tmp_path,
        public_base_url="https://example.com",
        sync_secret="secret",
        admin_upload_path="/api/v1/admin/tool-images",
        sync_header_name="X-Tool-Image-Sync-Key",
        sync_secret_env_var="TOOL_IMAGE_SYNC_SECRET",
        upload_file=fake_upload,
    )

    assert uploaded == ["Original/meta.yaml"]
    assert pruned_keep == {"Original/keep.png", "Original/meta.yaml"}
    assert summary["meta_uploaded"] == 1
    assert summary["pruned"] == 1
