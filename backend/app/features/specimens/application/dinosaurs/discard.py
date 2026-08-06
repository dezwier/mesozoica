"""Discard a dinosaur inventory occurrence for the acting user."""

from __future__ import annotations

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError
from app.models.dinosaur import Dinosaur
from app.models.user_dinosaur import UserDinosaur


def discard_dinosaur_for_user(
    session: Session,
    *,
    dinosaur_id: int,
    user_id: int,
) -> None:
    """Delete the caller's ``user_dinosaur`` rows for an occurrence.

    Idempotent when the caller has no links. The occurrence row is kept.
    """
    dinosaur = session.get(Dinosaur, dinosaur_id)
    if dinosaur is None:
        raise NotFoundError(f"Dinosaur {dinosaur_id} not found")

    rows = session.exec(
        select(UserDinosaur).where(
            col(UserDinosaur.user_id) == user_id,
            col(UserDinosaur.dinosaur_id) == dinosaur_id,
        )
    ).all()
    for row in rows:
        session.delete(row)
    if rows:
        session.commit()
