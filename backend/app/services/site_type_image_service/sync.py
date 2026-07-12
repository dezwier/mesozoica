"""Curated site-type card image helpers and sync."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from app.services.curated_image_service.common import (
    ALLOWED_IMAGE_EXTENSIONS,
    DEFAULT_PRODUCTION_BASE_URL,
    is_allowed_image_filename,
    normalize_public_base_url,
    remote_curated_image_exists,
    resolve_local_source_dir_for_sync as _resolve_local_source_dir,
    resolve_public_base_url_for_sync,
    scan_local_image_files,
    upload_curated_image_to_railway,
)

CURATED_MEDIA_PATH = "/media/site-types/"


@dataclass(frozen=True)
class SiteTypeImageFileMatch:
    path: Path
    filename: str
    site_type_id: int


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
    site_type_ids: set[int],
) -> tuple[list[SiteTypeImageFileMatch], list[Path]]:
    """Return (matched, unmatched); file stem matches site_type.id."""
    matched: list[SiteTypeImageFileMatch] = []
    unmatched: list[Path] = []
    for path in files:
        try:
            site_type_id = int(path.stem)
        except ValueError:
            unmatched.append(path)
            continue
        if site_type_id not in site_type_ids:
            unmatched.append(path)
            continue
        matched.append(
            SiteTypeImageFileMatch(
                path=path,
                filename=f"{site_type_id}{path.suffix.lower()}",
                site_type_id=site_type_id,
            )
        )
    return matched, unmatched


def remote_image_exists(*, public_base_url: str, filename: str) -> bool:
    return remote_curated_image_exists(
        public_base_url=public_base_url,
        curated_media_path=CURATED_MEDIA_PATH,
        filename=filename,
    )


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
        admin_upload_path="/api/v1/admin/site-type-images",
        sync_header_name="X-Site-Type-Image-Sync-Key",
        sync_secret_env_var="SITE_TYPE_IMAGE_SYNC_SECRET",
        dry_run=dry_run,
    )


def resolve_local_source_dir_for_sync() -> Path:
    return _resolve_local_source_dir(
        source_env_var="SITE_TYPE_IMAGES_SOURCE_DIR",
        default_repo_subdir="site-type-images",
    )


__all__ = [
    "ALLOWED_IMAGE_EXTENSIONS",
    "CURATED_MEDIA_PATH",
    "DEFAULT_PRODUCTION_BASE_URL",
    "SiteTypeImageFileMatch",
    "build_curated_image_url",
    "is_allowed_image_filename",
    "is_curated_image_url",
    "match_image_files",
    "normalize_public_base_url",
    "remote_image_exists",
    "resolve_local_source_dir_for_sync",
    "resolve_public_base_url_for_sync",
    "scan_local_image_files",
    "upload_file_to_railway",
]
