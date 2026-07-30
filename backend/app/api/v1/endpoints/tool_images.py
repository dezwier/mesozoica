"""Admin upload/list/delete endpoint for curated tool card images."""

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

router = APIRouter(prefix="/admin/tool-images", tags=["admin"])


def _require_sync_secret(
    x_tool_image_sync_key: str | None = Header(default=None),
) -> None:
    require_sync_secret(
        configured_secret=settings.tool_image_sync_secret,
        provided_header=x_tool_image_sync_key,
        unavailable_detail="Tool image sync is not configured on this server.",
        invalid_detail="Invalid tool image sync key.",
    )


@router.get("", response_model=CuratedImageListResponse)
def list_tool_images(
    _: None = Depends(_require_sync_secret),
) -> CuratedImageListResponse:
    return handle_list(target_dir=settings.resolved_tool_images_dir)


@router.put("/{filepath:path}")
async def upload_tool_image(
    filepath: str,
    request: Request,
    _: None = Depends(_require_sync_secret),
) -> Response:
    return await handle_upload(
        filepath=filepath,
        request=request,
        target_dir=settings.resolved_tool_images_dir,
    )


@router.delete("/{filepath:path}")
def delete_tool_image(
    filepath: str,
    _: None = Depends(_require_sync_secret),
) -> Response:
    return handle_delete(
        filepath=filepath,
        target_dir=settings.resolved_tool_images_dir,
    )
