"""Small public projection used by the knowledge acquisition jobs."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import func
from sqlmodel import Session, col, select

from app.features.specimens.models.dinosaur_type import DinosaurType
from app.features.specimens.models.dinosaur_type_revision import DinosaurTypeRevision


@dataclass(frozen=True)
class DinosaurKnowledgeSubject:
    id: int
    name: str
    wikipedia_title: str


@dataclass(frozen=True)
class DinosaurWikipediaArticle:
    """Latest Wikipedia article payload for RAG acquisition."""

    dinosaur_type_id: int
    wikipedia_title: str
    wikipedia_page_id: int
    revision_db_id: int
    wikipedia_revision_id: int | None
    article_date: datetime | None
    content_hash: str
    article: str


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


def get_latest_dinosaur_wikipedia_article(
    session: Session, *, dinosaur_type_id: int
) -> DinosaurWikipediaArticle | None:
    """Return the live/latest revision article for a dinosaur type, if any.

    Prefers ``DinosaurType.current_revision_id``. Falls back to the newest
    revision row that still has article text.
    """
    dino_type = session.get(DinosaurType, dinosaur_type_id)
    if dino_type is None or dino_type.id is None:
        return None

    revision: DinosaurTypeRevision | None = None
    if dino_type.current_revision_id is not None:
        current = session.get(DinosaurTypeRevision, dino_type.current_revision_id)
        if current is not None and (current.article or "").strip():
            revision = current

    if revision is None:
        revision = session.exec(
            select(DinosaurTypeRevision)
            .where(col(DinosaurTypeRevision.dinosaur_type_id) == int(dino_type.id))
            .where(col(DinosaurTypeRevision.article).is_not(None))
            .order_by(
                col(DinosaurTypeRevision.article_date).desc().nulls_last(),
                col(DinosaurTypeRevision.created_at).desc(),
                col(DinosaurTypeRevision.id).desc(),
            )
        ).first()
        if revision is None or not (revision.article or "").strip():
            return None

    assert revision.id is not None
    return DinosaurWikipediaArticle(
        dinosaur_type_id=int(dino_type.id),
        wikipedia_title=dino_type.wikipedia_title,
        wikipedia_page_id=int(dino_type.wikipedia_page_id),
        revision_db_id=int(revision.id),
        wikipedia_revision_id=revision.wikipedia_revision_id,
        article_date=revision.article_date,
        content_hash=revision.content_hash,
        article=str(revision.article),
    )
