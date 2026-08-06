"""List/delete/prune helpers for curated image roots (local + remote sync)."""

from __future__ import annotations

import logging
from pathlib import Path
from urllib.parse import quote

import httpx

from app.features.media.application.curated_images.album_thumb import (
    ALBUM_DIR_NAME,
    derived_album_relative_paths,
    list_local_album_relative_paths,
)
from app.features.media.application.curated_images.common import (
    is_allowed_image_filename,
    scan_local_image_files,
)
from app.features.media.application.curated_images.versions import (
    META_FILENAME,
    is_version_dir_name,
    load_image_versions,
    scan_versioned_image_files,
)

logger = logging.getLogger(__name__)


def list_managed_relative_paths(root: Path) -> list[str]:
    """Relative paths managed under a curated image root (images + meta + album thumbs)."""
    paths: set[str] = set()
    if not root.is_dir():
        return []

    for item in scan_versioned_image_files(root):
        paths.add(item.relative_path)

    for version in load_image_versions(root):
        meta = version.path / META_FILENAME
        if meta.is_file():
            paths.add(f"{version.name}/{META_FILENAME}")

    for flat in scan_local_image_files(root):
        paths.add(flat.name)

    # Local album files plus derived album paths for every full image so remote
    # thumbs are not pruned when they only exist on Railway.
    paths.update(list_local_album_relative_paths(root))
    paths.update(derived_album_relative_paths(root))

    return sorted(paths)


def safe_managed_relative_path(relative: str) -> str:
    """Validate managed paths under a curated root.

    Accepts flat ``foo.png``, ``Original/foo.png``, ``Original/meta.yaml``, or
    album thumbs ``Original/album/foo.webp``.

    Does not remap legacy names (``v1`` stays ``v1``) so prune can delete remote
    folders that still use old layout names.
    """
    text = relative.strip().replace("\\", "/")
    if not text or text.startswith("/") or ".." in text.split("/"):
        raise ValueError(f"Invalid relative image path: {relative!r}")
    parts = [p for p in text.split("/") if p]
    if len(parts) == 1:
        filename = parts[0]
        if not is_allowed_image_filename(filename):
            raise ValueError(f"Invalid image filename in path: {relative!r}")
        return filename
    if len(parts) == 3:
        version_part, album_part, filename = parts
        version_part = version_part.strip()
        if not is_version_dir_name(version_part):
            raise ValueError(f"Invalid version folder in path: {relative!r}")
        if album_part != ALBUM_DIR_NAME:
            raise ValueError(
                f"Expected album path like Original/album/name.webp, got {relative!r}"
            )
        if not is_allowed_image_filename(filename):
            raise ValueError(f"Invalid image filename in path: {relative!r}")
        return f"{version_part}/{ALBUM_DIR_NAME}/{filename}"
    if len(parts) != 2:
        raise ValueError(
            f"Expected path like Original/name.png or Original/album/name.webp, "
            f"got {relative!r}"
        )
    version_part, filename = parts
    version_part = version_part.strip()
    if not is_version_dir_name(version_part):
        raise ValueError(f"Invalid version folder in path: {relative!r}")
    if filename == META_FILENAME:
        return f"{version_part}/{META_FILENAME}"
    if not is_allowed_image_filename(filename):
        raise ValueError(f"Invalid image filename in path: {relative!r}")
    return f"{version_part}/{filename}"


def delete_local_managed_file(root: Path, relative: str) -> bool:
    """Delete a managed file under ``root``. Returns True when a file was removed."""
    safe_rel = safe_managed_relative_path(relative)
    root_resolved = root.resolve()
    target = (root / safe_rel).resolve()
    try:
        target.relative_to(root_resolved)
    except ValueError as exc:
        raise ValueError(f"Path escapes curated root: {relative!r}") from exc
    if not target.is_file():
        return False
    target.unlink()
    parent = target.parent
    if parent != root_resolved and parent.is_dir() and not any(parent.iterdir()):
        parent.rmdir()
    return True


def list_remote_managed_paths(
    *,
    public_base_url: str,
    sync_secret: str,
    admin_upload_path: str,
    sync_header_name: str,
    sync_secret_env_var: str,
    dry_run: bool = False,
) -> list[str]:
    """GET the remote curated image inventory from the admin list endpoint."""
    del dry_run  # list is always read-only
    secret = sync_secret.strip()
    if not secret:
        raise RuntimeError(f"{sync_secret_env_var} must be set to list remote curated images.")

    url = f"{public_base_url.rstrip('/')}/{admin_upload_path.strip('/')}"
    response = httpx.get(
        url,
        headers={sync_header_name: secret},
        timeout=60.0,
    )
    if response.status_code >= 400:
        detail = response.text.strip() or response.reason_phrase
        raise RuntimeError(
            f"Failed to list curated images at {url}: HTTP {response.status_code} {detail}"
        )
    payload = response.json()
    items = payload.get("items") if isinstance(payload, dict) else None
    if not isinstance(items, list):
        raise RuntimeError(f"Invalid curated image list response from {url}")
    return [str(item) for item in items if str(item).strip()]


