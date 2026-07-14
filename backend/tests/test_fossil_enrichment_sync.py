"""Tests for fossil enrichment sync orchestration."""

from __future__ import annotations

from datetime import datetime, timezone
from unittest.mock import patch

import pytest
from sqlmodel import Session

from app.models.dinosaur import Dinosaur
from app.models.fossil import Fossil
from app.services.fossil_enrichment_service.sync import (
    EnrichCounters,
    EnrichSummary,
    enrich_exit_code,
    enrich_fossils,
)


def _llm_response():
    return {
        "llm_rock_type": "sandstone",
        "llm_category": "body_fossil",
        "llm_subcategory": "teeth",
        "llm_preservation_quality": "good",
        "llm_completeness": "isolated_element",
        "llm_description": (
            "An isolated tyrannosaur tooth from channel sandstone in the Hell Creek Formation."
        ),
    }


def _seed_fossil(
    session: Session,
    *,
    fossil_id: int = 100001,
    dinosaur_name: str = "Tyrannosaurus",
    llm_enriched: bool = False,
    main_image_url: str | None = None,
    fossils_insert_time: datetime | None = None,
) -> tuple[Fossil, Dinosaur]:
    dinosaur = Dinosaur(
        name=dinosaur_name,
        wikipedia_page_id=fossil_id,
        wikipedia_title=dinosaur_name,
        main_image_url=main_image_url,
        fossils_insert_time=fossils_insert_time,
    )
    session.add(dinosaur)
    session.commit()
    session.refresh(dinosaur)

    fossil = Fossil(
        id=fossil_id,
        dinosaur_id=dinosaur.id,
        identified_name=f"{dinosaur_name} rex",
        occurrence_comments="isolated tooth",
        lithology1="sandstone",
        common_body_parts="teeth",
        pres_mode="body",
        llm_enriched=llm_enriched,
        llm_rock_type="shale" if llm_enriched else None,
        llm_category="body_fossil" if llm_enriched else None,
        llm_subcategory="skull" if llm_enriched else None,
        llm_preservation_quality="moderate" if llm_enriched else None,
        llm_completeness="fragmentary" if llm_enriched else None,
        llm_description="Old summary." if llm_enriched else None,
    )
    session.add(fossil)
    session.commit()
    session.refresh(fossil)
    return fossil, dinosaur


@pytest.fixture(autouse=True)
def gemini_key(monkeypatch):
    monkeypatch.setenv("GOOGLE_GEMINI_API_KEY", "test-key")
    monkeypatch.setattr(
        "app.services.fossil_enrichment_service.sync.settings.google_gemini_api_key",
        "test-key",
    )


def test_enrich_writes_fields_and_sets_flag(session: Session):
    fossil, _dinosaur = _seed_fossil(session)

    with patch(
        "app.services.fossil_enrichment_service.sync.call_gemini_api",
        return_value=(_llm_response(), {"prompt_tokens": 100, "output_tokens": 50}),
    ):
        summary = enrich_fossils(session, dry_run=False)

    session.refresh(fossil)
    assert summary.counters.enriched == 1
    assert fossil.llm_enriched is True
    assert fossil.llm_rock_type == "sandstone"
    assert fossil.llm_category == "body_fossil"
    assert fossil.llm_subcategory == "teeth"
    assert fossil.llm_preservation_quality == "good"
    assert fossil.llm_completeness == "isolated_element"
    assert fossil.llm_description is not None
    assert "tooth" in fossil.llm_description.lower()


def test_enrich_disables_gemini_thinking(session: Session):
    _seed_fossil(session)

    with patch(
        "app.services.fossil_enrichment_service.sync.call_gemini_api",
        return_value=(_llm_response(), {"prompt_tokens": 100, "output_tokens": 50}),
    ) as mock_api:
        enrich_fossils(session, dry_run=False)

    mock_api.assert_called_once()
    assert mock_api.call_args.kwargs["thinking_budget"] == 0
    assert mock_api.call_args.kwargs["max_output_tokens"] == 4096


