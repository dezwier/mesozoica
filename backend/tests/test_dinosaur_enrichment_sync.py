"""Tests for dinosaur enrichment sync orchestration."""

from __future__ import annotations

from datetime import datetime, timezone
from unittest.mock import patch

import pytest
from sqlmodel import Session

from app.models.dinosaur_type import DinosaurType
from app.services.dinosaur_enrichment_service.sync import (
    EnrichCounters,
    EnrichSummary,
    enrich_dinosaurs,
    enrich_exit_code,
    reset_llm_enriched_flags,
)


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
    row = DinosaurType(
        name="Tyrannosaurus",
        wikipedia_page_id=30467,
        wikipedia_title="Tyrannosaurus",
        cladogram={"genus": "Tyrannosaurus"},
        article="<p>Tyrannosaurus was a large carnivore found in North America.</p>",
        article_date=datetime(2026, 7, 8, tzinfo=timezone.utc),
    )
    session.add(row)
    session.commit()

    with patch(
        "app.services.dinosaur_enrichment_service.sync.call_gemini_api",
        return_value=(_llm_response(), {"prompt_tokens": 100, "output_tokens": 50}),
    ):
        summary = enrich_dinosaurs(session, dry_run=False)

    session.refresh(row)
    assert summary.counters.enriched == 1
    assert row.llm_enriched is True
    assert row.length == "12 m"
    assert row.mass == "7 t"
    assert row.location == "North America"
    assert row.diet_type == "carnivore"
    assert row.short_description is not None


def test_enrich_disables_gemini_thinking(session: Session):
    row = DinosaurType(
        name="Tyrannosaurus",
        wikipedia_page_id=30468,
        wikipedia_title="Tyrannosaurus",
        cladogram={"genus": "Tyrannosaurus"},
        article="<p>Tyrannosaurus was a large carnivore found in North America.</p>",
        article_date=datetime(2026, 7, 8, tzinfo=timezone.utc),
    )
    session.add(row)
    session.commit()

    with patch(
        "app.services.dinosaur_enrichment_service.sync.call_gemini_api",
        return_value=(_llm_response(), {"prompt_tokens": 100, "output_tokens": 50}),
    ) as mock_api:
        enrich_dinosaurs(session, dry_run=False)

    mock_api.assert_called_once()
    assert mock_api.call_args.kwargs["thinking_budget"] == 0
    assert mock_api.call_args.kwargs["max_output_tokens"] == 4096


def test_enrich_skips_already_enriched(session: Session):
    row = DinosaurType(
        name="Velociraptor",
        wikipedia_page_id=999,
        wikipedia_title="Velociraptor",
        cladogram={},
        article="<p>Small theropod.</p>",
        llm_enriched=True,
        short_description="Already done.",
    )
    session.add(row)
    session.commit()

    with patch("app.services.dinosaur_enrichment_service.sync.call_gemini_api") as mock_api:
        summary = enrich_dinosaurs(session, dry_run=False)

    mock_api.assert_not_called()
    assert summary.counters.enriched == 0
    assert summary.total_candidates == 0


def test_enrich_overwrite_refreshes_enriched(session: Session):
    row = DinosaurType(
        name="Velociraptor",
        wikipedia_page_id=999,
        wikipedia_title="Velociraptor",
        cladogram={},
        article="<p>Small theropod.</p>",
        llm_enriched=True,
        short_description="Old description.",
        length="2 m",
    )
    session.add(row)
    session.commit()

    with patch(
        "app.services.dinosaur_enrichment_service.sync.call_gemini_api",
        return_value=(_llm_response(), {}),
    ):
        summary = enrich_dinosaurs(session, dry_run=False, overwrite=True)

    session.refresh(row)
    assert summary.counters.enriched == 1
    assert row.length == "12 m"


def test_enrich_overwrite_resets_flags_before_processing(session: Session):
    done = DinosaurType(
        name="Velociraptor",
        wikipedia_page_id=901,
        wikipedia_title="Velociraptor",
        cladogram={},
        article="<p>Small theropod.</p>",
        llm_enriched=True,
        short_description="Old description.",
    )
    pending = DinosaurType(
        name="Tyrannosaurus",
        wikipedia_page_id=902,
        wikipedia_title="Tyrannosaurus",
        cladogram={},
        article="<p>Big carnivore.</p>",
        llm_enriched=True,
        short_description="Also old.",
    )
    session.add_all([done, pending])
    session.commit()

    with patch(
        "app.services.dinosaur_enrichment_service.sync.call_gemini_api",
        return_value=(_llm_response(), {}),
    ) as mock_api:
        summary = enrich_dinosaurs(session, dry_run=False, overwrite=True, max_records=1)

    session.refresh(done)
    session.refresh(pending)
    assert summary.counters.enriched == 1
    assert mock_api.call_count == 1
    enriched = [done.llm_enriched, pending.llm_enriched]
    assert enriched.count(True) == 1
    assert enriched.count(False) == 1


