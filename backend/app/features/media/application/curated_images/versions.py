"""Named curated image version folders (Original/, Summer 26/, …) with meta.yaml."""

from __future__ import annotations

import logging
import shutil
from dataclasses import dataclass
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path
from typing import Any

import yaml

from app.features.media.application.curated_images.common import (
    ALLOWED_IMAGE_EXTENSIONS,
    file_content_version,
    is_allowed_image_filename,
)

logger = logging.getLogger(__name__)

META_FILENAME = "meta.yaml"
ORIGINAL_VERSION = "Original"
SUMMER_26_VERSION = "Summer 26"
AUGUST_2026_VERSION = "August 2026"
BACKFILL_RUN_DATE = datetime(2026, 7, 29, 0, 0, 0, tzinfo=timezone.utc)

# Legacy numeric folder names from before named versions.
_LEGACY_VERSION_MAP = {
    "v1": ORIGINAL_VERSION,
    "v2": SUMMER_26_VERSION,
}

# Directories that are never treated as image version folders.
_SKIP_DIR_NAMES = frozenset(
    {
        ".git",
        ".DS_Store",
        "__pycache__",
        "node_modules",
    }
)


@dataclass(frozen=True)
class ImageVersionInfo:
    """One version folder under a curated image root."""

    name: str
    path: Path
    run_date: datetime | None
    prompt: str | None


@dataclass(frozen=True)
class VersionedImageFile:
    """A single image file inside a version folder."""

    path: Path
    version: str
    relative_path: str  # e.g. "Original/cretaceous_sandstone.png"
    filename: str


def normalize_version_name(raw: str | None) -> str:
    """Accept a non-empty version folder name string."""
    if raw is None or not str(raw).strip():
        raise ValueError("Image version is required (e.g. 'Original' or 'Summer 26')")
    text = str(raw).strip()
    if "/" in text or "\\" in text or text in (".", ".."):
        raise ValueError(f"Invalid image version {raw!r}")
    # Map legacy CLI values if someone still passes v1/v2.
    legacy = _LEGACY_VERSION_MAP.get(text.lower())
    if legacy is not None:
        return legacy
    return text


def require_generation_version(version: str | None) -> str:
    """Require an explicit version name for image generate jobs."""
    return normalize_version_name(version)


def version_dir(root: Path, version: str | None) -> Path:
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
        formatted = _format_run_date(existing_run)
        if meta.get("run_date") != formatted:
            meta["run_date"] = formatted
            changed = True

    if changed or not (version_path / META_FILENAME).is_file():
        write_meta(version_path, meta)
    return meta


def is_version_dir_name(name: str) -> bool:
    """True when ``name`` can be a curated image version folder."""
    text = name.strip()
    if not text or text.startswith(".") or text in _SKIP_DIR_NAMES:
        return False
    if "/" in text or "\\" in text:
        return False
    return True


def load_image_versions(root: Path) -> list[ImageVersionInfo]:
    """List version folders under ``root``, sorted by run_date then name."""
    if not root.is_dir():
        return []
    versions: list[ImageVersionInfo] = []
    for child in sorted(root.iterdir(), key=lambda p: p.name.lower()):
        if not child.is_dir() or not is_version_dir_name(child.name):
            continue
        meta = read_meta(child)
        prompt = meta.get("prompt")
        prompt_str = prompt.strip() if isinstance(prompt, str) else None
        versions.append(
            ImageVersionInfo(
                name=child.name,
                path=child,
                run_date=_parse_run_date(meta.get("run_date")),
                prompt=prompt_str or None,
            )
        )
    versions.sort(
        key=lambda v: (
            v.run_date or datetime.min.replace(tzinfo=timezone.utc),
            v.name.lower(),
        )
    )
    return versions


def bundled_version_meta_root() -> Path:
    """``app/data/curated_version_meta`` — run_date metas shipped in the Docker image."""
    return Path(__file__).resolve().parents[4] / "data" / "curated_version_meta"


def bundled_version_meta_dir(kind: str) -> Path:
    """Bundled meta root for one curated kind (``site-types``, ``tools``, …)."""
    return bundled_version_meta_root() / kind


def merge_image_versions(*roots: Path) -> list[ImageVersionInfo]:
    """Union version folders from multiple roots; newer ``run_date`` wins per name."""
    by_name: dict[str, ImageVersionInfo] = {}
    for root in roots:
        for version in load_image_versions(root):
            existing = by_name.get(version.name)
            if existing is None:
                by_name[version.name] = version
                continue
            existing_date = existing.run_date
            new_date = version.run_date
            if new_date is not None and (
                existing_date is None or new_date > existing_date
            ):
                by_name[version.name] = version
    return list(by_name.values())


def latest_version_by_run_date(root: Path) -> ImageVersionInfo | None:
    """Newest version by meta ``run_date`` (undated last). Used when creating occurrences."""
    return pick_latest_version(load_image_versions(root))


