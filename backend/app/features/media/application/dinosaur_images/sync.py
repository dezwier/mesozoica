"""Curated dinosaur card image helpers and sync."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from app.features.media.application.curated_images.common import (
    ALLOWED_IMAGE_EXTENSIONS,
    DEFAULT_PRODUCTION_BASE_URL,
    file_content_version,
    is_allowed_image_filename,
    normalize_public_base_url,
    remote_curated_image_exists,
    resolve_local_source_dir_for_sync as _resolve_local_source_dir,
    resolve_public_base_url_for_sync,
    scan_local_image_files,
    upload_curated_image_to_railway,
)
from app.features.media.application.curated_images.versions import (
    VersionedImageFile,
    build_versioned_media_url,
    latest_version_with_stem,
    migrate_flat_images_to_v1,
    scan_versioned_image_files,
)
from app.features.media.infrastructure.image_generation.prompting import dinosaur_image_prompt_template

CURATED_MEDIA_PATH = "/media/dinosaurs/"


@dataclass(frozen=True)
class ImageFileMatch:
    path: Path
    filename: str
    relative_path: str
    version: str
    dinosaur_name: str


def build_curated_image_url(
    public_base_url: str,
    filename: str,
    *,
    version: str | None = None,
) -> str:
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


def match_image_files(
    files: list[Path] | list[VersionedImageFile],
    dinosaur_names: set[str],
) -> tuple[list[ImageFileMatch], list[Path]]:
    """Return (matched, unmatched); file stem matches dinosaur.name case-insensitively."""
    names_by_lower = {name.lower(): name for name in dinosaur_names}
    matched: list[ImageFileMatch] = []
    unmatched: list[Path] = []
    seen: set[tuple[str, str]] = set()

    for item in files:
        if isinstance(item, VersionedImageFile):
            path = item.path
            stem = Path(item.filename).stem
            version_name = item.version
        else:
            path = item
            stem = path.stem
            version_name = "flat"

        canonical_name = names_by_lower.get(stem.lower())
        if canonical_name is None:
            unmatched.append(path)
            continue

        filename = f"{canonical_name}{path.suffix.lower()}"
        relative_path = (
            f"{version_name}/{filename}" if version_name and version_name != "flat" else filename
        )
        seen_key = (canonical_name.lower(), version_name)
        if seen_key in seen:
            unmatched.append(path)
            continue

        matched.append(
            ImageFileMatch(
                path=path,
                filename=filename,
                relative_path=relative_path,
                version=version_name,
                dinosaur_name=canonical_name,
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
        default_repo_subdir="images/dinosaurs",
    )


def prepare_local_source_for_sync() -> Path:
    root = resolve_local_source_dir_for_sync()
    migrate_flat_images_to_v1(root, default_prompt=dinosaur_image_prompt_template())
    return root


def collect_versioned_matches(
    dinosaur_names: set[str],
) -> tuple[list[ImageFileMatch], list[Path]]:
    root = prepare_local_source_for_sync()
    versioned = scan_versioned_image_files(root)
    if versioned:
        return match_image_files(versioned, dinosaur_names)
    return match_image_files(scan_local_image_files(root), dinosaur_names)


def latest_relative_path_for_dinosaur(
    *,
    dinosaur_name: str,
    root: Path | None = None,
) -> tuple[str, Path] | None:
    source = root or resolve_local_source_dir_for_sync()
    resolved = latest_version_with_stem(source, dinosaur_name, case_insensitive=True)
    if resolved is None:
        return None
    version, path = resolved
    return f"{version.name}/{dinosaur_name}{path.suffix.lower()}", path


def catalog_relative_path_for_dinosaur(
    *,
    dinosaur_name: str,
    root: Path | None = None,
) -> tuple[str, Path] | None:
    """Relative path for catalog cards — always the Original version when present."""
    from app.features.media.application.curated_images.versions import (
        ORIGINAL_VERSION,
        resolve_versioned_image_path,
    )

    source = root or resolve_local_source_dir_for_sync()
    resolved = resolve_versioned_image_path(
        source,
        dinosaur_name,
        version=ORIGINAL_VERSION,
        case_insensitive=True,
    )
    if resolved is None:
        return None
    version, path = resolved
    return f"{version.name}/{dinosaur_name}{path.suffix.lower()}", path


__all__ = [
    "ALLOWED_IMAGE_EXTENSIONS",
    "CURATED_MEDIA_PATH",
    "DEFAULT_PRODUCTION_BASE_URL",
    "ImageFileMatch",
    "build_curated_image_url",
    "catalog_relative_path_for_dinosaur",
    "collect_versioned_matches",
    "file_content_version",
    "is_allowed_image_filename",
    "is_curated_image_url",
    "latest_relative_path_for_dinosaur",
    "match_image_files",
    "normalize_public_base_url",
    "prepare_local_source_for_sync",
    "remote_image_exists",
    "resolve_local_source_dir_for_sync",
    "resolve_public_base_url_for_sync",
    "scan_local_image_files",
    "upload_file_to_railway",
]
