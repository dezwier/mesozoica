"""Curated tool card image helpers and sync."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from app.services.curated_image_service.common import (
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
from app.services.curated_image_service.versions import (
    VersionedImageFile,
    build_versioned_media_url,
    latest_version_with_stem,
    migrate_flat_images_to_v1,
    scan_versioned_image_files,
)
from app.services.image_generation_service.prompting import tool_image_prompt_template

CURATED_MEDIA_PATH = "/media/tools/"


@dataclass(frozen=True)
class ImageFileMatch:
    path: Path
    filename: str  # canonical basename
    relative_path: str  # e.g. v1/Orbit Survey.png
    version: str
    tool_name: str


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
    tool_names: set[str],
) -> tuple[list[ImageFileMatch], list[Path]]:
    """Return (matched, unmatched); file stem matches tool.name case-insensitively."""
    names_by_lower = {name.lower(): name for name in tool_names}
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
                tool_name=canonical_name,
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
        admin_upload_path="/api/v1/admin/tool-images",
        sync_header_name="X-Tool-Image-Sync-Key",
        sync_secret_env_var="TOOL_IMAGE_SYNC_SECRET",
        dry_run=dry_run,
    )


def resolve_local_source_dir_for_sync() -> Path:
    return _resolve_local_source_dir(
        source_env_var="TOOL_IMAGES_SOURCE_DIR",
        default_repo_subdir="images/tools",
    )


def prepare_local_source_for_sync() -> Path:
    root = resolve_local_source_dir_for_sync()
    migrate_flat_images_to_v1(root, default_prompt=tool_image_prompt_template())
    return root


def collect_versioned_matches(
    tool_names: set[str],
) -> tuple[list[ImageFileMatch], list[Path]]:
    root = prepare_local_source_for_sync()
    versioned = scan_versioned_image_files(root)
    if versioned:
        return match_image_files(versioned, tool_names)
    return match_image_files(scan_local_image_files(root), tool_names)


def latest_relative_path_for_tool(
    *,
    tool_name: str,
    root: Path | None = None,
) -> tuple[str, Path] | None:
    source = root or resolve_local_source_dir_for_sync()
    resolved = latest_version_with_stem(source, tool_name, case_insensitive=True)
    if resolved is None:
        return None
    version, path = resolved
    return f"{version.name}/{tool_name}{path.suffix.lower()}", path


__all__ = [
    "ALLOWED_IMAGE_EXTENSIONS",
    "CURATED_MEDIA_PATH",
    "DEFAULT_PRODUCTION_BASE_URL",
    "ImageFileMatch",
    "build_curated_image_url",
    "collect_versioned_matches",
    "file_content_version",
    "is_allowed_image_filename",
    "is_curated_image_url",
    "latest_relative_path_for_tool",
    "match_image_files",
    "normalize_public_base_url",
    "prepare_local_source_for_sync",
    "remote_image_exists",
    "resolve_local_source_dir_for_sync",
    "resolve_public_base_url_for_sync",
    "scan_local_image_files",
    "upload_file_to_railway",
]