def pick_latest_version(versions: list[ImageVersionInfo]) -> ImageVersionInfo | None:
    """Newest version by ``run_date``, then name; undated versions sort last."""
    if not versions:
        return None
    dated = [v for v in versions if v.run_date is not None]
    if dated:
        return max(
            dated,
            key=lambda v: (
                v.run_date or datetime.min.replace(tzinfo=timezone.utc),
                v.name,
            ),
        )
    # Prefer Original when nothing is dated, else last by name.
    by_name = {v.name: v for v in versions}
    if ORIGINAL_VERSION in by_name:
        return by_name[ORIGINAL_VERSION]
    return sorted(versions, key=lambda v: v.name.lower())[-1]


def latest_version_name(root: Path, *, default: str = ORIGINAL_VERSION) -> str:
    """Folder name of the newest version, or ``default`` when none exist."""
    latest = latest_version_by_run_date(root)
    return latest.name if latest is not None else default


def latest_version_name_with_bundled(
    storage_root: Path,
    *,
    kind: str,
    default: str = ORIGINAL_VERSION,
) -> str:
    """Newest version using storage metas merged with bundled run_dates.

    Workers (e.g. field-generate) often lack the curated-image volume. Bundled
    ``app/data/curated_version_meta/<kind>/`` ships run_dates in the image so
    occurrence version assignment still follows ``images/*/meta.yaml``.
    """
    versions = merge_image_versions(storage_root, bundled_version_meta_dir(kind))
    latest = pick_latest_version(versions)
    return latest.name if latest is not None else default


def latest_tool_image_version() -> str:
    from app.core.config import settings

    return latest_version_name_with_bundled(
        settings.resolved_tool_images_dir, kind="tools"
    )


def latest_site_type_image_version() -> str:
    from app.core.config import settings

    return latest_version_name_with_bundled(
        settings.resolved_site_type_images_dir, kind="site-types"
    )


def latest_fossil_image_version() -> str:
    from app.core.config import settings

    return latest_version_name_with_bundled(
        settings.resolved_fossil_images_dir, kind="fossils"
    )


def latest_dinosaur_image_version() -> str:
    from app.core.config import settings

    return latest_version_name_with_bundled(
        settings.resolved_dinosaur_images_dir, kind="dinosaurs"
    )


