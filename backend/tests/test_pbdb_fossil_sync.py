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
    resolve_since,
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
        "primary_name": "Tyrannosaurus",
        "species_name": "rex",
        "accepted_name": "Tyrannosaurus rex",
        "accepted_no": "54833",
        "accepted_rank": "species",
        "accepted_attr": "Osborn 1905",
        "genus": "Tyrannosaurus",
        "order": "NO_ORDER_SPECIFIED",
        "class": "Reptilia",
        "phylum": "Chordata",
        "identified_rank": "species",
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
        "collection_type": "biostratigraphic",
        "occurrence_comments": "partial skull and vertebrae",
        "geogcomments": (
            "center of section 10, township 34, range 22, W. 4th meridian; "
            "7 miles east of Huxley, AB in Knudsen's Coulee"
        ),
        "stratcomments": "52 m above base (Kneehills Tuff)",
        "lithdescript": "concretionary zone in the basal part of a channel sandstone",
        "composition": "hydroxyapatite",
        "architecture": "compact or dense",
        "fragmentation": "slightly abraded",
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
    assert fossil.collection_type == "biostratigraphic"
    assert fossil.occurrence_comments == "partial skull and vertebrae"
    assert fossil.stratcomments == "52 m above base (Kneehills Tuff)"
    assert fossil.lithdescript == "concretionary zone in the basal part of a channel sandstone"
    assert fossil.composition == "hydroxyapatite"
    assert fossil.architecture == "compact or dense"
    assert fossil.fragmentation == "slightly abraded"
    assert fossil.collectors == "C. M. Sternberg, W. Langston"
    assert fossil.museum == "GSC"
    assert fossil.pres_mode == "body"
    assert fossil.preservation_quality == "medium"
    assert fossil.abund_value == 1
    assert fossil.abund_unit == "specimens"
    assert fossil.description is None
    assert fossil.accepted_name == "Tyrannosaurus rex"
    assert fossil.accepted_no == 54833
    assert fossil.accepted_rank == "species"
    assert fossil.accepted_attr == "Osborn 1905"
    assert fossil.genus == "Tyrannosaurus"
    assert fossil.taxon_order == "NO_ORDER_SPECIFIED"
    assert fossil.taxon_class == "Reptilia"
    assert fossil.phylum == "Chordata"
    assert fossil.identified_rank == "species"
    assert fossil.geogcomments is not None
    assert "Huxley" in fossil.geogcomments
    assert summary.counters.fetched == 1
    assert summary.counters.updated == 0

    session.refresh(dinosaur)
    assert dinosaur.fossils_insert_time is not None


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


def test_sync_prioritizes_dinosaurs_with_custom_image(session: Session):
    curated = _dinosaur(name="Zephyrosaurus", page_id=10)
    curated.main_image_url = (
        "https://mesozoica-production.up.railway.app/media/dinosaurs/Zephyrosaurus.webp"
    )
    uncurated = _dinosaur(name="Anchisaurus", page_id=11)
    uncurated.main_image_url = "https://upload.wikimedia.org/wikipedia/commons/anchi.jpg"
    session.add(curated)
    session.add(uncurated)
    session.commit()

    queried: list[str] = []

    def iter_occurrences(*, base_name: str):
        queried.append(base_name)
        return
        yield  # pragma: no cover

    client = MagicMock()
    client.iter_occurrences.side_effect = iter_occurrences

    sync_fossils(session, client=client, dry_run=True)

    assert queried == ["Zephyrosaurus", "Anchisaurus"]


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

    session.refresh(dinosaur)
    assert dinosaur.fossils_insert_time is None


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

    session.refresh(dinosaur)
    assert dinosaur.fossils_insert_time is None


def test_sync_skips_recently_synced_dinosaur(session: Session):
    recent = datetime(2026, 7, 11, 12, 0, tzinfo=timezone.utc)
    stale = datetime(2026, 7, 1, 12, 0, tzinfo=timezone.utc)

    recent_dino = _dinosaur(name="Tyrannosaurus", page_id=1)
    recent_dino.fossils_insert_time = recent
    stale_dino = _dinosaur(name="Giganotosaurus", page_id=2)
    stale_dino.fossils_insert_time = stale
    session.add(recent_dino)
    session.add(stale_dino)
    session.commit()
    session.refresh(stale_dino)

    client = _mock_client(
        {
            "Giganotosaurus": [
                {
                    **_tyrannosaurus_record(occurrence_no="999001"),
                    "primary_name": "Giganotosaurus",
                    "identified_name": "Giganotosaurus carolinii",
                }
            ]
        }
    )
    summary = sync_fossils(
        session,
        client=client,
        dry_run=False,
        since=datetime(2026, 7, 10, 0, 0, tzinfo=timezone.utc),
    )
    session.commit()

    assert summary.total_dinosaurs == 1
    assert summary.stale_skipped == 1
    fossil = session.get(Fossil, 999001)
    assert fossil is not None
    assert fossil.dinosaur_id == stale_dino.id


def test_sync_since_filter_bypassed_with_overwrite(session: Session):
    recent = datetime(2026, 7, 11, 12, 0, tzinfo=timezone.utc)
    dinosaur = _dinosaur()
    dinosaur.fossils_insert_time = recent
    session.add(dinosaur)
    session.commit()
    session.refresh(dinosaur)

    client = _mock_client({"Tyrannosaurus": [_tyrannosaurus_record()]})
    summary = sync_fossils(
        session,
        client=client,
        dry_run=False,
        overwrite=True,
        since=datetime(2026, 7, 10, 0, 0, tzinfo=timezone.utc),
    )
    session.commit()

    assert summary.total_dinosaurs == 1
    assert summary.stale_skipped == 0
    session.refresh(dinosaur)
    assert dinosaur.fossils_insert_time is not None
    updated = dinosaur.fossils_insert_time
    if updated.tzinfo is None:
        updated = updated.replace(tzinfo=timezone.utc)
    assert updated > recent


def test_resolve_since_from_stale_days():
    cutoff = resolve_since(stale_days=7)
    assert cutoff is not None
    assert cutoff.tzinfo == timezone.utc
    assert (datetime.now(timezone.utc) - cutoff).days == 7
