"""Local curated image folder helpers for generation jobs."""

from __future__ import annotations

from pathlib import Path

from app.services.curated_image_service.common import ALLOWED_IMAGE_EXTENSIONS


def scan_existing_stems(directory: Path, *, case_insensitive: bool = False) -> set[str]:
    """Return filename stems that already have a curated image file."""
    if not directory.is_dir():
        return set()
    stems: set[str] = set()
    for path in directory.iterdir():
        if not path.is_file():
            continue
        if path.suffix.lower() not in ALLOWED_IMAGE_EXTENSIONS:
            continue
        stem = path.stem.lower() if case_insensitive else path.stem
        stems.add(stem)
    return stems


def has_local_image(
    directory: Path,
    stem: str,
    *,
    existing_stems: set[str] | None = None,
    case_insensitive: bool = False,
) -> bool:
    """True when any allowed image extension exists for ``stem``."""
    if existing_stems is not None:
        key = stem.lower() if case_insensitive else stem
        return key in existing_stems

    for ext in ALLOWED_IMAGE_EXTENSIONS:
        candidate = directory / f"{stem}{ext}"
        if candidate.is_file():
            return True
        if case_insensitive:
            for path in directory.glob(f"{stem}.*"):
                if path.is_file() and path.suffix.lower() in ALLOWED_IMAGE_EXTENSIONS:
                    return True
            for path in directory.iterdir():
                if (
                    path.is_file()
                    and path.stem.lower() == stem.lower()
                    and path.suffix.lower() in ALLOWED_IMAGE_EXTENSIONS
                ):
                    return True
            return False
    return False


def output_png_path(directory: Path, stem: str) -> Path:
    """Target PNG path for a newly generated image."""
    directory.mkdir(parents=True, exist_ok=True)
    return directory / f"{stem}.png"