def delete_remote_managed_file(
    *,
    remote_filename: str,
    public_base_url: str,
    sync_secret: str,
    admin_upload_path: str,
    sync_header_name: str,
    sync_secret_env_var: str,
    dry_run: bool = False,
) -> None:
    """DELETE one remote curated file via the admin endpoint."""
    secret = sync_secret.strip()
    if not dry_run and not secret:
        raise RuntimeError(f"{sync_secret_env_var} must be set to prune remote curated images.")

    upload_root = admin_upload_path.rstrip("/")
    url = (
        f"{public_base_url.rstrip('/')}/{upload_root.lstrip('/')}/"
        f"{quote(remote_filename, safe='/')}"
    )
    if dry_run:
        return

    response = httpx.delete(
        url,
        headers={sync_header_name: secret},
        timeout=60.0,
    )
    # 404 = already gone; treat as success for prune idempotency.
    if response.status_code in (204, 404):
        return
    if response.status_code >= 400:
        detail = response.text.strip() or response.reason_phrase
        raise RuntimeError(
            f"Failed to delete {remote_filename} at {url}: "
            f"HTTP {response.status_code} {detail}"
        )


def prune_remote_managed_paths(
    *,
    keep_relative_paths: set[str],
    public_base_url: str,
    sync_secret: str,
    admin_upload_path: str,
    sync_header_name: str,
    sync_secret_env_var: str,
    dry_run: bool = False,
) -> dict[str, int]:
    """Delete remote managed files that are not in ``keep_relative_paths``.

    Comparison is case-insensitive so local files like ``tyrannosaurus.png`` still
    protect remote uploads stored under the canonical DB name ``Tyrannosaurus.png``.
    """
    remote = list_remote_managed_paths(
        public_base_url=public_base_url,
        sync_secret=sync_secret,
        admin_upload_path=admin_upload_path,
        sync_header_name=sync_header_name,
        sync_secret_env_var=sync_secret_env_var,
        dry_run=dry_run,
    )
    keep_lower = {path.lower() for path in keep_relative_paths}
    orphans = sorted(path for path in set(remote) if path.lower() not in keep_lower)
    deleted = 0
    for relative in orphans:
        logger.info(
            "%s %s",
            "Would prune" if dry_run else "Prune",
            relative,
        )
        delete_remote_managed_file(
            remote_filename=relative,
            public_base_url=public_base_url,
            sync_secret=sync_secret,
            admin_upload_path=admin_upload_path,
            sync_header_name=sync_header_name,
            sync_secret_env_var=sync_secret_env_var,
            dry_run=dry_run,
        )
        deleted += 1
    return {"remote": len(remote), "kept": len(keep_relative_paths), "pruned": deleted}


def upload_local_meta_files(
    *,
    root: Path,
    public_base_url: str,
    sync_secret: str,
    admin_upload_path: str,
    sync_header_name: str,
    sync_secret_env_var: str,
    upload_file,
    dry_run: bool = False,
) -> int:
    """Upload each version folder's meta.yaml. ``upload_file`` is the type sync uploader."""
    del admin_upload_path, sync_header_name, sync_secret_env_var
    uploaded = 0
    for version in load_image_versions(root):
        meta_path = version.path / META_FILENAME
        if not meta_path.is_file():
            continue
        relative = f"{version.name}/{META_FILENAME}"
        logger.info(
            "%s %s",
            "Would upload" if dry_run else "Upload",
            relative,
        )
        upload_file(
            local_path=meta_path,
            remote_filename=relative,
            public_base_url=public_base_url,
            sync_secret=sync_secret,
            dry_run=dry_run,
        )
        uploaded += 1
    return uploaded


def sync_meta_and_prune_remote(
    *,
    root: Path,
    public_base_url: str,
    sync_secret: str,
    admin_upload_path: str,
    sync_header_name: str,
    sync_secret_env_var: str,
    upload_file,
    dry_run: bool = False,
) -> dict[str, int]:
    """Upload local meta.yaml files, then prune remote files absent locally."""
    meta_uploaded = upload_local_meta_files(
        root=root,
        public_base_url=public_base_url,
        sync_secret=sync_secret,
        admin_upload_path=admin_upload_path,
        sync_header_name=sync_header_name,
        sync_secret_env_var=sync_secret_env_var,
        upload_file=upload_file,
        dry_run=dry_run,
    )
    keep = set(list_managed_relative_paths(root))
    prune_summary = prune_remote_managed_paths(
        keep_relative_paths=keep,
        public_base_url=public_base_url,
        sync_secret=sync_secret,
        admin_upload_path=admin_upload_path,
        sync_header_name=sync_header_name,
        sync_secret_env_var=sync_secret_env_var,
        dry_run=dry_run,
    )
    logger.info(
        "Meta/prune summary: meta_uploaded=%d remote=%d kept=%d pruned=%d",
        meta_uploaded,
        prune_summary["remote"],
        prune_summary["kept"],
        prune_summary["pruned"],
    )
    return {"meta_uploaded": meta_uploaded, **prune_summary}
