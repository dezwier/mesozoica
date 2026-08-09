"""Small public projection used by the knowledge acquisition jobs."""

from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import func
from sqlmodel import Session, col, select

from app.features.specimens.models.dinosaur_type import DinosaurType


@dataclass(frozen=True)
class DinosaurKnowledgeSubject:
    id: int
    name: str
    wikipedia_title: str


def list_dinosaur_knowledge_subjects(
    session: Session, *, names: list[str] | None = None
) -> list[DinosaurKnowledgeSubject]:
    statement = select(DinosaurType).order_by(col(DinosaurType.name))
    if names:
        normalized = [name.strip().casefold() for name in names if name.strip()]
        statement = statement.where(func.lower(DinosaurType.wikipedia_title).in_(normalized))
    rows = session.exec(statement).all()
    return [
        DinosaurKnowledgeSubject(
            id=int(row.id), name=row.name, wikipedia_title=row.wikipedia_title
        )
        for row in rows
        if row.id is not None
    ]
