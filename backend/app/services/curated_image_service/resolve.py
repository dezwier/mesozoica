"""Resolve versioned curated image URLs for site-type and tool cards."""

from __future__ import annotations

from datetime import datetime
from pathlib import Path

from app.core.config import settings
from app.services.curated_image_service.common import file_content_version
from app.services.curated_image_service.versions import (
    build_versioned_media_url,
    resolve_versioned_image_path,
)
from app.services.site_type_image_service.sync import (
    CURATED_MEDIA_PATH as SITE_TYPE_MEDIA_PATH,
    site_type_image_key,
)
from app.services.tool_image_service.sync import CURATED_MEDIA_PATH as TOOL_MEDIA_PATH


def _public_base_url() -> str:
    base = settings.public_base_url.strip()
    if base:
        return base.rstrip("/")
    return ""


def resolve_site_type_card_image_url(
    *,
    period: str,
    rock_type: str,
    as_of: datetime | None = None,
    force_v1: bool = False,
    fallback_url: str | None = None,
) -> str | None:
    """Pick the versioned site-type image URL for a card."""
    root = settings.resolved_site_type_images_dir
    stem = site_type_image_key(period=period, rock_type=rock_type)
    resolved = resolve_versioned_image_path(
        root,
        stem,
        as_of=as_of,
        force_v1=force_v1,
        case_insensitive=False,
    )
    if resolved is None:
        return fallback_url
    version, path = resolved
    base = _public_base_url()
    if not base:
        return fallback_url
    relative = f"{version.name}/{path.name}"
    return build_versioned_media_url(
        base,
        SITE_TYPE_MEDIA_PATH,
        relative,
        content_version=file_content_version(path),
    )


def resolve_tool_card_image_url(
    *,
    tool_name: str,
    as_of: datetime | None = None,
    force_v1: bool = False,
    fallback_url: str | None = None,
) -> str | None:
    """Pick the versioned tool image URL for a card."""
    root = settings.resolved_tool_images_dir
    resolved = resolve_versioned_image_path(
        root,
        tool_name,
        as_of=as_of,
        force_v1=force_v1,
        case_insensitive=True,
    )
    if resolved is None:
        return fallback_url
    version, path = resolved
    base = _public_base_url()
    if not base:
        return fallback_url
    relative = f"{version.name}/{path.name}"
    return build_versioned_media_url(
        base,
        TOOL_MEDIA_PATH,
        relative,
        content_version=file_content_version(path),
    )


def any_versioned_stem_exists(root: Path, stem: str, *, case_insensitive: bool = False) -> bool:
    from app.services.curated_image_service.versions import load_image_versions, find_image_in_version

    for version in load_image_versions(root):
        if find_image_in_version(version.path, stem, case_insensitive=case_insensitive):
            return True
    return False
