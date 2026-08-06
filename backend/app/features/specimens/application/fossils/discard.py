"""Discard a field fossil from the acting user's inventory."""

from __future__ import annotations

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError
from app.shared.data_sources import DATA_SOURCE_FIELD
from app.models.fossil import Fossil
from app.models.user_fossil import UserFossil


def discard_fossil_for_user(
    session: Session,
    *,
    fossil_id: int,
    user_id: int,
) -> None:
    """Delete the caller's ``user_fossil`` rows for a field fossil.

    Idempotent when the caller has no links. The fossil row is kept.
    """
    fossil = session.get(Fossil, fossil_id)
    if fossil is None or fossil.data_source != DATA_SOURCE_FIELD:
        raise NotFoundError(f"Field fossil {fossil_id} not found")

    rows = session.exec(
        select(UserFossil).where(
            col(UserFossil.user_id) == user_id,
            col(UserFossil.fossil_id) == fossil_id,
        )
    ).all()
    for row in rows:
        session.delete(row)
    if rows:
        session.commit()
