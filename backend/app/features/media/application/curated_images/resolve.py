"""Resolve versioned curated image URLs for site-type, tool, dinosaur, and fossil cards."""

from __future__ import annotations

from pathlib import Path

from app.core.config import settings
from app.features.media.application.curated_images.common import file_content_version
from app.features.media.application.curated_images.versions import (
    ORIGINAL_VERSION,
    build_versioned_media_url,
    resolve_versioned_image_path,
)
from app.features.media.application.site_type_images.sync import (
    CURATED_MEDIA_PATH as SITE_TYPE_MEDIA_PATH,
    site_type_image_key,
)
from app.features.media.application.tool_images.sync import CURATED_MEDIA_PATH as TOOL_MEDIA_PATH


def _public_base_url() -> str:
    base = settings.public_base_url.strip()
    if base:
        return base.rstrip("/")
    return ""


def resolve_site_type_card_image_url(
    *,
    period: str,
    rock_type: str,
    version: str | None = None,
    fallback_url: str | None = None,
) -> str | None:
    """Pick the versioned site-type image URL for a card."""
    root = settings.resolved_site_type_images_dir
    stem = site_type_image_key(period=period, rock_type=rock_type)
    resolved = resolve_versioned_image_path(
        root,
        stem,
        version=version or ORIGINAL_VERSION,
        case_insensitive=False,
    )
    if resolved is None:
        return fallback_url
    info, path = resolved
    base = _public_base_url()
    if not base:
        return fallback_url
    relative = f"{info.name}/{path.name}"
    return build_versioned_media_url(
        base,
        SITE_TYPE_MEDIA_PATH,
        relative,
        content_version=file_content_version(path),
    )


def resolve_tool_card_image_url(
    *,
    tool_name: str,
    version: str | None = None,
    fallback_url: str | None = None,
) -> str | None:
    """Pick the versioned tool image URL for a card."""
    root = settings.resolved_tool_images_dir
    resolved = resolve_versioned_image_path(
        root,
        tool_name,
        version=version or ORIGINAL_VERSION,
        case_insensitive=True,
    )
    if resolved is None:
        return fallback_url
    info, path = resolved
    base = _public_base_url()
    if not base:
        return fallback_url
    relative = f"{info.name}/{path.name}"
    return build_versioned_media_url(
        base,
        TOOL_MEDIA_PATH,
        relative,
        content_version=file_content_version(path),
    )


def resolve_dinosaur_card_image_url(
    *,
    dinosaur_name: str,
    version: str | None = None,
    fallback_url: str | None = None,
) -> str | None:
    """Pick the versioned dinosaur image URL for a card."""
    from app.features.media.application.dinosaur_images.sync import CURATED_MEDIA_PATH as DINO_MEDIA_PATH

    root = settings.resolved_dinosaur_images_dir
    resolved = resolve_versioned_image_path(
        root,
        dinosaur_name,
        version=version or ORIGINAL_VERSION,
        case_insensitive=True,
    )
    if resolved is None:
        return fallback_url
    info, path = resolved
    base = _public_base_url()
    if not base:
        return fallback_url
    relative = f"{info.name}/{path.name}"
    return build_versioned_media_url(
        base,
        DINO_MEDIA_PATH,
        relative,
        content_version=file_content_version(path),
    )


def resolve_fossil_card_image_url(
    *,
    fossil_id: int,
    version: str | None = None,
    fallback_url: str | None = None,
) -> str | None:
    """Pick the versioned fossil image URL for a card."""
    from app.features.media.application.fossil_images.sync import CURATED_MEDIA_PATH as FOSSIL_MEDIA_PATH

    root = settings.resolved_fossil_images_dir
    resolved = resolve_versioned_image_path(
        root,
        str(fossil_id),
        version=version or ORIGINAL_VERSION,
        case_insensitive=False,
    )
    if resolved is None:
        return fallback_url
    info, path = resolved
    base = _public_base_url()
    if not base:
        return fallback_url
    relative = f"{info.name}/{path.name}"
    return build_versioned_media_url(
        base,
        FOSSIL_MEDIA_PATH,
        relative,
        content_version=file_content_version(path),
    )


def any_versioned_stem_exists(
    root: Path, stem: str, *, case_insensitive: bool = False
) -> bool:
    from app.features.media.application.curated_images.versions import (
        find_image_in_version,
        load_image_versions,
    )

    for version in load_image_versions(root):
        if find_image_in_version(
            version.path, stem, case_insensitive=case_insensitive
        ):
            return True
    return False
