"""Parse and match dinosaur name filters for sync jobs."""

from __future__ import annotations

from sqlalchemy import func, or_
from sqlmodel import Session, select

from app.models.dinosaur_type import DinosaurType


def parse_dino_names(raw: list[str] | None) -> list[str] | None:
    """Flatten CLI `--dinos` values; each argument may be comma-separated."""
    if not raw:
        return None
    names: list[str] = []
    for part in raw:
        for name in part.split(","):
            stripped = name.strip()
            if stripped:
                names.append(stripped)
    return names or None


def dino_name_match_clause(dinos: list[str]):
    """SQLAlchemy filter matching name or wikipedia_title (case-insensitive)."""
    lowered = [name.lower() for name in dinos]
    return or_(
        func.lower(DinosaurType.name).in_(lowered),
        func.lower(DinosaurType.wikipedia_title).in_(lowered),
    )


def find_dinosaurs_by_names(session: Session, dinos: list[str]) -> list[DinosaurType]:
    stmt = select(DinosaurType).where(dino_name_match_clause(dinos))
    return list(session.exec(stmt).all())
