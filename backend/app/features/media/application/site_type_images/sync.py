"""Curated site-type card image helpers and sync."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

from app.models.site_type import SiteType
from app.features.media.application.curated_images.common import (
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
from app.features.media.application.curated_images.versions import (
    VersionedImageFile,
    build_versioned_media_url,
    latest_version_with_stem,
    migrate_flat_images_to_v1,
    scan_versioned_image_files,
)
from app.features.media.infrastructure.image_generation.prompting import site_type_image_prompt_template

CURATED_MEDIA_PATH = "/media/site-types/"


@dataclass(frozen=True)
class SiteTypeImageFileMatch:
    path: Path
    filename: str  # basename used for DB key matching
    relative_path: str  # e.g. v1/cretaceous_sandstone.png
    version: str
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
    """Build a public URL. ``filename`` may be versioned (``v1/foo.png``)."""
    return build_versioned_media_url(
        public_base_url,
        CURATED_MEDIA_PATH,
        filename,
        content_version=version,
    )


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
    files: list[Path] | list[VersionedImageFile],
    site_types: list[SiteType],
) -> tuple[list[SiteTypeImageFileMatch], list[Path]]:
    """Match local files by ``period_rocktype`` stem, with legacy numeric id fallback.

    Accepts either flat ``Path`` lists (tests/legacy) or ``VersionedImageFile`` lists.
    """
    by_id = {row.id: row for row in site_types if row.id is not None}
    by_key = {
        site_type_image_key(period=row.period, rock_type=row.rock_type): row
        for row in site_types
        if row.id is not None
    }
    by_legacy_order = _legacy_order_index(site_types)

    matched: list[SiteTypeImageFileMatch] = []
    unmatched: list[Path] = []
    seen: set[tuple[int, str]] = set()

    for item in files:
        if isinstance(item, VersionedImageFile):
            path = item.path
            stem = Path(item.filename).stem
            version_name = item.version
        else:
            path = item
            stem = path.stem
            version_name = ""

        site_type = _resolve_site_type_for_stem(
            stem,
            by_id=by_id,
            by_key=by_key,
            by_legacy_order=by_legacy_order,
        )
        if site_type is None or site_type.id is None:
            unmatched.append(path)
            continue

        key = site_type_image_key(period=site_type.period, rock_type=site_type.rock_type)
        filename = f"{key}{path.suffix.lower()}"
        if isinstance(item, VersionedImageFile):
            relative_path = f"{item.version}/{filename}"
            version_name = item.version
        else:
            relative_path = filename

        seen_key = (site_type.id, version_name or "flat")
        if seen_key in seen:
            unmatched.append(path)
            continue

        matched.append(
            SiteTypeImageFileMatch(
                path=path,
                filename=filename,
                relative_path=relative_path,
                version=version_name or "flat",
                site_type_id=site_type.id,
                period=site_type.period,
                rock_type=site_type.rock_type,
            )
        )
        seen.add(seen_key)

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


def prepare_local_source_for_sync() -> Path:
    """Migrate flat files if needed and return the site-types image root."""
    root = resolve_local_source_dir_for_sync()
    migrate_flat_images_to_v1(root, default_prompt=site_type_image_prompt_template())
    return root


def collect_versioned_matches(
    site_types: list[SiteType],
) -> tuple[list[SiteTypeImageFileMatch], list[Path]]:
    root = prepare_local_source_for_sync()
    versioned = scan_versioned_image_files(root)
    if versioned:
        return match_image_files(versioned, site_types)
    # Legacy flat fallback for tests that still write flat files.
    return match_image_files(scan_local_image_files(root), site_types)


def latest_relative_path_for_site_type(
    *,
    period: str,
    rock_type: str,
    root: Path | None = None,
) -> tuple[str, Path] | None:
    source = root or resolve_local_source_dir_for_sync()
    stem = site_type_image_key(period=period, rock_type=rock_type)
    resolved = latest_version_with_stem(source, stem, case_insensitive=False)
    if resolved is None:
        return None
    version, path = resolved
    key = site_type_image_key(period=period, rock_type=rock_type)
    return f"{version.name}/{key}{path.suffix.lower()}", path


__all__ = [
    "ALLOWED_IMAGE_EXTENSIONS",
    "CURATED_MEDIA_PATH",
    "DEFAULT_PRODUCTION_BASE_URL",
    "SiteTypeImageFileMatch",
    "build_curated_image_url",
    "collect_versioned_matches",
    "file_content_version",
    "is_allowed_image_filename",
    "is_curated_image_url",
    "latest_relative_path_for_site_type",
    "match_image_files",
    "needs_image_resync",
    "normalize_public_base_url",
    "prepare_local_source_for_sync",
    "remote_image_exists",
    "resolve_local_source_dir_for_sync",
    "resolve_public_base_url_for_sync",
    "scan_local_image_files",
    "site_type_image_key",
    "upload_file_to_railway",
    "version_from_curated_url",
]
