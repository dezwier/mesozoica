"""Query helpers for dinosaur read APIs."""

from __future__ import annotations

from sqlmodel import Session, func, select

from app.core.exceptions import NotFoundError
from app.models.dinosaur import Dinosaur


def list_dinosaurs(
    session: Session,
    *,
    limit: int = 200,
    offset: int = 0,
) -> tuple[list[Dinosaur], int]:
    """Return paginated dinosaur rows ordered by name."""
    capped_limit = max(1, min(limit, 500))
    capped_offset = max(0, offset)

    total = session.exec(select(func.count()).select_from(Dinosaur)).one()
    rows = session.exec(
        select(Dinosaur)
        .order_by(Dinosaur.name)
        .offset(capped_offset)
        .limit(capped_limit)
    ).all()
    return list(rows), int(total)


def get_dinosaur_by_id(session: Session, dinosaur_id: int) -> Dinosaur:
    row = session.get(Dinosaur, dinosaur_id)
    if row is None:
        raise NotFoundError(f"Dinosaur {dinosaur_id} not found")
    return row
