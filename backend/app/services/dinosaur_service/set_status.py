"""Set dinosaur catalog status via user_dinosaur role (or clear for hidden)."""

from __future__ import annotations

from datetime import datetime, timezone

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError, ValidationError
from app.models.dinosaur import Dinosaur
from app.models.dinosaur_type import DinosaurType
from app.models.user_dinosaur import (
    DINOSAUR_STATUS_HIDDEN,
    DINOSAUR_STATUSES,
    ROLE_TO_STATUS,
    UserDinosaur,
    role_to_status,
)
from app.services.curated_image_service.versions import ORIGINAL_VERSION
from app.services.dinosaur_service.list import DinosaurListRow, dinosaur_to_summary

_STATUS_TO_ROLE: dict[str, str] = {
    status: role for role, status in ROLE_TO_STATUS.items()
}


def _viewer_status_for_type(
    session: Session,
    *,
    dinosaur_type_id: int,
    user_id: int,
) -> str:
    link = session.exec(
        select(UserDinosaur)
        .join(Dinosaur, col(Dinosaur.id) == col(UserDinosaur.dinosaur_id))
        .where(
            col(UserDinosaur.user_id) == user_id,
            col(Dinosaur.dinosaur_type_id) == dinosaur_type_id,
        )
        .order_by(col(UserDinosaur.timestamp).desc())
    ).first()
    return role_to_status(link.role if link is not None else None)


def _find_user_occurrence_for_type(
    session: Session,
    *,
    dinosaur_type_id: int,
    user_id: int,
) -> Dinosaur | None:
    return session.exec(
        select(Dinosaur)
        .join(UserDinosaur, col(UserDinosaur.dinosaur_id) == col(Dinosaur.id))
        .where(
            col(UserDinosaur.user_id) == user_id,
            col(Dinosaur.dinosaur_type_id) == dinosaur_type_id,
        )
        .order_by(col(Dinosaur.created_at).desc())
    ).first()


def set_dinosaur_status(
    session: Session,
    *,
    dinosaur_type_id: int,
    user_id: int,
    status: str,
):
    """Set catalog dinosaur status for the acting user.

    ``hidden`` clears that user's ``user_dinosaur`` rows for occurrences of
    this type and deletes orphan ``dinosaur`` rows.
    Other statuses find-or-create one occurrence and upsert the matching role.
    """
    normalized = (status or "").strip().lower()
    if normalized not in DINOSAUR_STATUSES:
        raise ValidationError(
            f"status must be one of: {', '.join(DINOSAUR_STATUSES)}"
        )

    dino_type = session.get(DinosaurType, dinosaur_type_id)
    if dino_type is None:
        raise NotFoundError(f"DinosaurType {dinosaur_type_id} not found")

    if normalized == DINOSAUR_STATUS_HIDDEN:
        occurrence_ids = list(
            session.exec(
                select(Dinosaur.id).where(
                    col(Dinosaur.dinosaur_type_id) == dinosaur_type_id
                )
            ).all()
        )
        if occurrence_ids:
            links = session.exec(
                select(UserDinosaur).where(
                    col(UserDinosaur.user_id) == user_id,
                    col(UserDinosaur.dinosaur_id).in_(occurrence_ids),
                )
            ).all()
            affected_ids = {int(link.dinosaur_id) for link in links}
            for link in links:
                session.delete(link)
            session.flush()
            for occ_id in affected_ids:
                remaining = session.exec(
                    select(UserDinosaur).where(
                        col(UserDinosaur.dinosaur_id) == occ_id
                    )
                ).first()
                if remaining is None:
                    occ = session.get(Dinosaur, occ_id)
                    if occ is not None:
                        session.delete(occ)
        session.commit()
    else:
        role = _STATUS_TO_ROLE[normalized]
        now = datetime.now(timezone.utc)
        occurrence = _find_user_occurrence_for_type(
            session,
            dinosaur_type_id=dinosaur_type_id,
            user_id=user_id,
        )
        if occurrence is None:
            occurrence = Dinosaur(
                dinosaur_type_id=dinosaur_type_id,
                version=ORIGINAL_VERSION,
                created_at=now,
            )
            session.add(occurrence)
            session.flush()

        existing = session.exec(
            select(UserDinosaur).where(
                col(UserDinosaur.user_id) == user_id,
                col(UserDinosaur.dinosaur_id) == occurrence.id,
                col(UserDinosaur.role) == role,
            )
        ).first()
        if existing is None:
            session.add(
                UserDinosaur(
                    user_id=user_id,
                    dinosaur_id=int(occurrence.id),
                    role=role,
                    timestamp=now,
                )
            )
        else:
            existing.timestamp = now
            session.add(existing)
        session.commit()

    return dinosaur_to_summary(
        DinosaurListRow(dinosaur_type=dino_type, image_version=ORIGINAL_VERSION),
        viewer_status=_viewer_status_for_type(
            session, dinosaur_type_id=dinosaur_type_id, user_id=user_id
        ),
    )
