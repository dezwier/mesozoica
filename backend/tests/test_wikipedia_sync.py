"""Tests for Wikipedia sync orchestration."""

from __future__ import annotations

from datetime import datetime, timezone
from unittest.mock import MagicMock

import pytest
from sqlmodel import Session, select

from app.models.dinosaur_type import DinosaurType
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

    row = session.exec(select(DinosaurType).where(DinosaurType.wikipedia_page_id == 30467)).first()
    assert row is not None
    assert row.short_description is None
    assert row.llm_enriched is False
    assert summary.counters.fetched == 1


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

    row = session.exec(select(DinosaurType).where(DinosaurType.wikipedia_page_id == 30467)).first()
    assert row is not None
    assert row.main_image_url == "https://upload.wikimedia.org/wikipedia/commons/t-rex.jpg"


def test_sync_stale_update_fills_null_main_image_url(session: Session, fixture_html, monkeypatch):
    existing = DinosaurType(
        name="Tyrannosaurus",
        wikipedia_page_id=30467,
        wikipedia_title="Tyrannosaurus",
        cladogram={"kingdom": "Animalia"},
        article_date=datetime(2025, 1, 1, tzinfo=timezone.utc),
        insert_date=datetime(2024, 6, 1, tzinfo=timezone.utc),
        main_image_url=None,
    )
    session.add(existing)
    session.commit()

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
    existing = DinosaurType(
        name="Tyrannosaurus",
        wikipedia_page_id=30467,
        wikipedia_title="Tyrannosaurus",
        cladogram={"kingdom": "Animalia"},
        article="<p>Cached article body</p>",
        article_date=datetime(2026, 7, 8, tzinfo=timezone.utc),
        insert_date=datetime(2025, 1, 1, tzinfo=timezone.utc),
        main_image_url="https://example.com/image.jpg",
    )
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
    existing = DinosaurType(
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

    assert summary.counters.updated == 1
    assert existing.insert_date.replace(tzinfo=None) == insert_date.replace(tzinfo=None)
    assert existing.main_image_url == "https://example.com/kept.jpg"
    assert existing.period == "Late Cretaceous"
    assert existing.llm_enriched is False


def test_sync_refreshes_incomplete_stub(session: Session, fixture_html, monkeypatch):
    existing = DinosaurType(
        name="Brachiosaurus",
        wikipedia_page_id=12345,
        wikipedia_title="Brachiosaurus",
        cladogram={},
        article=None,
        article_date=datetime(2026, 7, 8, tzinfo=timezone.utc),
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

    assert summary.counters.updated == 1
    assert existing.period == "Late Cretaceous"
    assert existing.cladogram["genus"] == "Tyrannosaurus"
    assert existing.article is not None
    client.page_with_html.assert_called_once()


def test_sync_updates_stub_matched_by_title_when_page_id_differs(
    session: Session, fixture_html, monkeypatch
):
    existing = DinosaurType(
        name="Allosaurus",
        wikipedia_page_id=99999,
        wikipedia_title="Allosaurus",
        cladogram={},
        article=None,
        article_date=datetime(2026, 7, 8, tzinfo=timezone.utc),
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

    assert summary.counters.updated == 1
    assert summary.counters.fetched == 0
    assert existing.wikipedia_page_id == 1347
    assert existing.period == "Late Cretaceous"
    assert existing.article is not None
    assert len(session.exec(select(DinosaurType)).all()) == 1


def test_sync_stale_update_resets_llm_enriched(session: Session, fixture_html, monkeypatch):
    existing = DinosaurType(
        name="Tyrannosaurus",
        wikipedia_page_id=30467,
        wikipedia_title="Tyrannosaurus",
        cladogram={"kingdom": "Animalia"},
        article_date=datetime(2025, 1, 1, tzinfo=timezone.utc),
        insert_date=datetime(2024, 6, 1, tzinfo=timezone.utc),
        llm_enriched=True,
        short_description="Previously enriched catchy description for museum visitors.",
        length="12 m",
    )
    session.add(existing)
    session.commit()

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

    assert existing.llm_enriched is False
    assert existing.length is None
    assert existing.mass is None
    assert existing.location is None
    assert existing.short_description is None


def test_sync_keyboard_interrupt_preserves_committed_records(session: Session, fixture_html, monkeypatch):
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

    saved = session.exec(select(DinosaurType).where(DinosaurType.wikipedia_page_id == 30467)).first()
    missing = session.exec(select(DinosaurType).where(DinosaurType.wikipedia_page_id == 99999)).first()

    assert saved is not None
    assert saved.period == "Late Cretaceous"
    assert missing is None


def test_sync_overwrite_bulk_clears_all_dinosaurs(session: Session, monkeypatch):
    """LLM fields are cleared up front so Ctrl+C mid-sync still leaves DB empty."""
    synced = DinosaurType(
        name="Tyrannosaurus",
        wikipedia_page_id=30467,
        wikipedia_title="Tyrannosaurus",
        cladogram={"kingdom": "Animalia"},
        length="12 m",
        mass="7 t",
        llm_enriched=True,
    )
    unsynced = DinosaurType(
        name="Velociraptor",
        wikipedia_page_id=99999,
        wikipedia_title="Velociraptor",
        cladogram={"kingdom": "Animalia"},
        length="2 m",
        mass="15 kg",
        llm_enriched=True,
    )
    session.add(synced)
    session.add(unsynced)
    session.commit()

    monkeypatch.setattr(
        "app.services.wikipedia_service.sync.list_dinosaur_sync_batches",
        lambda *_args, **_kwargs: [],
    )

    sync_dinosaurs(session, client=MagicMock(), overwrite=True)
    session.refresh(synced)
    session.refresh(unsynced)

    assert synced.length is None
    assert synced.mass is None
    assert synced.llm_enriched is False
    assert unsynced.length is None
    assert unsynced.mass is None
    assert unsynced.llm_enriched is False


def test_sync_overwrite_clears_llm_fields(session: Session, fixture_html, monkeypatch):
    existing = DinosaurType(
        name="Tyrannosaurus",
        wikipedia_page_id=30467,
        wikipedia_title="Tyrannosaurus",
        cladogram={"kingdom": "Animalia", "genus": "Tyrannosaurus et al."},
        article_date=datetime(2026, 7, 8, tzinfo=timezone.utc),
        insert_date=datetime(2025, 1, 1, tzinfo=timezone.utc),
        length="12 m",
        mass="7 t",
        location="North America",
        short_description="Old LLM blurb.",
        llm_enriched=True,
    )
    session.add(existing)
    session.commit()

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

    assert existing.cladogram["genus"] == "Tyrannosaurus"
    assert existing.length is None
    assert existing.mass is None
    assert existing.location is None
    assert existing.short_description is None
    assert existing.llm_enriched is False


def test_sync_overwrite_refetches_up_to_date(session: Session, fixture_html, monkeypatch):
    existing = DinosaurType(
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

    assert summary.counters.updated == 1
    assert summary.counters.skipped == 0
    assert existing.period == "Late Cretaceous"
    client.page_with_html.assert_called_once()


def test_sync_exit_code_threshold():
    summary = SyncSummary(category="Category:Dinosaur_genera", total_candidates=10, counters=SyncCounters(failed=2, fetched=8))
    assert sync_exit_code(summary) == 1

    summary_ok = SyncSummary(category="Category:Dinosaur_genera", total_candidates=10, counters=SyncCounters(failed=0, fetched=10))
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
    assert summary.counters.fetched == 1
    row = session.exec(select(DinosaurType).where(DinosaurType.wikipedia_page_id == 555)).first()
    assert row is not None
    assert row.name == "Giganotosaurus"


def test_sync_overwrite_targeted_dinos_only_clears_those_rows(session: Session, monkeypatch):
    synced = DinosaurType(
        name="Tyrannosaurus",
        wikipedia_page_id=30467,
        wikipedia_title="Tyrannosaurus",
        cladogram={"kingdom": "Animalia"},
        length="12 m",
        mass="7 t",
        llm_enriched=True,
    )
    untouched = DinosaurType(
        name="Velociraptor",
        wikipedia_page_id=99999,
        wikipedia_title="Velociraptor",
        cladogram={"kingdom": "Animalia"},
        length="2 m",
        mass="15 kg",
        llm_enriched=True,
    )
    session.add(synced)
    session.add(untouched)
    session.commit()

    sync_dinosaurs(
        session,
        client=MagicMock(),
        overwrite=True,
        dinos=["Tyrannosaurus"],
    )
    session.refresh(synced)
    session.refresh(untouched)

    assert synced.length is None
    assert synced.llm_enriched is False
    assert untouched.length == "2 m"
    assert untouched.llm_enriched is True
