"""Versioned curated image folders (v1/, v2/, …) with meta.yaml."""

from __future__ import annotations

import logging
import re
import shutil
from dataclasses import dataclass
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path
from typing import Any

import yaml

from app.services.curated_image_service.common import (
    ALLOWED_IMAGE_EXTENSIONS,
    file_content_version,
    is_allowed_image_filename,
)

logger = logging.getLogger(__name__)

META_FILENAME = "meta.yaml"
BACKFILL_RUN_DATE = datetime(2026, 7, 29, 0, 0, 0, tzinfo=timezone.utc)
_VERSION_DIR_RE = re.compile(r"^v(\d+)$", re.IGNORECASE)


@dataclass(frozen=True)
class ImageVersionInfo:
    """One version folder under a curated image root."""

    name: str  # e.g. "v1"
    number: int
    path: Path
    run_date: datetime | None
    prompt: str | None


@dataclass(frozen=True)
class VersionedImageFile:
    """A single image file inside a version folder."""

    path: Path
    version: str
    version_number: int
    relative_path: str  # e.g. "v1/cretaceous_sandstone.png"
    filename: str  # basename only, e.g. "cretaceous_sandstone.png"


def normalize_version_name(raw: str | int | None) -> str:
    """Accept ``2``, ``v2``, or ``None`` (defaults to ``v1``)."""
    if raw is None or (isinstance(raw, str) and not raw.strip()):
        return "v1"
    text = str(raw).strip().lower()
    if text.startswith("v"):
        text = text[1:]
    if not text.isdigit():
        raise ValueError(f"Invalid image version {raw!r}; expected e.g. 1 or v1")
    return f"v{int(text)}"


def next_version_name(root: Path) -> str:
    """Return ``v1`` when no versions exist, else ``v{max+1}``."""
    versions = load_image_versions(root)
    if not versions:
        return "v1"
    return f"v{max(v.number for v in versions) + 1}"


def resolve_generation_version(
    root: Path,
    version: str | int | None = None,
) -> str:
    """Pick the target version folder for a generate run.

    Explicit ``version`` wins. When omitted, auto-increment past existing
    version folders (``v1`` if none exist).
    """
    if version is None or (isinstance(version, str) and not str(version).strip()):
        return next_version_name(root)
    return normalize_version_name(version)


def parse_version_dir_name(name: str) -> int | None:
    match = _VERSION_DIR_RE.match(name.strip())
    if match is None:
        return None
    return int(match.group(1))


def version_dir(root: Path, version: str | int | None) -> Path:
    return root / normalize_version_name(version)


