"""Tests for Wikipedia sync orchestration."""

from __future__ import annotations

from datetime import datetime, timezone
from unittest.mock import MagicMock

import pytest
from sqlmodel import Session, select

from app.models.dinosaur_type import DinosaurType
from app.models.dinosaur_type_revision import DinosaurTypeRevision
from app.services.wikipedia_service.category import CategoryMember
from app.services.wikipedia_service.metadata import PageMetadata
from app.services.wikipedia_service.parser import ParsedArticle
from app.services.wikipedia_service.sync import (
    SyncCounters,
    SyncSummary,
    sync_dinosaurs,
    sync_exit_code,
)
from tests.helpers.dinosaur_fixtures import current_revision, seed_dinosaur_type


@pytest.fixture
def fixture_html():
    from pathlib import Path

    return (
        Path(__file__).parent / "fixtures" / "wikipedia" / "tyrannosaurus_infobox.html"
    ).read_text(encoding="utf-8")


def _metadata(
    *,
    page_id: int = 30467,
    title: str = "Tyrannosaurus",
    ts: datetime | None = None,
    image_url: str | None = None,
):
    return PageMetadata(
        page_id=page_id,
        title=title,
        description="Genus of Late Cretaceous theropod",
        is_disambiguation=False,
        article_date=ts or datetime(2026, 7, 8, tzinfo=timezone.utc),
        image_url=image_url,
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


def _sync_batches(
    *members: CategoryMember,
    category: str = "Category:Dinosaur_genera",
) -> list[tuple[str, list[CategoryMember]]]:
    return [(category, list(members))]


def test_sync_inserts_new_record(session: Session, fixture_html, monkeypatch):
    client = MagicMock()
    client.page_with_html.return_value = {"html": fixture_html}

    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.list_dinosaur_sync_batches",
        lambda *_args, **_kwargs: _sync_batches(
            CategoryMember(page_id=30467, title="Tyrannosaurus"),
        ),
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

    row = session.exec(
        select(DinosaurType).where(DinosaurType.wikipedia_page_id == 30467)
    ).first()
    assert row is not None
    revision = current_revision(session, row)
    assert revision is not None
    assert revision.short_description is None
    assert revision.llm_enriched is False
    assert revision.article is not None
    assert summary.counters.types_added == 1


def test_sync_inserts_main_image_url_from_metadata(session: Session, fixture_html, monkeypatch):
    client = MagicMock()
    client.page_with_html.return_value = {"html": fixture_html}

    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.list_dinosaur_sync_batches",
        lambda *_args, **_kwargs: _sync_batches(
            CategoryMember(page_id=30467, title="Tyrannosaurus"),
        ),
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.fetch_page_metadata",
        lambda *_args, **_kwargs: _metadata(
            image_url="https://upload.wikimedia.org/wikipedia/commons/t-rex.jpg",
        ),
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.parse_article_html",
        lambda html: _parsed(html),
    )

    sync_dinosaurs(session, client=client, dry_run=False)
    session.commit()

    row = session.exec(
        select(DinosaurType).where(DinosaurType.wikipedia_page_id == 30467)
    ).first()
    assert row is not None
    assert row.main_image_url == "https://upload.wikimedia.org/wikipedia/commons/t-rex.jpg"


def test_sync_stale_update_fills_null_main_image_url(session: Session, fixture_html, monkeypatch):
    existing = seed_dinosaur_type(
        session,
        name="Tyrannosaurus",
        wikipedia_page_id=30467,
        cladogram={"kingdom": "Animalia"},
        article="<p>old</p>",
        article_date=datetime(2025, 1, 1, tzinfo=timezone.utc),
        main_image_url=None,
    )

    client = MagicMock()
    client.page_with_html.return_value = {"html": fixture_html}

    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.list_dinosaur_sync_batches",
        lambda *_args, **_kwargs: _sync_batches(
            CategoryMember(page_id=30467, title="Tyrannosaurus"),
        ),
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.fetch_page_metadata",
        lambda *_args, **_kwargs: _metadata(
            ts=datetime(2026, 7, 8, tzinfo=timezone.utc),
            image_url="https://upload.wikimedia.org/wikipedia/commons/t-rex.jpg",
        ),
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.parse_article_html",
        lambda html: _parsed(html),
    )

    sync_dinosaurs(session, client=client)
    session.refresh(existing)

    assert existing.main_image_url == "https://upload.wikimedia.org/wikipedia/commons/t-rex.jpg"


