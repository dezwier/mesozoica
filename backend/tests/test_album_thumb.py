"""Tests for album-grid WebP thumb generation and path helpers."""

from __future__ import annotations

import io
from pathlib import Path

from PIL import Image as PILImage

from app.services.curated_image_service.album_thumb import (
    ALBUM_MAX_HEIGHT,
    ALBUM_MAX_WIDTH,
    album_relative_path_for,
    derived_album_relative_paths,
    generate_album_thumb_bytes,
    is_album_relative_path,
    write_album_thumb,
)
from app.services.curated_image_service.versions import ORIGINAL_VERSION


def _rgb_png_bytes(width: int, height: int) -> bytes:
    img = PILImage.new("RGB", (width, height), color=(40, 80, 120))
    buffer = io.BytesIO()
    img.save(buffer, format="PNG")
    return buffer.getvalue()


def test_album_relative_path_for():
    assert album_relative_path_for("Original/Tyrannosaurus.png") == (
        "Original/album/Tyrannosaurus.webp"
    )
    assert album_relative_path_for("Summer 26/foo.JPEG") == (
        "Summer 26/album/foo.webp"
    )


def test_is_album_relative_path():
    assert is_album_relative_path("Original/album/Tyrannosaurus.webp")
    assert not is_album_relative_path("Original/Tyrannosaurus.png")
    assert not is_album_relative_path("Original/thumbs/x.webp")


def test_generate_album_thumb_bytes_caps_size():
    raw = _rgb_png_bytes(1086, 1448)
    thumb = generate_album_thumb_bytes(raw)
    img = PILImage.open(io.BytesIO(thumb))
    assert img.format == "WEBP"
    assert img.width <= ALBUM_MAX_WIDTH
    assert img.height <= ALBUM_MAX_HEIGHT
    # 3:4 portrait preserved within rounding.
    assert abs(img.width / img.height - 3 / 4) < 0.02


def test_write_album_thumb(tmp_path: Path):
    source = tmp_path / "full.png"
    source.write_bytes(_rgb_png_bytes(768, 1024))
    dest = tmp_path / "out.webp"
    write_album_thumb(source, dest)
    assert dest.is_file()
    img = PILImage.open(dest)
    assert img.format == "WEBP"
    assert img.width <= ALBUM_MAX_WIDTH


def test_ensure_local_album_thumb_writes_beside_full(tmp_path: Path):
    from app.services.curated_image_service.album_thumb import ensure_local_album_thumb

    version = tmp_path / "Original"
    version.mkdir()
    full = version / "Tyrannosaurus.png"
    full.write_bytes(_rgb_png_bytes(768, 1024))

    thumb = ensure_local_album_thumb(
        local_full_path=full,
        full_relative_path="Original/Tyrannosaurus.png",
    )
    assert thumb == version / "album" / "Tyrannosaurus.webp"
    assert thumb.is_file()
    img = PILImage.open(thumb)
    assert img.format == "WEBP"
    assert img.width <= ALBUM_MAX_WIDTH


def test_derived_album_relative_paths(tmp_path: Path):
    original = tmp_path / ORIGINAL_VERSION
    original.mkdir()
    (original / "A.png").write_bytes(b"x")
    (original / "B.webp").write_bytes(b"y")
    assert derived_album_relative_paths(tmp_path) == {
        "Original/album/A.webp",
        "Original/album/B.webp",
    }
