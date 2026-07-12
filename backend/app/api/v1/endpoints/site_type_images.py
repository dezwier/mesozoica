"""Admin upload endpoint for curated site-type card images."""

from __future__ import annotations

import secrets
from pathlib import Path

from fastapi import APIRouter, Depends, Header, HTTPException, Request, status
from fastapi.responses import Response

from app.core.config import settings
from app.services.site_type_image_service.sync import (
    ALLOWED_IMAGE_EXTENSIONS,
    is_allowed_image_filename,
)

router = APIRouter(prefix="/admin/site-type-images", tags=["admin"])


def _require_sync_secret(
    x_site_type_image_sync_key: str | None = Header(default=None),
) -> None:
    expected = settings.site_type_image_sync_secret.strip()
    if not expected:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Site-type image sync is not configured on this server.",
        )
    provided = (x_site_type_image_sync_key or "").strip()
    if not provided or not secrets.compare_digest(provided, expected):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid site-type image sync key.",
        )


def _safe_filename(filename: str) -> str:
    name = Path(filename).name
    if name != filename or not is_allowed_image_filename(name):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid image filename. Allowed extensions: {sorted(ALLOWED_IMAGE_EXTENSIONS)}",
        )
    return name


@router.put("/{filename}")
async def upload_site_type_image(
    filename: str,
    request: Request,
    _: None = Depends(_require_sync_secret),
) -> Response:
    body = await request.body()
    safe_name = _safe_filename(filename)
    if not body:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Image body must not be empty.",
        )

    target_dir = settings.resolved_site_type_images_dir
    target_dir.mkdir(parents=True, exist_ok=True)
    target_path = target_dir / safe_name
    target_path.write_bytes(body)

    return Response(status_code=status.HTTP_204_NO_CONTENT)