def test_sync_skips_up_to_date(session: Session, monkeypatch):
    existing = seed_dinosaur_type(
        session,
        name="Tyrannosaurus",
        wikipedia_page_id=30467,
        cladogram={"kingdom": "Animalia"},
        article="<p>Cached article body</p>",
        article_date=datetime(2026, 7, 8, tzinfo=timezone.utc),
        main_image_url="https://example.com/image.jpg",
    )
    existing.insert_date = datetime(2025, 1, 1, tzinfo=timezone.utc)
    session.add(existing)
    session.commit()

    client = MagicMock()
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.list_dinosaur_sync_batches",
        lambda *_args, **_kwargs: _sync_batches(
            CategoryMember(page_id=30467, title="Tyrannosaurus"),
        ),
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
    existing = seed_dinosaur_type(
        session,
        name="Tyrannosaurus",
        wikipedia_page_id=30467,
        cladogram={"kingdom": "Animalia"},
        article="<p>old article</p>",
        article_date=datetime(2025, 1, 1, tzinfo=timezone.utc),
        main_image_url="https://example.com/kept.jpg",
    )
    existing.insert_date = insert_date
    session.add(existing)
    session.commit()
    old_revision_id = existing.current_revision_id

    client = MagicMock()
    client.page_with_html.return_value = {"html": fixture_html}

    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.list_dinosaur_sync_batches",
        lambda *_args, **_kwargs: _sync_batches(
            CategoryMember(page_id=30467, title="Tyrannosaurus"),
        ),
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
    revision = current_revision(session, existing)

    assert summary.counters.revisions_appended == 1
    assert existing.insert_date.replace(tzinfo=None) == insert_date.replace(tzinfo=None)
    assert existing.main_image_url == "https://example.com/kept.jpg"
    assert revision is not None
    assert revision.period == "Late Cretaceous"
    assert revision.llm_enriched is False
    assert existing.current_revision_id != old_revision_id


def test_sync_refreshes_incomplete_stub(session: Session, fixture_html, monkeypatch):
    existing = DinosaurType(
        name="Brachiosaurus",
        wikipedia_page_id=12345,
        wikipedia_title="Brachiosaurus",
        insert_date=datetime(2025, 1, 1, tzinfo=timezone.utc),
    )
    session.add(existing)
    session.commit()

    client = MagicMock()
    client.page_with_html.return_value = {"html": fixture_html}

    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.list_dinosaur_sync_batches",
        lambda *_args, **_kwargs: _sync_batches(
            CategoryMember(page_id=12345, title="Brachiosaurus"),
        ),
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.fetch_page_metadata",
        lambda *_args, **_kwargs: _metadata(
            page_id=12345,
            title="Brachiosaurus",
            ts=datetime(2026, 7, 8, tzinfo=timezone.utc),
        ),
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.parse_article_html",
        lambda html: _parsed(html),
    )

    summary = sync_dinosaurs(session, client=client)
    session.refresh(existing)
    revision = current_revision(session, existing)

    assert summary.counters.revisions_appended == 1
    assert revision is not None
    assert revision.period == "Late Cretaceous"
    assert revision.cladogram["genus"] == "Tyrannosaurus"
    assert revision.article is not None
    client.page_with_html.assert_called_once()


def test_sync_updates_stub_matched_by_title_when_page_id_differs(
    session: Session, fixture_html, monkeypatch
):
    existing = DinosaurType(
        name="Allosaurus",
        wikipedia_page_id=99999,
        wikipedia_title="Allosaurus",
        insert_date=datetime(2025, 1, 1, tzinfo=timezone.utc),
    )
    session.add(existing)
    session.commit()

    client = MagicMock()
    client.page_with_html.return_value = {"html": fixture_html}

    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.list_dinosaur_sync_batches",
        lambda *_args, **_kwargs: _sync_batches(
            CategoryMember(page_id=1347, title="Allosaurus"),
        ),
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.fetch_page_metadata",
        lambda *_args, **_kwargs: _metadata(
            page_id=1347,
            title="Allosaurus",
            ts=datetime(2026, 7, 8, tzinfo=timezone.utc),
        ),
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.parse_article_html",
        lambda html: _parsed(html),
    )

    summary = sync_dinosaurs(session, client=client)
    session.refresh(existing)
    revision = current_revision(session, existing)

    assert summary.counters.revisions_appended == 1
    assert summary.counters.types_added == 0
    assert existing.wikipedia_page_id == 1347
    assert revision is not None
    assert revision.period == "Late Cretaceous"
    assert revision.article is not None
    assert len(session.exec(select(DinosaurType)).all()) == 1


