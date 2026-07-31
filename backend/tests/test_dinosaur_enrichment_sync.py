"""Tests for dinosaur enrichment sync orchestration."""

from __future__ import annotations

from unittest.mock import patch

import pytest
from sqlmodel import Session

from app.services.dinosaur_enrichment_service.sync import (
    EnrichCounters,
    EnrichSummary,
    enrich_dinosaurs,
    enrich_exit_code,
    reset_llm_enriched_flags,
)
from tests.helpers.dinosaur_fixtures import current_revision, seed_dinosaur_type


def _llm_response():
    return {
        "length": "12 m",
        "mass": "7 t",
        "location": "North America",
        "diet_type": "carnivore",
        "short_description": (
            "A towering Late Cretaceous apex predator whose bone-crushing bite "
            "made it the most famous dinosaur of all time."
        ),
    }


@pytest.fixture(autouse=True)
def gemini_key(monkeypatch):
    monkeypatch.setenv("GOOGLE_GEMINI_API_KEY", "test-key")
    monkeypatch.setattr(
        "app.services.dinosaur_enrichment_service.sync.settings.google_gemini_api_key",
        "test-key",
    )


def test_enrich_writes_fields_and_sets_flag(session: Session):
    row = seed_dinosaur_type(
        session,
        name="Tyrannosaurus",
        wikipedia_page_id=30467,
        cladogram={"genus": "Tyrannosaurus"},
        article="<p>Tyrannosaurus was a large carnivore found in North America.</p>",
    )

    with patch(
        "app.services.dinosaur_enrichment_service.sync.call_gemini_api",
        return_value=(_llm_response(), {"prompt_tokens": 100, "output_tokens": 50}),
    ):
        summary = enrich_dinosaurs(session, dry_run=False)

    revision = current_revision(session, row)
    assert summary.counters.enriched == 1
    assert revision is not None
    assert revision.llm_enriched is True
    assert revision.length == "12 m"
    assert revision.mass == "7 t"
    assert revision.location == "North America"
    assert revision.diet_type == "carnivore"
    assert revision.short_description is not None


def test_enrich_disables_gemini_thinking(session: Session):
    seed_dinosaur_type(
        session,
        name="Tyrannosaurus",
        wikipedia_page_id=30468,
        cladogram={"genus": "Tyrannosaurus"},
        article="<p>Tyrannosaurus was a large carnivore found in North America.</p>",
    )

    with patch(
        "app.services.dinosaur_enrichment_service.sync.call_gemini_api",
        return_value=(_llm_response(), {"prompt_tokens": 100, "output_tokens": 50}),
    ) as mock_api:
        enrich_dinosaurs(session, dry_run=False)

    mock_api.assert_called_once()
    assert mock_api.call_args.kwargs["thinking_budget"] == 0
    assert mock_api.call_args.kwargs["max_output_tokens"] == 4096


def test_enrich_skips_already_enriched(session: Session):
    seed_dinosaur_type(
        session,
        name="Velociraptor",
        wikipedia_page_id=999,
        article="<p>Small theropod.</p>",
        llm_enriched=True,
        short_description="Already done.",
    )

    with patch("app.services.dinosaur_enrichment_service.sync.call_gemini_api") as mock_api:
        summary = enrich_dinosaurs(session, dry_run=False)

    mock_api.assert_not_called()
    assert summary.counters.enriched == 0
    assert summary.total_candidates == 0


def test_enrich_overwrite_refreshes_enriched(session: Session):
    row = seed_dinosaur_type(
        session,
        name="Velociraptor",
        wikipedia_page_id=999,
        article="<p>Small theropod.</p>",
        llm_enriched=True,
        short_description="Old description.",
        length="2 m",
    )

    with patch(
        "app.services.dinosaur_enrichment_service.sync.call_gemini_api",
        return_value=(_llm_response(), {}),
    ):
        summary = enrich_dinosaurs(session, dry_run=False, overwrite=True)

    revision = current_revision(session, row)
    assert summary.counters.enriched == 1
    assert revision is not None
    assert revision.length == "12 m"


def test_enrich_overwrite_resets_flags_before_processing(session: Session):
    done = seed_dinosaur_type(
        session,
        name="Velociraptor",
        wikipedia_page_id=901,
        article="<p>Small theropod.</p>",
        llm_enriched=True,
        short_description="Old description.",
    )
    pending = seed_dinosaur_type(
        session,
        name="Tyrannosaurus",
        wikipedia_page_id=902,
        article="<p>Big carnivore.</p>",
        llm_enriched=True,
        short_description="Also old.",
    )

    with patch(
        "app.services.dinosaur_enrichment_service.sync.call_gemini_api",
        return_value=(_llm_response(), {}),
    ) as mock_api:
        summary = enrich_dinosaurs(session, dry_run=False, overwrite=True, max_records=1)

    done_rev = current_revision(session, done)
    pending_rev = current_revision(session, pending)
    assert summary.counters.enriched == 1
    assert mock_api.call_count == 1
    enriched = [done_rev.llm_enriched, pending_rev.llm_enriched]
    assert enriched.count(True) == 1
    assert enriched.count(False) == 1


