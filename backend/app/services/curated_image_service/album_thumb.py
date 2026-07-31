"""Album-grid WebP thumbs derived from full curated card images."""

from __future__ import annotations

import io
import logging
import tempfile
from pathlib import Path
from typing import Callable

from PIL import Image as PILImage
from PIL import ImageOps

from app.services.curated_image_service.common import (
    is_allowed_image_filename,
    needs_curated_image_resync,
)
from app.services.curated_image_service.versions import (
    load_image_versions,
    scan_versioned_image_files,
)

logger = logging.getLogger(__name__)

ALBUM_DIR_NAME = "album"
ALBUM_MAX_WIDTH = 384
ALBUM_MAX_HEIGHT = 512
ALBUM_WEBP_QUALITY = 80
ALBUM_EXT = ".webp"


def album_relative_path_for(full_relative_path: str) -> str:
    """Map ``Original/Name.png`` → ``Original/album/Name.webp``."""
    text = full_relative_path.strip().replace("\\", "/")
    parts = [p for p in text.split("/") if p]
    if len(parts) != 2:
        raise ValueError(
            f"Expected versioned full image path like Original/Name.png, "
            f"got {full_relative_path!r}"
        )
    version, filename = parts
    stem = Path(filename).stem
    if not stem:
        raise ValueError(f"Invalid image filename in path: {full_relative_path!r}")
    return f"{version}/{ALBUM_DIR_NAME}/{stem}{ALBUM_EXT}"


def is_album_relative_path(relative: str) -> bool:
    """True for ``Original/album/Name.webp`` style paths."""
    text = relative.strip().replace("\\", "/")
    parts = [p for p in text.split("/") if p]
    return (
        len(parts) == 3
        and parts[1] == ALBUM_DIR_NAME
        and is_allowed_image_filename(parts[2])
    )


def list_local_album_relative_paths(root: Path) -> list[str]:
    """Album thumbs already present under version folders on disk."""
    paths: list[str] = []
    if not root.is_dir():
        return paths
    for version in load_image_versions(root):
        album_dir = version.path / ALBUM_DIR_NAME
        if not album_dir.is_dir():
            continue
        for path in sorted(album_dir.iterdir()):
            if path.is_file() and is_allowed_image_filename(path.name):
                paths.append(f"{version.name}/{ALBUM_DIR_NAME}/{path.name}")
    return paths


def derived_album_relative_paths(root: Path) -> set[str]:
    """Album paths implied by every versioned full image (even if thumb missing locally)."""
    return {
        album_relative_path_for(item.relative_path)
        for item in scan_versioned_image_files(root)
    }


def generate_album_thumb_bytes(image_bytes: bytes) -> bytes:
    """Resize full card art to album max and encode WebP."""
    img = PILImage.open(io.BytesIO(image_bytes))
    img = ImageOps.exif_transpose(img)
    if img.mode not in ("RGB", "RGBA"):
        img = img.convert("RGBA" if "A" in img.getbands() else "RGB")
    img.thumbnail((ALBUM_MAX_WIDTH, ALBUM_MAX_HEIGHT), PILImage.Resampling.LANCZOS)
    if img.mode == "RGBA":
        # WebP keeps alpha; convert opaque RGB when no transparency needed.
        if img.getchannel("A").getextrema() == (255, 255):
            img = img.convert("RGB")
    buffer = io.BytesIO()
    img.save(buffer, format="WEBP", quality=ALBUM_WEBP_QUALITY, method=4)
    return buffer.getvalue()


def write_album_thumb(source_path: Path, dest_path: Path) -> Path:
    """Generate album WebP from ``source_path`` and write to ``dest_path``."""
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    dest_path.write_bytes(generate_album_thumb_bytes(source_path.read_bytes()))
    return dest_path


UploadFileFn = Callable[..., None]


def sync_album_thumb_for_image(
    *,
    local_full_path: Path,
    full_relative_path: str,
    public_base_url: str,
    curated_media_path: str,
    sync_secret: str,
    upload_file: UploadFileFn,
    overwrite: bool = False,
    dry_run: bool = False,
) -> bool:
    """Generate and upload an album thumb when missing/stale. Returns True if uploaded."""
    album_rel = album_relative_path_for(full_relative_path)
    if not needs_curated_image_resync(
        overwrite=overwrite,
        local_path=local_full_path,
        main_image_url=None,
        public_base_url=public_base_url,
        filename=album_rel,
        curated_media_path=curated_media_path,
    ):
        return False

    logger.info(
        "%s %s",
        "Would upload album" if dry_run else "Upload album",
        album_rel,
    )
    if dry_run:
        return True

    with tempfile.TemporaryDirectory(prefix="mesozoica-album-") as tmp:
        thumb_path = Path(tmp) / Path(album_rel).name
        write_album_thumb(local_full_path, thumb_path)
        upload_file(
            local_path=thumb_path,
            remote_filename=album_rel,
            public_base_url=public_base_url,
            sync_secret=sync_secret,
        )
    return True