def test_sync_stale_update_keeps_old_revision_llm(session: Session, fixture_html, monkeypatch):
    existing = seed_dinosaur_type(
        session,
        name="Tyrannosaurus",
        wikipedia_page_id=30467,
        cladogram={"kingdom": "Animalia"},
        article="<p>old article</p>",
        article_date=datetime(2025, 1, 1, tzinfo=timezone.utc),
        llm_enriched=True,
        short_description="Previously enriched catchy description for museum visitors.",
        length="12 m",
    )
    old_revision_id = int(existing.current_revision_id)

    client = MagicMock()
    client.page_with_html.return_value = {"html": fixture_html}

    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.list_dinosaur_sync_batches",
        lambda *_args, **_kwargs: _sync_batches(
            CategoryMember(page_id=30467, title="Tyrannosaurus"),
        ),
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.fetch_page_metadata",
        lambda *_args, **_kwargs: _metadata(ts=datetime(2026, 7, 8, tzinfo=timezone.utc)),
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.parse_article_html",
        lambda html: _parsed(html),
    )

    sync_dinosaurs(session, client=client)
    session.refresh(existing)
    old_revision = session.get(DinosaurTypeRevision, old_revision_id)
    new_revision = current_revision(session, existing)

    assert old_revision is not None
    assert old_revision.llm_enriched is True
    assert old_revision.length == "12 m"
    assert new_revision is not None
    assert new_revision.id != old_revision_id
    assert new_revision.llm_enriched is False
    assert new_revision.length is None


def test_sync_keyboard_interrupt_preserves_committed_records(
    session: Session, fixture_html, monkeypatch
):
    client = MagicMock()
    client.page_with_html.return_value = {"html": fixture_html}

    def metadata_side_effect(_wiki, title: str):
        if title == "Velociraptor":
            raise KeyboardInterrupt()
        return _metadata(title=title, page_id=30467 if title == "Tyrannosaurus" else 99999)

    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.list_dinosaur_sync_batches",
        lambda *_args, **_kwargs: _sync_batches(
            CategoryMember(page_id=30467, title="Tyrannosaurus"),
            CategoryMember(page_id=99999, title="Velociraptor"),
        ),
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.fetch_page_metadata",
        metadata_side_effect,
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.parse_article_html",
        lambda html: _parsed(html),
    )

    with pytest.raises(KeyboardInterrupt):
        sync_dinosaurs(session, client=client, dry_run=False)

    saved = session.exec(
        select(DinosaurType).where(DinosaurType.wikipedia_page_id == 30467)
    ).first()
    missing = session.exec(
        select(DinosaurType).where(DinosaurType.wikipedia_page_id == 99999)
    ).first()

    assert saved is not None
    revision = current_revision(session, saved)
    assert revision is not None
    assert revision.period == "Late Cretaceous"
    assert missing is None


def test_sync_overwrite_without_candidates_preserves_revision_llm(
    session: Session, monkeypatch
):
    """Overwrite no longer bulk-clears LLM; untouched revisions keep enrichment."""
    synced = seed_dinosaur_type(
        session,
        name="Tyrannosaurus",
        wikipedia_page_id=30467,
        cladogram={"kingdom": "Animalia"},
        article="<p>T</p>",
        length="12 m",
        mass="7 t",
        llm_enriched=True,
    )
    unsynced = seed_dinosaur_type(
        session,
        name="Velociraptor",
        wikipedia_page_id=99999,
        cladogram={"kingdom": "Animalia"},
        article="<p>V</p>",
        length="2 m",
        mass="15 kg",
        llm_enriched=True,
    )

    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.list_dinosaur_sync_batches",
        lambda *_args, **_kwargs: [],
    )

    sync_dinosaurs(session, client=MagicMock(), overwrite=True)
    synced_rev = current_revision(session, synced)
    unsynced_rev = current_revision(session, unsynced)

    assert synced_rev is not None
    assert synced_rev.length == "12 m"
    assert synced_rev.llm_enriched is True
    assert unsynced_rev is not None
    assert unsynced_rev.length == "2 m"
    assert unsynced_rev.llm_enriched is True


