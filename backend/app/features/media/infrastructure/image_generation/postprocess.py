"""Post-process Imagen output to 3:4 portrait PNG."""

from __future__ import annotations

import io
from pathlib import Path

from PIL import Image as PILImage
from PIL import ImageOps

PORTRAIT_WIDTH_RATIO = 3
PORTRAIT_HEIGHT_RATIO = 4
OUTPUT_MAX_WIDTH = 768
OUTPUT_MAX_HEIGHT = 1024


def crop_to_portrait_3_4(img: PILImage.Image) -> PILImage.Image:
    """Center-crop to 3:4 portrait aspect ratio."""
    width, height = img.size
    target_ratio = PORTRAIT_WIDTH_RATIO / PORTRAIT_HEIGHT_RATIO
    current_ratio = width / height

    if abs(current_ratio - target_ratio) < 0.01:
        return img

    if current_ratio > target_ratio:
        new_width = int(height * target_ratio)
        left = (width - new_width) // 2
        return img.crop((left, 0, left + new_width, height))

    new_height = int(width / target_ratio)
    top = (height - new_height) // 2
    return img.crop((0, top, width, top + new_height))


def resize_portrait_cap(img: PILImage.Image) -> PILImage.Image:
    """Resize so the longest edge matches the 3:4 output cap."""
    width, height = img.size
    scale = min(OUTPUT_MAX_WIDTH / width, OUTPUT_MAX_HEIGHT / height, 1.0)
    if scale >= 1.0:
        return img
    new_size = (max(1, int(width * scale)), max(1, int(height * scale)))
    return img.resize(new_size, PILImage.Resampling.LANCZOS)


def process_image_bytes(image_bytes: bytes) -> bytes:
    """Normalize Imagen bytes to 3:4 portrait PNG."""
    img = PILImage.open(io.BytesIO(image_bytes))
    img = ImageOps.exif_transpose(img)
    if img.mode != "RGB":
        img = img.convert("RGB")
    img = crop_to_portrait_3_4(img)
    img = resize_portrait_cap(img)
    buffer = io.BytesIO()
    img.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def save_processed_png(image_bytes: bytes, output_path: Path) -> Path:
    """Post-process and write PNG to disk without overwriting."""
    if output_path.exists():
        raise FileExistsError(f"Refusing to overwrite existing image: {output_path}")
    processed = process_image_bytes(image_bytes)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(processed)
    return output_path
