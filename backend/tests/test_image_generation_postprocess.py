"""Tests for 3:4 portrait post-processing."""

from __future__ import annotations

import io
from pathlib import Path

import pytest
from PIL import Image as PILImage

from app.services.image_generation_service.postprocess import (
    crop_to_portrait_3_4,
    process_image_bytes,
    resize_portrait_cap,
    save_processed_png,
)


def _make_image(width: int, height: int, color: str = "red") -> bytes:
    img = PILImage.new("RGB", (width, height), color=color)
    buffer = io.BytesIO()
    img.save(buffer, format="PNG")
    return buffer.getvalue()


def test_crop_to_portrait_3_4_from_square():
    img = PILImage.open(io.BytesIO(_make_image(1024, 1024)))
    cropped = crop_to_portrait_3_4(img)
    width, height = cropped.size
    assert abs((width / height) - (3 / 4)) < 0.02
    assert width == 768
    assert height == 1024


def test_crop_to_portrait_3_4_from_landscape():
    img = PILImage.open(io.BytesIO(_make_image(1600, 900)))
    cropped = crop_to_portrait_3_4(img)
    width, height = cropped.size
    assert abs((width / height) - (3 / 4)) < 0.02


def test_resize_portrait_cap_does_not_upscale():
    img = PILImage.new("RGB", (300, 400), color="blue")
    resized = resize_portrait_cap(img)
    assert resized.size == (300, 400)


def test_process_image_bytes_returns_png():
    processed = process_image_bytes(_make_image(1200, 800))
    img = PILImage.open(io.BytesIO(processed))
    assert img.format == "PNG"
    width, height = img.size
    assert abs((width / height) - (3 / 4)) < 0.02


def test_save_processed_png_writes_file(tmp_path: Path):
    output = tmp_path / "Tyrannosaurus.png"
    save_processed_png(_make_image(1024, 1024), output)
    assert output.is_file()
    img = PILImage.open(output)
    assert img.format == "PNG"
