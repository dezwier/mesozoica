"""Tests for Wikipedia revision → RAG document conversion."""

from datetime import datetime, timezone

import pytest
from sqlmodel import Session

from app.features.ingestion.application.dinosaur_knowledge.wikipedia_documents import (
    wikipedia_documents_from_article,
)
from app.features.specimens.models.dinosaur_type import DinosaurType
from app.features.specimens.models.dinosaur_type_revision import DinosaurTypeRevision
from app.features.specimens.public import get_latest_dinosaur_wikipedia_article
from mesozoica_ai.common.errors import SourceFetchError


def test_wikipedia_documents_from_article_splits_sections_and_skips_references():
    html = """
    <p>Lead text about the animal.</p>
    <h2><span class="mw-headline" id="Description">Description</span></h2>
    <p>Body text.</p>
    <h3><span class="mw-headline" id="Skull">Skull</span></h3>
    <p>Skull detail.</p>
    <h2><span class="mw-headline" id="References">References</span></h2>
    <p>Ignore me.</p>
    """
    published = datetime(2026, 1, 2, tzinfo=timezone.utc)
    documents = wikipedia_documents_from_article(
        html,
        title="Example animal",
        page_id=42,
        source_version="7",
        published_at=published,
        metadata={"namespace": "test", "subject_id": "dinosaur:7"},
    )

    assert [document.metadata.section for document in documents] == [
        "Introduction",
        "Description",
        "Skull",
    ]
    assert documents[0].text == "Lead text about the animal."
    assert documents[0].metadata.source_version == "7"
    assert documents[0].metadata.namespace == "test"
    assert documents[2].id == "wikipedia:42:section:2:skull"
    assert documents[2].metadata.section_path == ["Description", "Skull"]


def test_wikipedia_documents_from_article_requires_usable_text():
    with pytest.raises(SourceFetchError, match="no usable text"):
        wikipedia_documents_from_article(
            "<table><tr><td>only chrome</td></tr></table>",
            title="Empty",
            page_id=1,
        )


def test_get_latest_dinosaur_wikipedia_article_prefers_current_revision(session: Session):
    dino = DinosaurType(
        name="Example",
        wikipedia_page_id=99,
        wikipedia_title="Example",
    )
    session.add(dino)
    session.commit()
    session.refresh(dino)

    older = DinosaurTypeRevision(
        dinosaur_type_id=int(dino.id),
        content_hash="a" * 64,
        article="<p>Older article.</p>",
        article_date=datetime(2024, 1, 1, tzinfo=timezone.utc),
    )
    newer = DinosaurTypeRevision(
        dinosaur_type_id=int(dino.id),
        content_hash="b" * 64,
        article="<p>Current article.</p>",
        article_date=datetime(2025, 1, 1, tzinfo=timezone.utc),
        wikipedia_revision_id=123,
    )
    session.add(older)
    session.add(newer)
    session.commit()
    session.refresh(older)
    session.refresh(newer)

    dino.current_revision_id = int(older.id)
    session.add(dino)
    session.commit()

    article = get_latest_dinosaur_wikipedia_article(
        session, dinosaur_type_id=int(dino.id)
    )
    assert article is not None
    assert article.revision_db_id == int(older.id)
    assert "Older article" in article.article

    dino.current_revision_id = int(newer.id)
    session.add(dino)
    session.commit()

    article = get_latest_dinosaur_wikipedia_article(
        session, dinosaur_type_id=int(dino.id)
    )
    assert article is not None
    assert article.revision_db_id == int(newer.id)
    assert article.wikipedia_revision_id == 123
    assert "Current article" in article.article


def test_get_latest_dinosaur_wikipedia_article_falls_back_without_current(
    session: Session,
):
    dino = DinosaurType(
        name="Fallback",
        wikipedia_page_id=100,
        wikipedia_title="Fallback",
    )
    session.add(dino)
    session.commit()
    session.refresh(dino)

    session.add(
        DinosaurTypeRevision(
            dinosaur_type_id=int(dino.id),
            content_hash="c" * 64,
            article="<p>Newest fallback.</p>",
            article_date=datetime(2026, 2, 1, tzinfo=timezone.utc),
        )
    )
    session.add(
        DinosaurTypeRevision(
            dinosaur_type_id=int(dino.id),
            content_hash="d" * 64,
            article="<p>Older fallback.</p>",
            article_date=datetime(2025, 2, 1, tzinfo=timezone.utc),
        )
    )
    session.commit()

    article = get_latest_dinosaur_wikipedia_article(
        session, dinosaur_type_id=int(dino.id)
    )
    assert article is not None
    assert "Newest fallback" in article.article
