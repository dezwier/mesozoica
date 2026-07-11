"""Query helpers for dinosaur read APIs."""

from __future__ import annotations

import hashlib
from typing import Literal

from sqlalchemy import func
from sqlmodel import Session, func as sqlmodel_func, select

from app.core.exceptions import NotFoundError, ValidationError
from app.models.dinosaur import Dinosaur

SortOption = Literal["name", "random"]
_MAX_SEED_LEN = 64


def list_dinosaurs(
    session: Session,
    *,
    limit: int = 200,
    offset: int = 0,
    sort: SortOption = "name",
    seed: str | None = None,
) -> tuple[list[Dinosaur], int]:
    """Return paginated dinosaur rows ordered by name or seed-stable random."""
    capped_limit = max(1, min(limit, 500))
    capped_offset = max(0, offset)

    total = session.exec(select(sqlmodel_func.count()).select_from(Dinosaur)).one()

    if sort == "random":
        normalized_seed = (seed or "").strip()
        if not normalized_seed:
            raise ValidationError("seed is required when sort=random")
        normalized_seed = normalized_seed[:_MAX_SEED_LEN]
        rows = _list_dinosaurs_random(
            session,
            seed=normalized_seed,
            offset=capped_offset,
            limit=capped_limit,
        )
        return rows, int(total)

    rows = session.exec(
        select(Dinosaur)
        .order_by(Dinosaur.name)
        .offset(capped_offset)
        .limit(capped_limit)
    ).all()
    return list(rows), int(total)


def _list_dinosaurs_random(
    session: Session,
    *,
    seed: str,
    offset: int,
    limit: int,
) -> list[Dinosaur]:
    dialect_name = session.get_bind().dialect.name
    if dialect_name == "postgresql":
        order = func.md5(func.concat(Dinosaur.name, seed))
        rows = session.exec(
            select(Dinosaur).order_by(order).offset(offset).limit(limit)
        ).all()
        return list(rows)

    all_rows = session.exec(select(Dinosaur)).all()
    all_rows.sort(
        key=lambda row: hashlib.md5(f"{row.name}{seed}".encode()).hexdigest()
    )
    return all_rows[offset : offset + limit]


def get_dinosaur_by_id(session: Session, dinosaur_id: int) -> Dinosaur:
    row = session.get(Dinosaur, dinosaur_id)
    if row is None:
        raise NotFoundError(f"Dinosaur {dinosaur_id} not found")
    return row
