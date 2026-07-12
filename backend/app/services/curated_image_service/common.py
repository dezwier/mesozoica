"""Shared path, scan, and upload helpers for curated card images."""

from __future__ import annotations

import os
import re
from pathlib import Path

import httpx

from app.core.config import settings

ALLOWED_IMAGE_EXTENSIONS = frozenset({".webp", ".jpg", ".jpeg", ".png"})
DEFAULT_PRODUCTION_BASE_URL = "https://mesozoica-production.up.railway.app"
_BACKEND_DIR = Path(__file__).resolve().parents[3]


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


def resolve_local_source_dir_for_sync(
    *,
    source_env_var: str,
    default_repo_subdir: str,
) -> Path:
    """Repo image folder used as the local sync source.

    Intentionally ignores server-side storage env vars (e.g. DINOSAUR_IMAGES_DIR
    on Railway at /data/dinosaur-images). Override with *_SOURCE_DIR when needed.
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
        return (Path(root) / subdir_name).resolve()

    path = Path(configured or default_relative)
    if path.is_absolute():
        return path
    return (_BACKEND_DIR / path).resolve()


def remote_curated_image_exists(
    *,
    public_base_url: str,
    curated_media_path: str,
    filename: str,
) -> bool:
    """Return True when the image is already served from Railway."""
    url = f"{public_base_url.rstrip('/')}{curated_media_path}{filename}"
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

    url = f"{public_base_url.rstrip('/')}{admin_upload_path}/{remote_filename}"
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
