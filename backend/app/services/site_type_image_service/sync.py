"""Curated site-type card image helpers and sync."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

from app.models.site_type import SiteType
from app.services.curated_image_service.common import (
    ALLOWED_IMAGE_EXTENSIONS,
    DEFAULT_PRODUCTION_BASE_URL,
    file_content_version,
    is_allowed_image_filename,
    needs_curated_image_resync,
    normalize_public_base_url,
    remote_curated_image_exists,
    resolve_local_source_dir_for_sync as _resolve_local_source_dir,
    resolve_public_base_url_for_sync,
    scan_local_image_files,
    upload_curated_image_to_railway,
    version_from_curated_url,
)

CURATED_MEDIA_PATH = "/media/site-types/"


@dataclass(frozen=True)
class SiteTypeImageFileMatch:
    path: Path
    filename: str
    site_type_id: int
    period: str
    rock_type: str


def site_type_image_key(*, period: str, rock_type: str) -> str:
    """Stable filename stem: ``{period}_{rock_type}`` (lowercase snake_case)."""
    period_key = period.strip().lower()
    rock_key = rock_type.strip().lower()
    rock_key = re.sub(r"[\s\-/]+", "_", rock_key)
    rock_key = re.sub(r"[^a-z0-9_]", "", rock_key)
    rock_key = re.sub(r"_+", "_", rock_key).strip("_")
    return f"{period_key}_{rock_key}"


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


def _sorted_site_types(site_types: list[SiteType]) -> list[SiteType]:
    return sorted(site_types, key=lambda row: (row.period, row.rock_type))


def _legacy_order_index(site_types: list[SiteType]) -> dict[int, SiteType]:
    """Map legacy numeric filename stems to site types by sorted (period, rock_type) order."""
    return {
        index: row
        for index, row in enumerate(_sorted_site_types(site_types), start=1)
    }


def _resolve_site_type_for_stem(
    stem: str,
    *,
    by_id: dict[int, SiteType],
    by_key: dict[str, SiteType],
    by_legacy_order: dict[int, SiteType],
) -> SiteType | None:
    lowered = stem.lower()
    if lowered in by_key:
        return by_key[lowered]
    try:
        numeric = int(stem)
    except ValueError:
        return None
    if numeric in by_id:
        return by_id[numeric]
    return by_legacy_order.get(numeric)


def match_image_files(
    files: list[Path],
    site_types: list[SiteType],
) -> tuple[list[SiteTypeImageFileMatch], list[Path]]:
    """Match local files by ``period_rocktype`` stem, with legacy numeric id fallback."""
    by_id = {row.id: row for row in site_types if row.id is not None}
    by_key = {
        site_type_image_key(period=row.period, rock_type=row.rock_type): row
        for row in site_types
        if row.id is not None
    }
    by_legacy_order = _legacy_order_index(site_types)

    matched: list[SiteTypeImageFileMatch] = []
    unmatched: list[Path] = []
    seen_ids: set[int] = set()

    for path in files:
        site_type = _resolve_site_type_for_stem(
            path.stem,
            by_id=by_id,
            by_key=by_key,
            by_legacy_order=by_legacy_order,
        )
        if site_type is None or site_type.id is None:
            unmatched.append(path)
            continue
        if site_type.id in seen_ids:
            unmatched.append(path)
            continue

        key = site_type_image_key(period=site_type.period, rock_type=site_type.rock_type)
        matched.append(
            SiteTypeImageFileMatch(
                path=path,
                filename=f"{key}{path.suffix.lower()}",
                site_type_id=site_type.id,
                period=site_type.period,
                rock_type=site_type.rock_type,
            )
        )
        seen_ids.add(site_type.id)

    return matched, unmatched


def remote_image_exists(*, public_base_url: str, filename: str) -> bool:
    return remote_curated_image_exists(
        public_base_url=public_base_url,
        curated_media_path=CURATED_MEDIA_PATH,
        filename=filename,
    )


def needs_image_resync(
    *,
    overwrite: bool,
    local_path: Path,
    main_image_url: str | None,
    public_base_url: str,
    filename: str,
) -> bool:
    return needs_curated_image_resync(
        overwrite=overwrite,
        local_path=local_path,
        main_image_url=main_image_url,
        public_base_url=public_base_url,
        filename=filename,
        curated_media_path=CURATED_MEDIA_PATH,
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
        default_repo_subdir="images/site-types",
    )


__all__ = [
    "ALLOWED_IMAGE_EXTENSIONS",
    "CURATED_MEDIA_PATH",
    "DEFAULT_PRODUCTION_BASE_URL",
    "SiteTypeImageFileMatch",
    "build_curated_image_url",
    "file_content_version",
    "is_allowed_image_filename",
    "is_curated_image_url",
    "match_image_files",
    "needs_image_resync",
    "normalize_public_base_url",
    "remote_image_exists",
    "resolve_local_source_dir_for_sync",
    "resolve_public_base_url_for_sync",
    "scan_local_image_files",
    "site_type_image_key",
    "upload_file_to_railway",
    "version_from_curated_url",
]
