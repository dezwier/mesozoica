"""Tests for PBDB fossil sync orchestration."""

from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal
from unittest.mock import MagicMock

import pytest
from sqlmodel import Session, select

from app.models.dinosaur import Dinosaur
from app.models.fossil import Fossil
from app.services.pbdb_service.sync import (
    build_fossil_description,
    sync_exit_code,
    sync_fossils,
    SyncCounters,
    SyncSummary,
)


def _dinosaur(
    *,
    name: str = "Tyrannosaurus",
    page_id: int = 30467,
) -> Dinosaur:
    return Dinosaur(
        name=name,
        wikipedia_page_id=page_id,
        wikipedia_title=name,
        cladogram={"genus": name},
        article_date=datetime(2026, 7, 8, tzinfo=timezone.utc),
    )


def _tyrannosaurus_record(*, occurrence_no: str = "139292", formation: str = "Scollard") -> dict:
    return {
        "occurrence_no": occurrence_no,
        "identified_name": "Tyrannosaurus rex",
        "accepted_name": "Tyrannosaurus rex",
        "primary_name": "Tyrannosaurus",
        "species_name": "rex",
        "family": "Tyrannosauridae",
        "lat": "51.906399",
        "lng": "-113.028900",
        "cc": "CA",
        "state": "Alberta",
        "formation": formation,
        "min_ma": 66,
        "max_ma": 72.2,
        "early_interval": "Late Maastrichtian",
        "collection_name": "Knudsen's Coulee (NMC 9954)",
        "collection_aka": "East of Huxley",
        "collection_dates": "1946, 1962",
        "geogcomments": (
            "center of section 10, township 34, range 22, W. 4th meridian; "
            "7 miles east of Huxley, AB in Knudsen's Coulee"
        ),
        "stratcomments": "52 m above base (Kneehills Tuff)",
        "lithdescript": "concretionary zone in the basal part of a channel sandstone",
        "collectors": "C. M. Sternberg, W. Langston",
        "museum": "GSC",
        "pres_mode": "body",
        "preservation_quality": "medium",
        "abund_value": "1",
        "abund_unit": "specimens",
    }


def _aves_record() -> dict:
    return {
        "occurrence_no": "41524",
        "identified_name": "Aves indet.",
        "accepted_name": "Aves",
        "primary_name": "Aves",
        "species_name": "indet.",
        "lat": "51.083332",
        "lng": "-1.166667",
        "cc": "UK",
        "state": "England",
        "formation": "Earnley",
        "min_ma": 41.03,
        "max_ma": 48.07,
    }


def _mock_client(records_by_name: dict[str, list[dict]]) -> MagicMock:
    client = MagicMock()

    def iter_occurrences(*, base_name: str):
        yield from records_by_name.get(base_name, [])

    client.iter_occurrences.side_effect = iter_occurrences
    return client


def test_sync_inserts_new_fossil(session: Session):
    dinosaur = _dinosaur()
    session.add(dinosaur)
    session.commit()
    session.refresh(dinosaur)

    client = _mock_client({"Tyrannosaurus": [_tyrannosaurus_record()]})
    summary = sync_fossils(session, client=client, dry_run=False)
    session.commit()

    fossil = session.get(Fossil, 139292)
    assert fossil is not None
    assert fossil.dinosaur_id == dinosaur.id
    assert fossil.identified_name == "Tyrannosaurus rex"
    assert fossil.latitude == Decimal("51.906399")
    assert fossil.longitude == Decimal("-113.028900")
    assert fossil.country_code == "CA"
    assert fossil.state == "Alberta"
    assert fossil.geological_formation == "Scollard"
    assert fossil.min_age_ma == Decimal("66.00")
    assert fossil.max_age_ma == Decimal("72.20")
    assert fossil.early_interval == "Late Maastrichtian"
    assert fossil.family == "Tyrannosauridae"
    assert fossil.collection_name == "Knudsen's Coulee (NMC 9954)"
    assert fossil.collection_dates == "1946, 1962"
    assert fossil.stratcomments == "52 m above base (Kneehills Tuff)"
    assert fossil.lithdescript == "concretionary zone in the basal part of a channel sandstone"
    assert fossil.collectors == "C. M. Sternberg, W. Langston"
    assert fossil.museum == "GSC"
    assert fossil.pres_mode == "body"
    assert fossil.preservation_quality == "medium"
    assert fossil.abund_value == 1
    assert fossil.abund_unit == "specimens"
    assert fossil.description is not None
    assert "Huxley" in fossil.description
    assert "Kneehills Tuff" in fossil.description
    assert "Lithology:" in fossil.description
    assert summary.counters.fetched == 1
    assert summary.counters.updated == 0


