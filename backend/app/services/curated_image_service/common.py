"""Shared path, scan, and upload helpers for curated card images."""

from __future__ import annotations

import hashlib
import os
import re
from pathlib import Path
from urllib.parse import quote

import httpx

from app.core.config import settings

ALLOWED_IMAGE_EXTENSIONS = frozenset({".webp", ".jpg", ".jpeg", ".png"})
DEFAULT_PRODUCTION_BASE_URL = "https://mesozoica-production.up.railway.app"
_BACKEND_DIR = Path(__file__).resolve().parents[3]

# Pre-images/ volume layouts kept for Railway volumes that were never migrated.
_LEGACY_DATA_SUBDIRS = {
    "images/dinosaurs": "dinosaur-images",
    "images/fossils": "fossil-images",
    "images/site-types": "site-type-images",
    "images/tools": "tool-images",
    "images/users": "user-images",
}


def is_allowed_image_filename(filename: str) -> bool:
    return Path(filename).suffix.lower() in ALLOWED_IMAGE_EXTENSIONS


def scan_local_image_files(source_dir: Path) -> list[Path]:
    if not source_dir.is_dir():
        return []
    return [
        path
        for path in sorted(source_dir.iterdir())
        if path.is_file() and is_allowed_image_filename(path.name)
    ]


def _dir_has_image_files(path: Path) -> bool:
    """True when path has flat images or images under version folders (vN/)."""
    from app.services.curated_image_service.versions import dir_has_versioned_or_flat_images

    return dir_has_versioned_or_flat_images(path)


def resolve_local_source_dir_for_sync(
    *,
    source_env_var: str,
    default_repo_subdir: str,
) -> Path:
    """Repo image folder used as the local sync source.

    Intentionally ignores server-side storage env vars (e.g. DINOSAUR_IMAGES_DIR
    on Railway at /data/images/dinosaurs). Override with *_SOURCE_DIR when needed.
    """
    override = os.getenv(source_env_var, "").strip()
    if override:
        path = Path(override)
        if path.is_absolute():
            return path
        return (_BACKEND_DIR / path).resolve()
    return (_BACKEND_DIR.parent / default_repo_subdir).resolve()


def resolve_curated_storage_dir(
    *,
    configured_dir: str,
    default_relative: str,
    data_root: str,
    subdir_name: str,
) -> Path:
    """Resolve server-side storage directory for served/uploaded images."""
    configured = configured_dir.strip()
    root = data_root.strip()

    if configured and configured != default_relative:
        path = Path(configured)
        if path.is_absolute():
            return path
        return (_BACKEND_DIR / path).resolve()

    if root:
        primary = (Path(root) / subdir_name).resolve()
        legacy_name = _LEGACY_DATA_SUBDIRS.get(subdir_name)
        if legacy_name:
            legacy = (Path(root) / legacy_name).resolve()
            # Prefer the new layout when populated; otherwise keep serving the
            # pre-migration volume folder (tools/site-types still live there).
            if _dir_has_image_files(primary):
                return primary
            if _dir_has_image_files(legacy):
                return legacy
        return primary

    path = Path(configured or default_relative)
    if path.is_absolute():
        return path
    return (_BACKEND_DIR / path).resolve()


def file_content_version(local_path: Path) -> str:
    """Short content hash for cache-busting curated image URLs after re-sync."""
    digest = hashlib.md5(local_path.read_bytes()).hexdigest()
    return digest[:12]


def version_from_curated_url(url: str | None) -> str | None:
    if not url or "?v=" not in url:
        return None
    return url.rsplit("?v=", 1)[-1].split("&", 1)[0] or None


def needs_curated_image_resync(
    *,
    overwrite: bool,
    local_path: Path,
    main_image_url: str | None,
    public_base_url: str,
    filename: str,
    curated_media_path: str,
) -> bool:
    """Return True when the local file should be uploaded and main_image_url refreshed."""
    if overwrite:
        return True

    if not remote_curated_image_exists(
        public_base_url=public_base_url,
        curated_media_path=curated_media_path,
        filename=filename,
    ):
        return True

    local_version = file_content_version(local_path)
    stored_version = version_from_curated_url(main_image_url)
    # Content unchanged and already served — skip.
    if stored_version == local_version:
        return False

    # Remote file exists but local content changed or the DB URL is stale.
    return True


def remote_curated_image_exists(
    *,
    public_base_url: str,
    curated_media_path: str,
    filename: str,
) -> bool:
    """Return True when the image is already served from Railway."""
    # Encode path segments so names with spaces (tool cards) HEAD correctly.
    # Keep '/' so versioned paths like v1/Orbit%20Survey.png resolve.
    media_path = curated_media_path if curated_media_path.endswith("/") else f"{curated_media_path}/"
    url = f"{public_base_url.rstrip('/')}{media_path}{quote(filename, safe='/')}"
    try:
        response = httpx.head(url, timeout=30.0, follow_redirects=True)
    except httpx.HTTPError:
        return False
    return response.status_code == 200


def upload_curated_image_to_railway(
    *,
    local_path: Path,
    remote_filename: str,
    public_base_url: str,
    sync_secret: str,
    admin_upload_path: str,
    sync_header_name: str,
    sync_secret_env_var: str,
    dry_run: bool = False,
) -> None:
    """Upload a local image to the deployed API (persists on Railway volume)."""
    secret = sync_secret.strip()
    if not dry_run and not secret:
        raise RuntimeError(f"{sync_secret_env_var} must be set to upload images to Railway.")

    upload_root = admin_upload_path.rstrip("/")
    url = (
        f"{public_base_url.rstrip('/')}/{upload_root.lstrip('/')}/"
        f"{quote(remote_filename, safe='/')}"
    )
    if dry_run:
        return

    response = httpx.put(
        url,
        content=local_path.read_bytes(),
        headers={
            "Content-Type": "application/octet-stream",
            sync_header_name: secret,
        },
        timeout=120.0,
    )
    if response.status_code >= 400:
        detail = response.text.strip() or response.reason_phrase
        raise RuntimeError(
            f"Failed to upload {local_path.name} to {url}: HTTP {response.status_code} {detail}"
        )


def resolve_public_base_url_for_sync() -> str:
    """Prefer explicit PUBLIC_BASE_URL; fall back to Railway domain or production default."""
    explicit = settings.public_base_url.strip()
    if explicit and not _is_localhost_url(explicit):
        return normalize_public_base_url(explicit)

    railway_domain = os.getenv("RAILWAY_PUBLIC_DOMAIN", "").strip()
    if railway_domain:
        host = railway_domain if railway_domain.startswith("http") else f"https://{railway_domain}"
        return normalize_public_base_url(host)

    return normalize_public_base_url(DEFAULT_PRODUCTION_BASE_URL)


def normalize_public_base_url(value: str) -> str:
    trimmed = value.strip()
    if not trimmed:
        raise ValueError("PUBLIC_BASE_URL must not be empty.")
    if not re.match(r"^https?://", trimmed, re.IGNORECASE):
        raise ValueError("PUBLIC_BASE_URL must start with http:// or https://")
    return trimmed.rstrip("/")


def _is_localhost_url(value: str) -> bool:
    lowered = value.lower()
    return "127.0.0.1" in lowered or "localhost" in lowered
