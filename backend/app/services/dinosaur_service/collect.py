"""Admin collect helper: spawn a dinosaur occurrence and record a collection role."""

from __future__ import annotations

from datetime import datetime, timezone

from sqlmodel import Session

from app.core.exceptions import NotFoundError, ValidationError
from app.models.dinosaur import Dinosaur
from app.models.dinosaur_type import DinosaurType
from app.models.user_dinosaur import (
    DINOSAUR_STATUS_HIDDEN,
    DINOSAUR_STATUSES,
    ROLE_TO_STATUS,
    UserDinosaur,
)
from app.services.curated_image_service.versions import (
    is_version_dir_name,
    latest_dinosaur_image_version,
    load_image_versions,
    normalize_version_name,
)
from app.services.dinosaur_service.list import DinosaurListRow, dinosaur_to_summary

_STATUS_TO_ROLE: dict[str, str] = {
    status: role for role, status in ROLE_TO_STATUS.items()
}

_COLLECT_STATUSES = tuple(
    status for status in DINOSAUR_STATUSES if status != DINOSAUR_STATUS_HIDDEN
)


def list_dinosaur_image_versions() -> list[dict[str, str | None]]:
    """Available curated dinosaur image version folders for admin collect UI."""
    from app.core.config import settings

    versions = load_image_versions(settings.resolved_dinosaur_images_dir)
    ordered = sorted(
        versions,
        key=lambda v: (
            v.run_date is not None,
            v.run_date or datetime.min.replace(tzinfo=timezone.utc),
            v.name.lower(),
        ),
        reverse=True,
    )
    return [
        {
            "name": v.name,
            "run_date": v.run_date.isoformat() if v.run_date else None,
        }
        for v in ordered
    ]


def _resolve_collect_version(version: str | None) -> str:
    from app.core.config import settings

    if version is None or not str(version).strip():
        return latest_dinosaur_image_version()
    name = normalize_version_name(version)
    root = settings.resolved_dinosaur_images_dir
    known = {v.name for v in load_image_versions(root)}
    if known and name not in known:
        raise ValidationError(
            f"Unknown dinosaur image version {name!r}; available: {sorted(known)}"
        )
    if not is_version_dir_name(name):
        raise ValidationError(f"Invalid dinosaur image version {name!r}")
    return name


def collect_dinosaur_for_user(
    session: Session,
    *,
    user_id: int,
    dinosaur_type_id: int,
    status: str,
    version: str | None = None,
):
    """Always create a new dinosaur occurrence + user_dinosaur role.

    Admins may collect duplicates of the same type. ``status`` must be a
    collection role status (modelled / reconstructed), not hidden.
    """
    normalized = (status or "").strip().lower()
    if normalized not in _COLLECT_STATUSES:
        raise ValidationError(
            f"status must be one of: {', '.join(_COLLECT_STATUSES)}"
        )

    dino_type = session.get(DinosaurType, dinosaur_type_id)
    if dino_type is None:
        raise NotFoundError(f"DinosaurType {dinosaur_type_id} not found")

    image_version = _resolve_collect_version(version)
    now = datetime.now(timezone.utc)
    occurrence = Dinosaur(
        dinosaur_type_id=dinosaur_type_id,
        version=image_version,
        created_at=now,
    )
    session.add(occurrence)
    session.flush()

    session.add(
        UserDinosaur(
            user_id=user_id,
            dinosaur_id=int(occurrence.id),
            role=_STATUS_TO_ROLE[normalized],
            timestamp=now,
        )
    )
    session.commit()
    session.refresh(occurrence)

    return dinosaur_to_summary(
        DinosaurListRow(
            dinosaur_type=dino_type,
            occurrence_id=int(occurrence.id),
            created_at=occurrence.created_at,
            image_version=image_version,
        ),
        viewer_status=normalized,
    )