def test_enrich_skips_already_enriched(session: Session):
    _seed_fossil(session, llm_enriched=True)

    with patch("app.services.fossil_enrichment_service.sync.call_gemini_api") as mock_api:
        summary = enrich_fossils(session, dry_run=False)

    mock_api.assert_not_called()
    assert summary.counters.enriched == 0
    assert summary.total_candidates == 0


def test_enrich_overwrite_refreshes_enriched(session: Session):
    fossil, _dinosaur = _seed_fossil(session, llm_enriched=True)

    with patch(
        "app.services.fossil_enrichment_service.sync.call_gemini_api",
        return_value=(_llm_response(), {}),
    ):
        summary = enrich_fossils(session, dry_run=False, overwrite=True)

    session.refresh(fossil)
    assert summary.counters.enriched == 1
    assert fossil.llm_subcategory == "teeth"


def test_enrich_failure_does_not_set_flag(session: Session):
    fossil, _dinosaur = _seed_fossil(session, fossil_id=100002)

    with patch(
        "app.services.fossil_enrichment_service.sync.call_gemini_api",
        side_effect=RuntimeError("API failed"),
    ):
        summary = enrich_fossils(session, dry_run=False)

    session.refresh(fossil)
    assert summary.counters.failed == 1
    assert fossil.llm_enriched is False


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
        "app.services.fossil_enrichment_service.sync.settings.google_gemini_api_key",
        "",
    )
    with pytest.raises(RuntimeError, match="GOOGLE_GEMINI_API_KEY"):
        enrich_fossils(session)


def test_enrich_prioritizes_custom_image_candidates(session: Session):
    synced_at = datetime(2026, 7, 10, tzinfo=timezone.utc)
    _seed_fossil(
        session,
        fossil_id=200001,
        dinosaur_name="Alpha",
        fossils_insert_time=synced_at,
    )
    _seed_fossil(
        session,
        fossil_id=200002,
        dinosaur_name="Beta",
        fossils_insert_time=synced_at,
        main_image_url=(
            "https://mesozoica-production.up.railway.app/media/dinosaurs/Beta.webp"
        ),
    )
    _seed_fossil(
        session,
        fossil_id=200003,
        dinosaur_name="Gamma",
        fossils_insert_time=synced_at,
    )

    with patch(
        "app.services.fossil_enrichment_service.sync.call_gemini_api",
        return_value=(_llm_response(), {}),
    ) as mock_api:
        summary = enrich_fossils(session, dry_run=False, max_records=1)

    assert summary.counters.enriched == 1
    mock_api.assert_called_once()
    assert mock_api.call_args.kwargs["log_context"] == "200002"


def test_enrich_prioritizes_fossils_synced_before_custom_image(session: Session):
    synced_at = datetime(2026, 7, 10, tzinfo=timezone.utc)
    _seed_fossil(
        session,
        fossil_id=210001,
        dinosaur_name="Alpha",
        main_image_url=(
            "https://mesozoica-production.up.railway.app/media/dinosaurs/Alpha.webp"
        ),
    )
    _seed_fossil(
        session,
        fossil_id=210002,
        dinosaur_name="Beta",
        fossils_insert_time=synced_at,
    )

    with patch(
        "app.services.fossil_enrichment_service.sync.call_gemini_api",
        return_value=(_llm_response(), {}),
    ) as mock_api:
        summary = enrich_fossils(session, dry_run=False, max_records=1)

    assert summary.counters.enriched == 1
    mock_api.assert_called_once()
    assert mock_api.call_args.kwargs["log_context"] == "210002"


def test_enrich_dinos_limits_candidates(session: Session):
    _seed_fossil(session, fossil_id=300001, dinosaur_name="Tyrannosaurus")
    _seed_fossil(session, fossil_id=300002, dinosaur_name="Velociraptor")

    with patch(
        "app.services.fossil_enrichment_service.sync.call_gemini_api",
        return_value=(_llm_response(), {}),
    ) as mock_api:
        summary = enrich_fossils(session, dry_run=False, dinos=["Velociraptor"])

    assert summary.counters.enriched == 1
    mock_api.assert_called_once()
    assert mock_api.call_args.kwargs["log_context"] == "300002"
