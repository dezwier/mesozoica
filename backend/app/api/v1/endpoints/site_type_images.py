"""Admin upload endpoint for curated site-type card images."""

from __future__ import annotations

import secrets
from pathlib import Path

from fastapi import APIRouter, Depends, Header, HTTPException, Request, status
from fastapi.responses import Response

from app.core.config import settings
from app.services.curated_image_service.versions import safe_versioned_relative_path
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


def _safe_relative_path(filename: str) -> str:
    # Legacy flat uploads: basename only.
    if "/" not in filename and "\\" not in filename:
        name = Path(filename).name
        if name != filename or not is_allowed_image_filename(name):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    f"Invalid image filename. Allowed extensions: "
                    f"{sorted(ALLOWED_IMAGE_EXTENSIONS)}"
                ),
            )
        return name
    try:
        return safe_versioned_relative_path(filename)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from exc


@router.put("/{filepath:path}")
async def upload_site_type_image(
    filepath: str,
    request: Request,
    _: None = Depends(_require_sync_secret),
) -> Response:
    body = await request.body()
    safe_rel = _safe_relative_path(filepath)
    if not body:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Image body must not be empty.",
        )

    target_dir = settings.resolved_site_type_images_dir
    target_path = target_dir / safe_rel
    target_path.parent.mkdir(parents=True, exist_ok=True)
    target_path.write_bytes(body)

    return Response(status_code=status.HTTP_204_NO_CONTENT)
