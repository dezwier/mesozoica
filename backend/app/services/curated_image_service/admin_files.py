"""Shared FastAPI helpers for curated image admin upload/list/delete."""

from __future__ import annotations

import secrets
from pathlib import Path

from fastapi import Header, HTTPException, Request, status
from fastapi.responses import Response
from pydantic import BaseModel

from app.services.curated_image_service.common import is_allowed_image_filename
from app.services.curated_image_service.sync_prune import (
    delete_local_managed_file,
    list_managed_relative_paths,
    safe_managed_relative_path,
)
from app.services.curated_image_service.versions import (
    META_FILENAME,
    ORIGINAL_VERSION,
)


class CuratedImageListResponse(BaseModel):
    items: list[str]


def require_sync_secret(
    *,
    configured_secret: str,
    provided_header: str | None,
    unavailable_detail: str,
    invalid_detail: str,
) -> None:
    expected = configured_secret.strip()
    if not expected:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=unavailable_detail,
        )
    provided = (provided_header or "").strip()
    if not provided or not secrets.compare_digest(provided, expected):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=invalid_detail,
        )


def resolve_upload_relative_path(
    filepath: str,
    *,
    flat_to_original: bool = False,
) -> str:
    """Validate admin upload/delete path; optionally map flat images to Original/."""
    try:
        if "/" not in filepath and "\\" not in filepath:
            name = Path(filepath).name
            if name != filepath:
                raise ValueError(f"Invalid relative image path: {filepath!r}")
            if name == META_FILENAME:
                raise ValueError("meta.yaml must be uploaded under a version folder")
            if not is_allowed_image_filename(name):
                raise ValueError(f"Invalid image filename in path: {filepath!r}")
            if flat_to_original:
                return f"{ORIGINAL_VERSION}/{name}"
            return name
        return safe_managed_relative_path(filepath)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from exc


async def handle_upload(
    *,
    filepath: str,
    request: Request,
    target_dir: Path,
    flat_to_original: bool = False,
) -> Response:
    body = await request.body()
    safe_rel = resolve_upload_relative_path(
        filepath, flat_to_original=flat_to_original
    )
    if not body:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Body must not be empty.",
        )
    target_path = target_dir / safe_rel
    target_path.parent.mkdir(parents=True, exist_ok=True)
    target_path.write_bytes(body)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


def handle_list(*, target_dir: Path) -> CuratedImageListResponse:
    return CuratedImageListResponse(items=list_managed_relative_paths(target_dir))


def handle_delete(
    *,
    filepath: str,
    target_dir: Path,
    flat_to_original: bool = False,
) -> Response:
    safe_rel = resolve_upload_relative_path(
        filepath, flat_to_original=flat_to_original
    )
    deleted = delete_local_managed_file(target_dir, safe_rel)
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"File not found: {safe_rel}",
        )
    return Response(status_code=status.HTTP_204_NO_CONTENT)
