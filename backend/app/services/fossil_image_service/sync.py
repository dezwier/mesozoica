"""Curated fossil card image helpers and sync."""

from __future__ import annotations

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

CURATED_MEDIA_PATH = "/media/fossils/"


@dataclass(frozen=True)
class FossilImageFileMatch:
    path: Path
    filename: str
    fossil_id: int


def build_curated_image_url(public_base_url: str, filename: str) -> str:
    base = public_base_url.rstrip("/")
    return f"{base}{CURATED_MEDIA_PATH}{filename}"


def is_curated_image_url(url: str | None) -> bool:
    if not url:
        return False
    return CURATED_MEDIA_PATH in url


def match_image_files(
    files: list[Path],
    fossil_ids: set[int],
) -> tuple[list[FossilImageFileMatch], list[Path]]:
    """Return (matched, unmatched); file stem matches fossil.id."""
    matched: list[FossilImageFileMatch] = []
    unmatched: list[Path] = []
    for path in files:
        try:
            fossil_id = int(path.stem)
        except ValueError:
            unmatched.append(path)
            continue
        if fossil_id not in fossil_ids:
            unmatched.append(path)
            continue
        matched.append(
            FossilImageFileMatch(
                path=path,
                filename=f"{fossil_id}{path.suffix.lower()}",
                fossil_id=fossil_id,
            )
        )
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
        admin_upload_path="/api/v1/admin/fossil-images",
        sync_header_name="X-Fossil-Image-Sync-Key",
        sync_secret_env_var="FOSSIL_IMAGE_SYNC_SECRET",
        dry_run=dry_run,
    )


def resolve_local_source_dir_for_sync() -> Path:
    return _resolve_local_source_dir(
        source_env_var="FOSSIL_IMAGES_SOURCE_DIR",
        default_repo_subdir="fossil-images",
    )


__all__ = [
    "ALLOWED_IMAGE_EXTENSIONS",
    "CURATED_MEDIA_PATH",
    "DEFAULT_PRODUCTION_BASE_URL",
    "FossilImageFileMatch",
    "build_curated_image_url",
    "is_allowed_image_filename",
    "is_curated_image_url",
    "match_image_files",
    "normalize_public_base_url",
    "resolve_local_source_dir_for_sync",
    "resolve_public_base_url_for_sync",
    "scan_local_image_files",
    "upload_file_to_railway",
]
