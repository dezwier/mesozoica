"""Admin upload/list/delete endpoint for curated site-type card images."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Header, Request
from fastapi.responses import Response

from app.core.config import settings
from app.services.curated_image_service.admin_files import (
    CuratedImageListResponse,
    handle_delete,
    handle_list,
    handle_upload,
    require_sync_secret,
)

router = APIRouter(prefix="/admin/site-type-images", tags=["admin"])


def _require_sync_secret(
    x_site_type_image_sync_key: str | None = Header(default=None),
) -> None:
    require_sync_secret(
        configured_secret=settings.site_type_image_sync_secret,
        provided_header=x_site_type_image_sync_key,
        unavailable_detail="Site-type image sync is not configured on this server.",
        invalid_detail="Invalid site-type image sync key.",
    )


@router.get("", response_model=CuratedImageListResponse)
def list_site_type_images(
    _: None = Depends(_require_sync_secret),
) -> CuratedImageListResponse:
    return handle_list(target_dir=settings.resolved_site_type_images_dir)


@router.put("/{filepath:path}")
async def upload_site_type_image(
    filepath: str,
    request: Request,
    _: None = Depends(_require_sync_secret),
) -> Response:
    return await handle_upload(
        filepath=filepath,
        request=request,
        target_dir=settings.resolved_site_type_images_dir,
    )


@router.delete("/{filepath:path}")
def delete_site_type_image(
    filepath: str,
    _: None = Depends(_require_sync_secret),
) -> Response:
    return handle_delete(
        filepath=filepath,
        target_dir=settings.resolved_site_type_images_dir,
    )
