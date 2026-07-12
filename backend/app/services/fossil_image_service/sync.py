"""Curated fossil card image helpers and sync."""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from pathlib import Path

import httpx

from app.core.config import settings

ALLOWED_IMAGE_EXTENSIONS = frozenset({".webp", ".jpg", ".jpeg", ".png"})
CURATED_MEDIA_PATH = "/media/fossils/"
DEFAULT_PRODUCTION_BASE_URL = "https://mesozoica-production.up.railway.app"


@dataclass(frozen=True)
class FossilImageFileMatch:
    path: Path
    filename: str
    fossil_id: int


def is_allowed_image_filename(filename: str) -> bool:
    return Path(filename).suffix.lower() in ALLOWED_IMAGE_EXTENSIONS


def build_curated_image_url(public_base_url: str, filename: str) -> str:
    base = public_base_url.rstrip("/")
    return f"{base}{CURATED_MEDIA_PATH}{filename}"


def is_curated_image_url(url: str | None) -> bool:
    if not url:
        return False
    return CURATED_MEDIA_PATH in url


def scan_local_image_files(source_dir: Path) -> list[Path]:
    if not source_dir.is_dir():
        return []
    return [
        path
        for path in sorted(source_dir.iterdir())
        if path.is_file() and is_allowed_image_filename(path.name)
    ]


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
    """Upload a local image to the deployed API (persists on Railway volume)."""
    secret = sync_secret.strip()
    if not dry_run and not secret:
        raise RuntimeError(
            "FOSSIL_IMAGE_SYNC_SECRET must be set to upload images to Railway."
        )

    url = (
        f"{public_base_url.rstrip('/')}/api/v1/admin/fossil-images/{remote_filename}"
    )
    if dry_run:
        return

    response = httpx.put(
        url,
        content=local_path.read_bytes(),
        headers={
            "Content-Type": "application/octet-stream",
            "X-Fossil-Image-Sync-Key": secret,
        },
        timeout=120.0,
    )
    if response.status_code >= 400:
        detail = response.text.strip() or response.reason_phrase
        raise RuntimeError(
            f"Failed to upload {local_path.name} to {url}: HTTP {response.status_code} {detail}"
        )


def resolve_local_source_dir_for_sync() -> Path:
    """Repo `fossil-images/` folder — local source files for sync."""
    override = os.getenv("FOSSIL_IMAGES_SOURCE_DIR", "").strip()
    backend_dir = Path(__file__).resolve().parents[3]
    if override:
        path = Path(override)
        if path.is_absolute():
            return path
        return (backend_dir / path).resolve()
    return (backend_dir.parent / "fossil-images").resolve()


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


def _is_localhost_url(value: str) -> bool:
    lowered = value.lower()
    return "127.0.0.1" in lowered or "localhost" in lowered


def normalize_public_base_url(value: str) -> str:
    trimmed = value.strip()
    if not trimmed:
        raise ValueError("PUBLIC_BASE_URL must not be empty.")
    if not re.match(r"^https?://", trimmed, re.IGNORECASE):
        raise ValueError("PUBLIC_BASE_URL must start with http:// or https://")
    return trimmed.rstrip("/")
