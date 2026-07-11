"""Tests for Wikipedia sync orchestration."""

from __future__ import annotations

from datetime import datetime, timezone
from unittest.mock import MagicMock

import pytest
from sqlmodel import Session, select

from app.models.dinosaur import Dinosaur
from app.services.wikipedia_service.category import CategoryMember
from app.services.wikipedia_service.metadata import PageMetadata
from app.services.wikipedia_service.parser import ParsedArticle
from app.services.wikipedia_service.sync import sync_dinosaurs, sync_exit_code, SyncSummary, SyncCounters


@pytest.fixture
def fixture_html():
    from pathlib import Path

    return (Path(__file__).parent / "fixtures" / "wikipedia" / "tyrannosaurus_infobox.html").read_text(
        encoding="utf-8"
    )


def _metadata(*, page_id: int = 30467, title: str = "Tyrannosaurus", ts: datetime | None = None):
    return PageMetadata(
        page_id=page_id,
        title=title,
        description="Genus of Late Cretaceous theropod",
        is_disambiguation=False,
        article_date=ts or datetime(2026, 7, 8, tzinfo=timezone.utc),
    )


def _parsed(html: str):
    return ParsedArticle(
        birth=77.0,
        death=66.0,
        period="Late Cretaceous",
        cladogram={"kingdom": "Animalia", "genus": "Tyrannosaurus"},
        diet_type="Carnivore",
        long_description="Tyrannosaurus is a genus of large theropod dinosaur.",
        article_html=html,
    )


def test_sync_inserts_new_record(session: Session, fixture_html, monkeypatch):
    client = MagicMock()
    client.page_with_html.return_value = {"html": fixture_html}

    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.list_category_articles",
        lambda *_args, **_kwargs: [CategoryMember(page_id=30467, title="Tyrannosaurus")],
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.fetch_page_metadata",
        lambda *_args, **_kwargs: _metadata(),
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.parse_article_html",
        lambda html: _parsed(html),
    )

    summary = sync_dinosaurs(session, client=client, dry_run=False)
    session.commit()

    row = session.exec(select(Dinosaur).where(Dinosaur.wikipedia_page_id == 30467)).first()
    assert row is not None
    assert row.short_description == "Genus of Late Cretaceous theropod"
    assert summary.counters.fetched == 1


def test_sync_skips_up_to_date(session: Session, monkeypatch):
    existing = Dinosaur(
        name="Tyrannosaurus",
        wikipedia_page_id=30467,
        wikipedia_title="Tyrannosaurus",
        cladogram={"kingdom": "Animalia"},
        article_date=datetime(2026, 7, 8, tzinfo=timezone.utc),
        insert_date=datetime(2025, 1, 1, tzinfo=timezone.utc),
        main_image_url="https://example.com/image.jpg",
    )
    session.add(existing)
    session.commit()

    client = MagicMock()
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.list_category_articles",
        lambda *_args, **_kwargs: [CategoryMember(page_id=30467, title="Tyrannosaurus")],
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.fetch_page_metadata",
        lambda *_args, **_kwargs: _metadata(ts=datetime(2026, 7, 8, tzinfo=timezone.utc)),
    )

    summary = sync_dinosaurs(session, client=client)
    session.refresh(existing)

    assert summary.counters.skipped == 1
    assert existing.main_image_url == "https://example.com/image.jpg"
    assert existing.insert_date.replace(tzinfo=None) == datetime(2025, 1, 1)
    client.page_with_html.assert_not_called()


def test_sync_updates_stale_preserves_insert_date(session: Session, fixture_html, monkeypatch):
    insert_date = datetime(2024, 6, 1, tzinfo=timezone.utc)
    existing = Dinosaur(
        name="Tyrannosaurus",
        wikipedia_page_id=30467,
        wikipedia_title="Tyrannosaurus",
        cladogram={"kingdom": "Animalia"},
        article_date=datetime(2025, 1, 1, tzinfo=timezone.utc),
        insert_date=insert_date,
        main_image_url="https://example.com/kept.jpg",
    )
    session.add(existing)
    session.commit()

    client = MagicMock()
    client.page_with_html.return_value = {"html": fixture_html}

    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.list_category_articles",
        lambda *_args, **_kwargs: [CategoryMember(page_id=30467, title="Tyrannosaurus")],
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.fetch_page_metadata",
        lambda *_args, **_kwargs: _metadata(ts=datetime(2026, 7, 8, tzinfo=timezone.utc)),
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.parse_article_html",
        lambda html: _parsed(html),
    )

    summary = sync_dinosaurs(session, client=client)
    session.refresh(existing)

    assert summary.counters.updated == 1
    assert existing.insert_date.replace(tzinfo=None) == insert_date.replace(tzinfo=None)
    assert existing.main_image_url == "https://example.com/kept.jpg"
    assert existing.period == "Late Cretaceous"


def test_sync_exit_code_threshold():
    summary = SyncSummary(category="Category:Dinosaur_genera", total_candidates=10, counters=SyncCounters(failed=2, fetched=8))
    assert sync_exit_code(summary) == 1

    summary_ok = SyncSummary(category="Category:Dinosaur_genera", total_candidates=10, counters=SyncCounters(failed=0, fetched=10))
    assert sync_exit_code(summary_ok) == 0
