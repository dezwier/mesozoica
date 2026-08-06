"""Profile image processing and storage."""

from __future__ import annotations

import io
from pathlib import Path

from fastapi import HTTPException, status
from PIL import Image

from app.core.config import settings


def process_user_profile_image(file_content: bytes) -> bytes:
    try:
        image = Image.open(io.BytesIO(file_content))
        image = image.convert("RGB")
        image.thumbnail((512, 512))
        output = io.BytesIO()
        image.save(output, format="JPEG", quality=85)
        return output.getvalue()
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid image file: {exc}",
        ) from exc


def save_user_image(username: str, image_bytes: bytes) -> Path:
    directory = settings.resolved_user_images_dir
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{username}.jpg"
    path.write_bytes(image_bytes)
    return path


def delete_user_image_file(image_url: str | None) -> None:
    if not image_url:
        return
    filename = image_url.rsplit("/", 1)[-1]
    if not filename.endswith(".jpg"):
        return
    path = settings.resolved_user_images_dir / filename
    if path.exists():
        path.unlink()