def test_sync_overwrite_appends_new_revision_when_content_changes(
    session: Session, fixture_html, monkeypatch
):
    existing = seed_dinosaur_type(
        session,
        name="Tyrannosaurus",
        wikipedia_page_id=30467,
        cladogram={"kingdom": "Animalia", "genus": "Tyrannosaurus et al."},
        article="<p>old</p>",
        article_date=datetime(2026, 7, 8, tzinfo=timezone.utc),
        length="12 m",
        mass="7 t",
        location="North America",
        short_description="Old LLM blurb.",
        llm_enriched=True,
    )
    old_revision_id = int(existing.current_revision_id)

    client = MagicMock()
    client.page_with_html.return_value = {"html": fixture_html}

    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.list_dinosaur_sync_batches",
        lambda *_args, **_kwargs: _sync_batches(
            CategoryMember(page_id=30467, title="Tyrannosaurus"),
        ),
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.fetch_page_metadata",
        lambda *_args, **_kwargs: _metadata(ts=datetime(2026, 7, 8, tzinfo=timezone.utc)),
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.parse_article_html",
        lambda html: _parsed(html),
    )

    sync_dinosaurs(session, client=client, overwrite=True)
    session.refresh(existing)
    old_revision = session.get(DinosaurTypeRevision, old_revision_id)
    new_revision = current_revision(session, existing)

    assert old_revision is not None
    assert old_revision.llm_enriched is True
    assert new_revision is not None
    assert new_revision.id != old_revision_id
    assert new_revision.cladogram["genus"] == "Tyrannosaurus"
    assert new_revision.llm_enriched is False
    assert new_revision.length is None


def test_sync_overwrite_refetches_up_to_date(session: Session, fixture_html, monkeypatch):
    existing = seed_dinosaur_type(
        session,
        name="Tyrannosaurus",
        wikipedia_page_id=30467,
        cladogram={"kingdom": "Animalia"},
        article="<p>Cached</p>",
        article_date=datetime(2026, 7, 8, tzinfo=timezone.utc),
        main_image_url="https://example.com/image.jpg",
    )

    client = MagicMock()
    client.page_with_html.return_value = {"html": fixture_html}

    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.list_dinosaur_sync_batches",
        lambda *_args, **_kwargs: _sync_batches(
            CategoryMember(page_id=30467, title="Tyrannosaurus"),
        ),
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.fetch_page_metadata",
        lambda *_args, **_kwargs: _metadata(ts=datetime(2026, 7, 8, tzinfo=timezone.utc)),
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.parse_article_html",
        lambda html: _parsed(html),
    )

    summary = sync_dinosaurs(session, client=client, overwrite=True)
    session.refresh(existing)
    revision = current_revision(session, existing)

    assert summary.counters.revisions_appended == 1
    assert summary.counters.skipped == 0
    assert revision is not None
    assert revision.period == "Late Cretaceous"
    client.page_with_html.assert_called_once()


def test_sync_same_hash_skips_new_revision(session: Session, fixture_html, monkeypatch):
    parsed = _parsed(fixture_html)
    existing = seed_dinosaur_type(
        session,
        name="Tyrannosaurus",
        wikipedia_page_id=30467,
        birth=parsed.birth,
        death=parsed.death,
        period=parsed.period,
        cladogram=parsed.cladogram,
        diet_type=parsed.diet_type,
        long_description=parsed.long_description,
        article=parsed.article_html,
        article_date=datetime(2025, 1, 1, tzinfo=timezone.utc),
        llm_enriched=True,
        length="12 m",
    )
    old_revision_id = int(existing.current_revision_id)

    client = MagicMock()
    client.page_with_html.return_value = {"html": fixture_html}

    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.list_dinosaur_sync_batches",
        lambda *_args, **_kwargs: _sync_batches(
            CategoryMember(page_id=30467, title="Tyrannosaurus"),
        ),
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.fetch_page_metadata",
        lambda *_args, **_kwargs: _metadata(ts=datetime(2026, 7, 8, tzinfo=timezone.utc)),
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.parse_article_html",
        lambda html: _parsed(html),
    )

    summary = sync_dinosaurs(session, client=client, overwrite=True)
    session.refresh(existing)
    revision = current_revision(session, existing)

    assert summary.counters.skipped == 1
    assert existing.current_revision_id == old_revision_id
    assert revision is not None
    assert revision.llm_enriched is True
    assert revision.article_date is not None
    assert revision.article_date.replace(tzinfo=timezone.utc) == datetime(
        2026, 7, 8, tzinfo=timezone.utc
    )


