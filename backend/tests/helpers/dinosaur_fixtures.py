"""Helpers to seed dinosaur_type + dinosaur_type_revision rows in tests."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from sqlmodel import Session

from app.models.dinosaur_type import DinosaurType
from app.models.dinosaur_type_revision import DinosaurTypeRevision
from app.services.wikipedia_service.content_hash import revision_content_hash


def seed_dinosaur_type(
    session: Session,
    *,
    name: str,
    wikipedia_page_id: int,
    wikipedia_title: str | None = None,
    birth: float | None = None,
    death: float | None = None,
    period: str | None = None,
    cladogram: dict[str, Any] | None = None,
    diet_type: str | None = None,
    short_description: str | None = None,
    long_description: str | None = None,
    article: str | None = None,
    article_date: datetime | None = None,
    length: str | None = None,
    mass: str | None = None,
    location: str | None = None,
    main_image_url: str | None = None,
    llm_enriched: bool = False,
    fossils_insert_time: datetime | None = None,
    content_hash: str | None = None,
    commit: bool = True,
) -> DinosaurType:
    """Insert a thin dinosaur_type plus one current revision with content fields."""
    title = wikipedia_title or name
    dino_type = DinosaurType(
        name=name,
        wikipedia_page_id=wikipedia_page_id,
        wikipedia_title=title,
        main_image_url=main_image_url,
        fossils_insert_time=fossils_insert_time,
    )
    session.add(dino_type)
    session.flush()

    clad = cladogram if cladogram is not None else {}
    hash_value = content_hash or revision_content_hash(
        article=article,
        long_description=long_description,
        birth=birth,
        death=death,
        period=period,
        diet_type=diet_type,
        cladogram=clad,
    )
    revision = DinosaurTypeRevision(
        dinosaur_type_id=int(dino_type.id),
        article_date=article_date or datetime(2026, 7, 8, tzinfo=timezone.utc),
        content_hash=hash_value,
        birth=birth,
        death=death,
        period=period,
        cladogram=clad,
        diet_type=diet_type,
        long_description=long_description,
        article=article,
        length=length,
        mass=mass,
        location=location,
        short_description=short_description,
        llm_enriched=llm_enriched,
    )
    session.add(revision)
    session.flush()
    dino_type.current_revision_id = int(revision.id)
    session.add(dino_type)
    if commit:
        session.commit()
        session.refresh(dino_type)
    return dino_type


def current_revision(
    session: Session, dino_type: DinosaurType
) -> DinosaurTypeRevision | None:
    if dino_type.current_revision_id is None:
        return None
    return session.get(DinosaurTypeRevision, dino_type.current_revision_id)
