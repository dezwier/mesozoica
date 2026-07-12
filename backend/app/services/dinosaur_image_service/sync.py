"""Curated dinosaur card image helpers and sync."""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from pathlib import Path

from app.services.curated_image_service.common import (
    ALLOWED_IMAGE_EXTENSIONS,
    DEFAULT_PRODUCTION_BASE_URL,
    is_allowed_image_filename,
    normalize_public_base_url,
    resolve_local_source_dir_for_sync as _resolve_local_source_dir,
    resolve_public_base_url_for_sync,
    scan_local_image_files,
    upload_curated_image_to_railway,
)

CURATED_MEDIA_PATH = "/media/dinosaurs/"


@dataclass(frozen=True)
class ImageFileMatch:
    path: Path
    filename: str
    dinosaur_name: str


def file_content_version(local_path: Path) -> str:
    """Short content hash for cache-busting curated image URLs after re-sync."""
    digest = hashlib.md5(local_path.read_bytes()).hexdigest()
    return digest[:12]


def build_curated_image_url(
    public_base_url: str,
    filename: str,
    *,
    version: str | None = None,
) -> str:
    base = public_base_url.rstrip("/")
    url = f"{base}{CURATED_MEDIA_PATH}{filename}"
    if version:
        return f"{url}?v={version}"
    return url


def is_curated_image_url(url: str | None) -> bool:
    if not url:
        return False
    return CURATED_MEDIA_PATH in url


def match_image_files(
    files: list[Path],
    dinosaur_names: set[str],
) -> tuple[list[ImageFileMatch], list[Path]]:
    """Return (matched, unmatched); file stem matches dinosaur.name case-insensitively."""
    names_by_lower = {name.lower(): name for name in dinosaur_names}
    matched: list[ImageFileMatch] = []
    unmatched: list[Path] = []
    for path in files:
        canonical_name = names_by_lower.get(path.stem.lower())
        if canonical_name is not None:
            matched.append(
                ImageFileMatch(
                    path=path,
                    filename=f"{canonical_name}{path.suffix.lower()}",
                    dinosaur_name=canonical_name,
                )
            )
        else:
            unmatched.append(path)
    return matched, unmatched


def upload_file_to_railway(
    *,
    local_path: Path,
    remote_filename: str,
    public_base_url: str,
    sync_secret: str,
    dry_run: bool = False,
) -> None:
    upload_curated_image_to_railway(
        local_path=local_path,
        remote_filename=remote_filename,
        public_base_url=public_base_url,
        sync_secret=sync_secret,
        admin_upload_path="/api/v1/admin/dinosaur-images",
        sync_header_name="X-Dinosaur-Image-Sync-Key",
        sync_secret_env_var="DINOSAUR_IMAGE_SYNC_SECRET",
        dry_run=dry_run,
    )


def resolve_local_source_dir_for_sync() -> Path:
    return _resolve_local_source_dir(
        source_env_var="DINOSAUR_IMAGES_SOURCE_DIR",
        default_repo_subdir="dinosaur-images",
    )


__all__ = [
    "ALLOWED_IMAGE_EXTENSIONS",
    "CURATED_MEDIA_PATH",
    "DEFAULT_PRODUCTION_BASE_URL",
    "ImageFileMatch",
    "build_curated_image_url",
    "file_content_version",
    "is_allowed_image_filename",
    "is_curated_image_url",
    "match_image_files",
    "normalize_public_base_url",
    "resolve_local_source_dir_for_sync",
    "resolve_public_base_url_for_sync",
    "scan_local_image_files",
    "upload_file_to_railway",
]