def test_sync_minor_change_skips_new_revision(session: Session, fixture_html, monkeypatch):
    """Tiny article edit (hash differs) must not append a revision."""
    parsed = _parsed(fixture_html)
    existing = seed_dinosaur_type(
        session,
        name="Tyrannosaurus",
        wikipedia_page_id=30467,
        birth=parsed.birth,
        death=parsed.death,
        period=parsed.period,
        cladogram=parsed.cladogram,
        diet_type=parsed.diet_type,
        long_description=parsed.long_description,
        article=parsed.article_html,
        article_date=datetime(2025, 1, 1, tzinfo=timezone.utc),
        llm_enriched=True,
        length="12 m",
    )
    old_revision_id = int(existing.current_revision_id)

    # One-word typo-style change: keeps structural fields + almost all tokens.
    minor_html = parsed.article_html.replace("</p>", " x</p>", 1)
    assert minor_html != parsed.article_html

    client = MagicMock()
    client.page_with_html.return_value = {"html": fixture_html}

    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.list_dinosaur_sync_batches",
        lambda *_args, **_kwargs: _sync_batches(
            CategoryMember(page_id=30467, title="Tyrannosaurus"),
        ),
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.fetch_page_metadata",
        lambda *_args, **_kwargs: _metadata(ts=datetime(2026, 7, 8, tzinfo=timezone.utc)),
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.parse_article_html",
        lambda _html: ParsedArticle(
            birth=parsed.birth,
            death=parsed.death,
            period=parsed.period,
            cladogram=parsed.cladogram,
            diet_type=parsed.diet_type,
            long_description=parsed.long_description,
            article_html=minor_html,
        ),
    )

    summary = sync_dinosaurs(session, client=client, overwrite=True)
    session.refresh(existing)
    revision = current_revision(session, existing)

    assert summary.counters.revisions_appended == 0
    assert summary.counters.skipped == 1
    assert existing.current_revision_id == old_revision_id
    assert revision is not None
    assert revision.article == parsed.article_html
    assert revision.llm_enriched is True


def test_sync_exit_code_threshold():
    summary = SyncSummary(
        category="Category:Dinosaur_genera",
        total_candidates=10,
        counters=SyncCounters(failed=2, types_added=8),
    )
    assert sync_exit_code(summary) == 1

    summary_ok = SyncSummary(
        category="Category:Dinosaur_genera",
        total_candidates=10,
        counters=SyncCounters(failed=0, types_added=10),
    )
    assert sync_exit_code(summary_ok) == 0


def test_sync_dinos_skips_category_listing(session: Session, fixture_html, monkeypatch):
    client = MagicMock()
    client.page_with_html.return_value = {"html": fixture_html}

    list_batches_called = False

    def fake_list_batches(*_args, **_kwargs):
        nonlocal list_batches_called
        list_batches_called = True
        return []

    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.list_dinosaur_sync_batches",
        fake_list_batches,
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.fetch_page_metadata",
        lambda *_args, **_kwargs: _metadata(title="Giganotosaurus", page_id=555),
    )
    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.parse_article_html",
        lambda html: _parsed(html),
    )

    summary = sync_dinosaurs(
        session,
        client=client,
        dry_run=False,
        dinos=["Giganotosaurus"],
    )
    session.commit()

    assert list_batches_called is False
    assert summary.counters.types_added == 1
    row = session.exec(
        select(DinosaurType).where(DinosaurType.wikipedia_page_id == 555)
    ).first()
    assert row is not None
    assert row.name == "Giganotosaurus"