def scan_versioned_image_files(root: Path) -> list[VersionedImageFile]:
    """Scan all image files inside version folders under ``root``."""
    files: list[VersionedImageFile] = []
    for version in load_image_versions(root):
        for path in sorted(version.path.iterdir()):
            if not path.is_file() or not is_allowed_image_filename(path.name):
                continue
            files.append(
                VersionedImageFile(
                    path=path,
                    version=version.name,
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


def resolve_versioned_image_path(
    root: Path,
    stem: str,
    *,
    version: str | None = None,
    case_insensitive: bool = False,
) -> tuple[ImageVersionInfo, Path] | None:
    """Pick version + local file path for a stem by exact version name.

    Falls back to ``Original``, then any version that has the stem.
    """
    versions = load_image_versions(root)
    if not versions:
        return None

    requested = (version or ORIGINAL_VERSION).strip() or ORIGINAL_VERSION
    by_name = {v.name: v for v in versions}

    candidates: list[ImageVersionInfo] = []
    if requested in by_name:
        candidates.append(by_name[requested])
    if ORIGINAL_VERSION in by_name and by_name[ORIGINAL_VERSION] not in candidates:
        candidates.append(by_name[ORIGINAL_VERSION])
    for v in reversed(versions):
        if v not in candidates:
            candidates.append(v)

    for info in candidates:
        path = find_image_in_version(
            info.path,
            stem,
            case_insensitive=case_insensitive,
        )
        if path is not None:
            return info, path
    return None


def latest_version_with_stem(
    root: Path,
    stem: str,
    *,
    case_insensitive: bool = False,
) -> tuple[ImageVersionInfo, Path] | None:
    """Newest version (by run_date) that contains ``stem``."""
    versions = load_image_versions(root)
    dated = [v for v in versions if v.run_date is not None]
    undated = [v for v in versions if v.run_date is None]
    ordered = sorted(
        dated,
        key=lambda v: (v.run_date or datetime.min.replace(tzinfo=timezone.utc), v.name),
        reverse=True,
    ) + sorted(undated, key=lambda v: v.name, reverse=True)
    for version in ordered:
        path = find_image_in_version(
            version.path,
            stem,
            case_insensitive=case_insensitive,
        )
        if path is not None:
            return version, path
    return None


def migrate_flat_images_to_version(
    root: Path,
    *,
    version_name: str = ORIGINAL_VERSION,
    default_prompt: str,
    backfill_run_date: datetime = BACKFILL_RUN_DATE,
    dry_run: bool = False,
) -> dict[str, int]:
    """Move loose image files at ``root`` into a version folder and ensure meta.yaml."""
    moved = 0
    skipped = 0
    target = root / version_name
    if not dry_run:
        target.mkdir(parents=True, exist_ok=True)

    if root.is_dir():
        for path in sorted(root.iterdir()):
            if not path.is_file() or not is_allowed_image_filename(path.name):
                continue
            dest = target / path.name
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
            target,
            default_prompt=default_prompt,
            run_date=backfill_run_date,
            preserve_existing_run_date=True,
        )
    return {"moved": moved, "skipped": skipped}


# Back-compat alias used by older scripts/tests.
def migrate_flat_images_to_v1(
    root: Path,
    *,
    default_prompt: str,
    backfill_run_date: datetime = BACKFILL_RUN_DATE,
    dry_run: bool = False,
) -> dict[str, int]:
    return migrate_flat_images_to_version(
        root,
        version_name=ORIGINAL_VERSION,
        default_prompt=default_prompt,
        backfill_run_date=backfill_run_date,
        dry_run=dry_run,
    )


def rename_legacy_version_folders(
    root: Path,
    *,
    dry_run: bool = False,
) -> dict[str, int]:
    """Rename ``v1``→``Original`` and ``v2``→``Summer 26`` under ``root``."""
    renamed = 0
    skipped = 0
    if not root.is_dir():
        return {"renamed": 0, "skipped": 0}
    for legacy, target_name in (
        ("v1", ORIGINAL_VERSION),
        ("v2", SUMMER_26_VERSION),
    ):
        src = root / legacy
        if not src.is_dir():
            continue
        dest = root / target_name
        if dest.exists():
            logger.warning("Skip rename %s; destination exists: %s", src, dest)
            skipped += 1
            continue
        logger.info(
            "%s %s -> %s",
            "Would rename" if dry_run else "Renaming",
            src,
            dest,
        )
        if not dry_run:
            src.rename(dest)
        renamed += 1
    return {"renamed": renamed, "skipped": skipped}


def safe_versioned_relative_path(relative: str) -> str:
    """Validate ``Original/foo.png`` style relative paths for admin upload."""
    text = relative.strip().replace("\\", "/")
    if not text or text.startswith("/") or ".." in text.split("/"):
        raise ValueError(f"Invalid relative image path: {relative!r}")
    parts = [p for p in text.split("/") if p]
    if len(parts) != 2:
        raise ValueError(
            f"Expected versioned path like Original/name.png, got {relative!r}"
        )
    version_part, filename = parts
    version_part = normalize_version_name(version_part)
    if not is_version_dir_name(version_part):
        raise ValueError(f"Invalid version folder in path: {relative!r}")
    if not is_allowed_image_filename(filename):
        raise ValueError(f"Invalid image filename in path: {relative!r}")
    return f"{version_part}/{filename}"


def build_versioned_media_url(
    public_base_url: str,
    curated_media_path: str,
    relative_path: str,
    *,
    content_version: str | None = None,
) -> str:
    media = curated_media_path if curated_media_path.endswith("/") else f"{curated_media_path}/"
    # Encode spaces in version folder names for URLs.
    encoded_relative = "/".join(
        part.replace(" ", "%20") for part in relative_path.replace("\\", "/").split("/")
    )
    url = f"{public_base_url.rstrip('/')}{media}{encoded_relative}"
    if content_version:
        return f"{url}?v={content_version}"
    return url


def dir_has_versioned_or_flat_images(path: Path) -> bool:
    """True when path has flat images or any images under version folders."""
    if not path.is_dir():
        return False
    for child in path.iterdir():
        if child.is_file() and is_allowed_image_filename(child.name):
            return True
        if child.is_dir() and is_version_dir_name(child.name):
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
            if child.is_dir() and is_version_dir_name(child.name):
                meta = child / META_FILENAME
                if meta.is_file():
                    mtime = max(mtime, meta.stat().st_mtime)
    except OSError:
        return load_image_versions(root)
    return list(_cached_versions_signature(str(root.resolve()), mtime))


# Re-export for callers that still import the cache-busting helper from here.
__all__ = [
    "ORIGINAL_VERSION",
    "SUMMER_26_VERSION",
    "AUGUST_2026_VERSION",
    "BACKFILL_RUN_DATE",
    "META_FILENAME",
    "ImageVersionInfo",
    "VersionedImageFile",
    "normalize_version_name",
    "require_generation_version",
    "version_dir",
    "ensure_version_meta",
    "load_image_versions",
    "merge_image_versions",
    "pick_latest_version",
    "latest_version_by_run_date",
    "latest_version_name",
    "latest_version_name_with_bundled",
    "bundled_version_meta_root",
    "bundled_version_meta_dir",
    "latest_tool_image_version",
    "latest_site_type_image_version",
    "latest_fossil_image_version",
    "latest_dinosaur_image_version",
    "scan_versioned_image_files",
    "find_image_in_version",
    "resolve_versioned_image_path",
    "latest_version_with_stem",
    "migrate_flat_images_to_version",
    "migrate_flat_images_to_v1",
    "rename_legacy_version_folders",
    "safe_versioned_relative_path",
    "build_versioned_media_url",
    "dir_has_versioned_or_flat_images",
    "load_image_versions_cached",
    "is_version_dir_name",
    "read_meta",
    "write_meta",
    "file_content_version",
]