def test_enrich_resume_after_interrupted_overwrite(session: Session):
    done = DinosaurType(
        name="Velociraptor",
        wikipedia_page_id=911,
        wikipedia_title="Velociraptor",
        cladogram={},
        article="<p>Small theropod.</p>",
        llm_enriched=True,
    )
    pending = DinosaurType(
        name="Tyrannosaurus",
        wikipedia_page_id=912,
        wikipedia_title="Tyrannosaurus",
        cladogram={},
        article="<p>Big carnivore.</p>",
        llm_enriched=True,
    )
    session.add_all([done, pending])
    session.commit()

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
    session.refresh(done)
    session.refresh(pending)
    assert done.llm_enriched is True
    assert pending.llm_enriched is True


def test_reset_llm_enriched_flags_honors_dino_filter(session: Session):
    tyranno = DinosaurType(
        name="Tyrannosaurus",
        wikipedia_page_id=921,
        wikipedia_title="Tyrannosaurus",
        cladogram={},
        article="<p>Big carnivore.</p>",
        llm_enriched=True,
    )
    giga = DinosaurType(
        name="Giganotosaurus",
        wikipedia_page_id=922,
        wikipedia_title="Giganotosaurus",
        cladogram={},
        article="<p>Another big carnivore.</p>",
        llm_enriched=True,
    )
    session.add_all([tyranno, giga])
    session.commit()

    assert reset_llm_enriched_flags(session, dinos=["Tyrannosaurus"]) == 1
    session.refresh(tyranno)
    session.refresh(giga)
    assert tyranno.llm_enriched is False
    assert giga.llm_enriched is True


def test_enrich_failure_does_not_set_flag(session: Session):
    row = DinosaurType(
        name="BadData",
        wikipedia_page_id=1001,
        wikipedia_title="BadData",
        cladogram={},
        article="<p>Some article.</p>",
    )
    session.add(row)
    session.commit()

    with patch(
        "app.services.dinosaur_enrichment_service.sync.call_gemini_api",
        side_effect=RuntimeError("API failed"),
    ):
        summary = enrich_dinosaurs(session, dry_run=False)

    session.refresh(row)
    assert summary.counters.failed == 1
    assert row.llm_enriched is False


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
    session.add_all(
        [
            DinosaurType(
                name="Alpha",
                wikipedia_page_id=7001,
                wikipedia_title="Alpha",
                cladogram={},
                article="<p>First in id order, no custom image.</p>",
            ),
            DinosaurType(
                name="Beta",
                wikipedia_page_id=7002,
                wikipedia_title="Beta",
                cladogram={},
                article="<p>Has a curated card image.</p>",
                main_image_url=(
                    "https://mesozoica-production.up.railway.app/media/dinosaurs/Beta.webp"
                ),
            ),
            DinosaurType(
                name="Gamma",
                wikipedia_page_id=7003,
                wikipedia_title="Gamma",
                cladogram={},
                article="<p>Later id, no custom image.</p>",
            ),
        ]
    )
    session.commit()

    with patch(
        "app.services.dinosaur_enrichment_service.sync.call_gemini_api",
        return_value=(_llm_response(), {}),
    ) as mock_api:
        summary = enrich_dinosaurs(session, dry_run=False, max_records=1)

    assert summary.counters.enriched == 1
    mock_api.assert_called_once()
    assert mock_api.call_args.kwargs["log_context"] == "Beta"


def test_enrich_dinos_limits_candidates(session: Session):
    session.add_all(
        [
            DinosaurType(
                name="Tyrannosaurus",
                wikipedia_page_id=8001,
                wikipedia_title="Tyrannosaurus",
                cladogram={},
                article="<p>Big carnivore.</p>",
            ),
            DinosaurType(
                name="Velociraptor",
                wikipedia_page_id=8002,
                wikipedia_title="Velociraptor",
                cladogram={},
                article="<p>Small theropod.</p>",
            ),
        ]
    )
    session.commit()

    with patch(
        "app.services.dinosaur_enrichment_service.sync.call_gemini_api",
        return_value=(_llm_response(), {}),
    ) as mock_api:
        summary = enrich_dinosaurs(session, dry_run=False, dinos=["Velociraptor"])

    assert summary.counters.enriched == 1
    mock_api.assert_called_once()
    assert mock_api.call_args.kwargs["log_context"] == "Velociraptor"