def test_sync_updates_existing_fossil_when_overwrite(session: Session):
    dinosaur = _dinosaur()
    session.add(dinosaur)
    session.commit()
    session.refresh(dinosaur)

    existing = Fossil(
        id=139292,
        dinosaur_id=dinosaur.id,
        identified_name="Tyrannosaurus rex",
        geological_formation="Old Formation",
    )
    session.add(existing)
    session.commit()

    client = _mock_client({"Tyrannosaurus": [_tyrannosaurus_record(formation="Scollard")]})
    summary = sync_fossils(session, client=client, dry_run=False, overwrite=True)
    session.commit()

    fossil = session.get(Fossil, 139292)
    assert fossil is not None
    assert fossil.geological_formation == "Scollard"
    assert summary.counters.updated == 1
    assert summary.counters.fetched == 0


def test_sync_skips_existing_fossil_without_overwrite(session: Session):
    dinosaur = _dinosaur()
    session.add(dinosaur)
    session.commit()
    session.refresh(dinosaur)

    existing = Fossil(
        id=139292,
        dinosaur_id=dinosaur.id,
        identified_name="Tyrannosaurus rex",
        geological_formation="Old Formation",
    )
    session.add(existing)
    session.commit()

    client = _mock_client({"Tyrannosaurus": [_tyrannosaurus_record(formation="Scollard")]})
    summary = sync_fossils(session, client=client, dry_run=False, overwrite=False)
    session.commit()

    fossil = session.get(Fossil, 139292)
    assert fossil is not None
    assert fossil.geological_formation == "Old Formation"
    assert summary.counters.unchanged == 1
    assert summary.counters.updated == 0
    assert summary.counters.fetched == 0


def test_sync_skips_aves_records(session: Session):
    dinosaur = _dinosaur(name="Aves")
    session.add(dinosaur)
    session.commit()

    client = _mock_client({"Aves": [_aves_record()]})
    summary = sync_fossils(session, client=client, dry_run=False)
    session.commit()

    fossils = list(session.exec(select(Fossil)).all())
    assert fossils == []
    assert summary.counters.skipped == 1


def test_sync_dinos_filter_limits_genera(session: Session, monkeypatch):
    tyranno = _dinosaur(name="Tyrannosaurus", page_id=1)
    giga = _dinosaur(name="Giganotosaurus", page_id=2)
    session.add(tyranno)
    session.add(giga)
    session.commit()
    session.refresh(tyranno)

    queried: list[str] = []

    def iter_occurrences(*, base_name: str):
        queried.append(base_name)
        if base_name == "Tyrannosaurus":
            yield _tyrannosaurus_record()
        return
        yield  # pragma: no cover

    client = MagicMock()
    client.iter_occurrences.side_effect = iter_occurrences

    sync_fossils(session, client=client, dry_run=False, dinos=["Tyrannosaurus"])
    session.commit()

    assert queried == ["Tyrannosaurus"]
    fossil = session.get(Fossil, 139292)
    assert fossil is not None
    assert fossil.dinosaur_id == tyranno.id


def test_sync_dry_run_does_not_write(session: Session):
    dinosaur = _dinosaur()
    session.add(dinosaur)
    session.commit()

    client = _mock_client({"Tyrannosaurus": [_tyrannosaurus_record()]})
    summary = sync_fossils(session, client=client, dry_run=True)

    fossils = list(session.exec(select(Fossil)).all())
    assert fossils == []
    assert summary.dry_run is True
    assert summary.counters.fetched == 1


def test_sync_dry_run_counts_unchanged_without_overwrite(session: Session):
    dinosaur = _dinosaur()
    session.add(dinosaur)
    session.commit()
    session.refresh(dinosaur)

    existing = Fossil(
        id=139292,
        dinosaur_id=dinosaur.id,
        identified_name="Tyrannosaurus rex",
        geological_formation="Old Formation",
    )
    session.add(existing)
    session.commit()

    client = _mock_client({"Tyrannosaurus": [_tyrannosaurus_record(formation="Scollard")]})
    summary = sync_fossils(session, client=client, dry_run=True, overwrite=False)

    assert summary.counters.unchanged == 1
    assert summary.counters.updated == 0


def test_build_fossil_description_composes_site_summary():
    description = build_fossil_description(_tyrannosaurus_record())
    assert description is not None
    assert "Huxley" in description
    assert "Kneehills Tuff" in description
    assert "Lithology:" in description


def test_build_fossil_description_returns_none_without_text():
    assert build_fossil_description({"occurrence_no": "1"}) is None


def test_sync_exit_code_zero_on_success():
    summary = SyncSummary(total_dinosaurs=1, counters=SyncCounters(fetched=3))
    assert sync_exit_code(summary) == 0


def test_sync_exit_code_nonzero_on_failures():
    summary = SyncSummary(total_dinosaurs=1, counters=SyncCounters(failed=1))
    assert sync_exit_code(summary) == 1


def test_sync_counts_per_genus_failure(session: Session):
    dinosaur = _dinosaur()
    session.add(dinosaur)
    session.commit()

    client = MagicMock()
    client.iter_occurrences.side_effect = RuntimeError("PBDB unavailable")

    summary = sync_fossils(session, client=client, dry_run=False)
    assert summary.counters.failed == 1
    assert sync_exit_code(summary) == 1
