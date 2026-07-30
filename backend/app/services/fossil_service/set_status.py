"""Set field fossil status via user_fossil role (or clear for hidden)."""

from __future__ import annotations

from datetime import datetime, timezone

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError, ValidationError
from app.models.data_source import DATA_SOURCE_FIELD
from app.models.fossil import Fossil
from app.models.user_fossil import (
    FOSSIL_STATUS_HIDDEN,
    FOSSIL_STATUSES,
    ROLE_TO_STATUS,
    UserFossil,
)
from app.services.fossil_service.list import fossil_row_to_summary, get_fossil_by_id
from app.services.site_service.site_type_fallback import load_site_types_by_period

_STATUS_TO_ROLE: dict[str, str] = {
    status: role for role, status in ROLE_TO_STATUS.items()
}


def set_fossil_status(
    session: Session,
    *,
    fossil_id: int,
    user_id: int,
    status: str,
):
    """Set the fossil's latest status for the acting user.

    ``hidden`` clears that user's ``user_fossil`` rows for the fossil.
    Other statuses upsert the matching role with a fresh timestamp.
    Field fossils only.
    """
    normalized = (status or "").strip().lower()
    if normalized not in FOSSIL_STATUSES:
        raise ValidationError(
            f"status must be one of: {', '.join(FOSSIL_STATUSES)}"
        )

    fossil = session.get(Fossil, fossil_id)
    if fossil is None or fossil.data_source != DATA_SOURCE_FIELD:
        raise NotFoundError(f"Field fossil {fossil_id} not found")

    if normalized == FOSSIL_STATUS_HIDDEN:
        rows = session.exec(
            select(UserFossil).where(
                col(UserFossil.user_id) == user_id,
                col(UserFossil.fossil_id) == fossil_id,
            )
        ).all()
        for row in rows:
            session.delete(row)
        session.commit()
    else:
        role = _STATUS_TO_ROLE[normalized]
        now = datetime.now(timezone.utc)
        existing = session.exec(
            select(UserFossil).where(
                col(UserFossil.user_id) == user_id,
                col(UserFossil.fossil_id) == fossil_id,
                col(UserFossil.role) == role,
            )
        ).first()
        if existing is None:
            session.add(
                UserFossil(
                    user_id=user_id,
                    fossil_id=fossil_id,
                    role=role,
                    timestamp=now,
                )
            )
        else:
            existing.timestamp = now
            session.add(existing)
        session.commit()

    row = get_fossil_by_id(session, fossil_id, data_source=DATA_SOURCE_FIELD)
    types_by_period = load_site_types_by_period(session)
    return fossil_row_to_summary(
        row,
        types_by_period=types_by_period,
        viewer_user_id=user_id,
        session=session,
    )