def _parse_run_date(value: Any) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)
    text = str(value).strip()
    if not text:
        return None
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    parsed = datetime.fromisoformat(text)
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _format_run_date(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat()


def read_meta(version_path: Path) -> dict[str, Any]:
    meta_path = version_path / META_FILENAME
    if not meta_path.is_file():
        return {}
    raw = yaml.safe_load(meta_path.read_text(encoding="utf-8"))
    if raw is None:
        return {}
    if not isinstance(raw, dict):
        raise ValueError(f"Invalid {meta_path}: expected a mapping")
    return raw


def write_meta(version_path: Path, meta: dict[str, Any]) -> None:
    version_path.mkdir(parents=True, exist_ok=True)
    meta_path = version_path / META_FILENAME
    meta_path.write_text(
        yaml.safe_dump(meta, sort_keys=False, allow_unicode=True),
        encoding="utf-8",
    )


def ensure_version_meta(
    version_path: Path,
    *,
    default_prompt: str,
    run_date: datetime | None = None,
    preserve_existing_run_date: bool = True,
) -> dict[str, Any]:
    """Create/repair meta.yaml: fill missing prompt and run_date; never overwrite prompt."""
    version_path.mkdir(parents=True, exist_ok=True)
    meta = dict(read_meta(version_path))
    changed = False

    existing_prompt = meta.get("prompt")
    if not (isinstance(existing_prompt, str) and existing_prompt.strip()):
        meta["prompt"] = default_prompt
        changed = True

    existing_run = _parse_run_date(meta.get("run_date"))
    if existing_run is None or not preserve_existing_run_date:
        meta["run_date"] = _format_run_date(run_date or datetime.now(timezone.utc))
        changed = True
    else:
        # Normalize stored form.
        formatted = _format_run_date(existing_run)
        if meta.get("run_date") != formatted:
            meta["run_date"] = formatted
            changed = True

    if changed or not (version_path / META_FILENAME).is_file():
        write_meta(version_path, meta)
    return meta


def load_image_versions(root: Path) -> list[ImageVersionInfo]:
    """List version folders under ``root``, sorted by version number ascending."""
    if not root.is_dir():
        return []
    versions: list[ImageVersionInfo] = []
    for child in sorted(root.iterdir(), key=lambda p: p.name.lower()):
        number = parse_version_dir_name(child.name)
        if number is None or not child.is_dir():
            continue
        name = f"v{number}"
        meta = read_meta(child)
        prompt = meta.get("prompt")
        prompt_str = prompt.strip() if isinstance(prompt, str) else None
        versions.append(
            ImageVersionInfo(
                name=name,
                number=number,
                path=child,
                run_date=_parse_run_date(meta.get("run_date")),
                prompt=prompt_str or None,
            )
        )
    return versions


def scan_versioned_image_files(root: Path) -> list[VersionedImageFile]:
    """Scan all image files inside ``vN/`` folders under ``root``."""
    files: list[VersionedImageFile] = []
    for version in load_image_versions(root):
        for path in sorted(version.path.iterdir()):
            if not path.is_file() or not is_allowed_image_filename(path.name):
                continue
            files.append(
                VersionedImageFile(
                    path=path,
                    version=version.name,
                    version_number=version.number,
                    relative_path=f"{version.name}/{path.name}",
                    filename=path.name,
                )
            )
    return files


def find_image_in_version(
    version_path: Path,
    stem: str,
    *,
    case_insensitive: bool = False,
) -> Path | None:
    """Return the image path for ``stem`` inside a version folder, if present."""
    if not version_path.is_dir():
        return None
    target = stem.lower() if case_insensitive else stem
    for path in version_path.iterdir():
        if not path.is_file() or path.suffix.lower() not in ALLOWED_IMAGE_EXTENSIONS:
            continue
        name = path.stem.lower() if case_insensitive else path.stem
        if name == target:
            return path
    return None


def pick_version_for_date(
    versions: list[ImageVersionInfo],
    *,
    as_of: datetime | None,
    force_v1: bool = False,
) -> ImageVersionInfo | None:
    """Pick the newest version whose run_date is <= as_of (or v1 when forced)."""
    if not versions:
        return None
    by_number = {v.number: v for v in versions}
    if force_v1:
        return by_number.get(1) or min(versions, key=lambda v: v.number)

    if as_of is None:
        return by_number.get(1) or min(versions, key=lambda v: v.number)

    as_of_utc = as_of if as_of.tzinfo else as_of.replace(tzinfo=timezone.utc)
    as_of_utc = as_of_utc.astimezone(timezone.utc)

    eligible = [
        v
        for v in versions
        if v.run_date is not None and v.run_date <= as_of_utc
    ]
    if eligible:
        return max(eligible, key=lambda v: (v.run_date or datetime.min.replace(tzinfo=timezone.utc), v.number))
    return by_number.get(1) or min(versions, key=lambda v: v.number)


def resolve_versioned_image_path(
    root: Path,
    stem: str,
    *,
    as_of: datetime | None = None,
    force_v1: bool = False,
    case_insensitive: bool = False,
) -> tuple[ImageVersionInfo, Path] | None:
    """Pick version + local file path for a stem, falling back to older versions."""
    versions = load_image_versions(root)
    if not versions:
        return None

    chosen = pick_version_for_date(versions, as_of=as_of, force_v1=force_v1)
    if chosen is None:
        return None

    # Prefer chosen version; if missing file, walk older versions by number desc.
    candidates = sorted(
        [v for v in versions if v.number <= chosen.number],
        key=lambda v: v.number,
        reverse=True,
    )
    for version in candidates:
        path = find_image_in_version(
            version.path,
            stem,
            case_insensitive=case_insensitive,
        )
        if path is not None:
            return version, path
    return None


def latest_version_with_stem(
    root: Path,
    stem: str,
    *,
    case_insensitive: bool = False,
) -> tuple[ImageVersionInfo, Path] | None:
    """Newest version (by run_date, then number) that contains ``stem``."""
    versions = load_image_versions(root)
    dated = [v for v in versions if v.run_date is not None]
    undated = [v for v in versions if v.run_date is None]
    ordered = sorted(
        dated,
        key=lambda v: (v.run_date or datetime.min.replace(tzinfo=timezone.utc), v.number),
        reverse=True,
    ) + sorted(undated, key=lambda v: v.number, reverse=True)
    for version in ordered:
        path = find_image_in_version(
            version.path,
            stem,
            case_insensitive=case_insensitive,
        )
        if path is not None:
            return version, path
    return None


def migrate_flat_images_to_v1(
    root: Path,
    *,
    default_prompt: str,
    backfill_run_date: datetime = BACKFILL_RUN_DATE,
    dry_run: bool = False,
) -> dict[str, int]:
    """Move loose image files at ``root`` into ``v1/`` and ensure meta.yaml."""
    moved = 0
    skipped = 0
    v1 = root / "v1"
    if not dry_run:
        v1.mkdir(parents=True, exist_ok=True)

    if root.is_dir():
        for path in sorted(root.iterdir()):
            if not path.is_file() or not is_allowed_image_filename(path.name):
                continue
            dest = v1 / path.name
            if dest.exists():
                logger.warning("Skip move %s; destination exists", dest)
                skipped += 1
                continue
            logger.info("%s %s -> %s", "Would move" if dry_run else "Moving", path, dest)
            if not dry_run:
                shutil.move(str(path), str(dest))
            moved += 1

    if not dry_run:
        ensure_version_meta(
            v1,
            default_prompt=default_prompt,
            run_date=backfill_run_date,
            preserve_existing_run_date=True,
        )
    return {"moved": moved, "skipped": skipped}


def safe_versioned_relative_path(relative: str) -> str:
    """Validate ``v1/foo.png`` style relative paths for admin upload."""
    text = relative.strip().replace("\\", "/")
    if not text or text.startswith("/") or ".." in text.split("/"):
        raise ValueError(f"Invalid relative image path: {relative!r}")
    parts = [p for p in text.split("/") if p]
    if len(parts) != 2:
        raise ValueError(
            f"Expected versioned path like v1/name.png, got {relative!r}"
        )
    version_part, filename = parts
    if parse_version_dir_name(version_part) is None:
        raise ValueError(f"Invalid version folder in path: {relative!r}")
    if not is_allowed_image_filename(filename):
        raise ValueError(f"Invalid image filename in path: {relative!r}")
    number = parse_version_dir_name(version_part)
    assert number is not None
    return f"v{number}/{filename}"


def build_versioned_media_url(
    public_base_url: str,
    curated_media_path: str,
    relative_path: str,
    *,
    content_version: str | None = None,
) -> str:
    media = curated_media_path if curated_media_path.endswith("/") else f"{curated_media_path}/"
    url = f"{public_base_url.rstrip('/')}{media}{relative_path}"
    if content_version:
        return f"{url}?v={content_version}"
    return url


def dir_has_versioned_or_flat_images(path: Path) -> bool:
    """True when path has flat images or any images under vN/ folders."""
    if not path.is_dir():
        return False
    for child in path.iterdir():
        if child.is_file() and is_allowed_image_filename(child.name):
            return True
        if child.is_dir() and parse_version_dir_name(child.name) is not None:
            if any(
                p.is_file() and is_allowed_image_filename(p.name)
                for p in child.iterdir()
            ):
                return True
    return False


@lru_cache(maxsize=8)
def _cached_versions_signature(root: str, mtime_key: float) -> tuple[ImageVersionInfo, ...]:
    del mtime_key  # used only as cache key
    return tuple(load_image_versions(Path(root)))


def load_image_versions_cached(root: Path) -> list[ImageVersionInfo]:
    """Cache version metadata keyed by directory mtime when available."""
    if not root.is_dir():
        return []
    try:
        mtime = root.stat().st_mtime
        for child in root.iterdir():
            if child.is_dir() and parse_version_dir_name(child.name) is not None:
                meta = child / META_FILENAME
                if meta.is_file():
                    mtime = max(mtime, meta.stat().st_mtime)
    except OSError:
        return load_image_versions(root)
    return list(_cached_versions_signature(str(root.resolve()), mtime))