def test_enrich_resume_after_interrupted_overwrite(session: Session):
    done = seed_dinosaur_type(
        session,
        name="Velociraptor",
        wikipedia_page_id=911,
        article="<p>Small theropod.</p>",
        llm_enriched=True,
    )
    pending = seed_dinosaur_type(
        session,
        name="Tyrannosaurus",
        wikipedia_page_id=912,
        article="<p>Big carnivore.</p>",
        llm_enriched=True,
    )

    with patch(
        "app.services.dinosaur_enrichment_service.sync.call_gemini_api",
        return_value=(_llm_response(), {}),
    ):
        enrich_dinosaurs(session, dry_run=False, overwrite=True, max_records=1)

    with patch(
        "app.services.dinosaur_enrichment_service.sync.call_gemini_api",
        return_value=(_llm_response(), {}),
    ) as mock_api:
        summary = enrich_dinosaurs(session, dry_run=False)

    assert summary.counters.enriched == 1
    mock_api.assert_called_once()
    assert current_revision(session, done).llm_enriched is True
    assert current_revision(session, pending).llm_enriched is True


def test_reset_llm_enriched_flags_honors_dino_filter(session: Session):
    tyranno = seed_dinosaur_type(
        session,
        name="Tyrannosaurus",
        wikipedia_page_id=921,
        article="<p>Big carnivore.</p>",
        llm_enriched=True,
    )
    giga = seed_dinosaur_type(
        session,
        name="Giganotosaurus",
        wikipedia_page_id=922,
        article="<p>Another big carnivore.</p>",
        llm_enriched=True,
    )

    assert reset_llm_enriched_flags(session, dinos=["Tyrannosaurus"]) == 1
    assert current_revision(session, tyranno).llm_enriched is False
    assert current_revision(session, giga).llm_enriched is True


def test_enrich_failure_does_not_set_flag(session: Session):
    row = seed_dinosaur_type(
        session,
        name="BadData",
        wikipedia_page_id=1001,
        article="<p>Some article.</p>",
    )

    with patch(
        "app.services.dinosaur_enrichment_service.sync.call_gemini_api",
        side_effect=RuntimeError("API failed"),
    ):
        summary = enrich_dinosaurs(session, dry_run=False)

    revision = current_revision(session, row)
    assert summary.counters.failed == 1
    assert revision is not None
    assert revision.llm_enriched is False


def test_enrich_exit_code_threshold():
    summary = EnrichSummary(
        total_candidates=10,
        counters=EnrichCounters(enriched=8, failed=2),
    )
    assert enrich_exit_code(summary) == 1

    summary_ok = EnrichSummary(
        total_candidates=10,
        counters=EnrichCounters(enriched=10, failed=0),
    )
    assert enrich_exit_code(summary_ok) == 0


def test_enrich_requires_api_key(monkeypatch, session: Session):
    monkeypatch.setattr(
        "app.services.dinosaur_enrichment_service.sync.settings.google_gemini_api_key",
        "",
    )
    with pytest.raises(RuntimeError, match="GOOGLE_GEMINI_API_KEY"):
        enrich_dinosaurs(session)


def test_enrich_prioritizes_custom_image_candidates(session: Session):
    seed_dinosaur_type(
        session,
        name="Alpha",
        wikipedia_page_id=7001,
        article="<p>First in id order, no custom image.</p>",
    )
    seed_dinosaur_type(
        session,
        name="Beta",
        wikipedia_page_id=7002,
        article="<p>Has a curated card image.</p>",
        main_image_url=(
            "https://mesozoica-production.up.railway.app/media/dinosaurs/Beta.webp"
        ),
    )
    seed_dinosaur_type(
        session,
        name="Gamma",
        wikipedia_page_id=7003,
        article="<p>Later id, no custom image.</p>",
    )

    with patch(
        "app.services.dinosaur_enrichment_service.sync.call_gemini_api",
        return_value=(_llm_response(), {}),
    ) as mock_api:
        summary = enrich_dinosaurs(session, dry_run=False, max_records=1)

    assert summary.counters.enriched == 1
    mock_api.assert_called_once()
    assert mock_api.call_args.kwargs["log_context"].startswith("Beta#")


def test_enrich_dinos_limits_candidates(session: Session):
    seed_dinosaur_type(
        session,
        name="Tyrannosaurus",
        wikipedia_page_id=8001,
        article="<p>Big carnivore.</p>",
    )
    seed_dinosaur_type(
        session,
        name="Velociraptor",
        wikipedia_page_id=8002,
        article="<p>Small theropod.</p>",
    )

    with patch(
        "app.services.dinosaur_enrichment_service.sync.call_gemini_api",
        return_value=(_llm_response(), {}),
    ) as mock_api:
        summary = enrich_dinosaurs(session, dry_run=False, dinos=["Velociraptor"])

    assert summary.counters.enriched == 1
    mock_api.assert_called_once()
    assert mock_api.call_args.kwargs["log_context"].startswith("Velociraptor#")


def test_enrich_any_unenriched_revision_not_only_current(session: Session):
    """Older non-current revisions with article still get enriched."""
    row = seed_dinosaur_type(
        session,
        name="Tyrannosaurus",
        wikipedia_page_id=30467,
        article="<p>Current article.</p>",
        llm_enriched=True,
        length="12 m",
    )
    from app.models.dinosaur_type_revision import DinosaurTypeRevision
    from app.services.wikipedia_service.content_hash import revision_content_hash

    old = DinosaurTypeRevision(
        dinosaur_type_id=int(row.id),
        content_hash=revision_content_hash(article="<p>Older article.</p>"),
        article="<p>Older article.</p>",
        cladogram={},
        llm_enriched=False,
    )
    session.add(old)
    session.commit()

    with patch(
        "app.services.dinosaur_enrichment_service.sync.call_gemini_api",
        return_value=(_llm_response(), {}),
    ) as mock_api:
        summary = enrich_dinosaurs(session, dry_run=False)

    session.refresh(old)
    assert summary.counters.enriched == 1
    assert old.llm_enriched is True
    assert mock_api.call_count == 1
