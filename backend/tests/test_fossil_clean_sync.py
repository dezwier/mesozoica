"""Tests for fossil clean table sync orchestration."""

from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal

import pytest
from sqlmodel import Session, select

from app.models.dinosaur import Dinosaur
from app.models.fossil import Fossil
from app.models.fossil_clean import FossilClean
from app.models.site_clean import SiteClean
from app.models.site_type import SiteType
from app.services.fossil_clean_service.sync import sync_clean_tables, sync_exit_code


def _dinosaur(*, name: str = "Tyrannosaurus", page_id: int = 30467) -> Dinosaur:
    return Dinosaur(
        name=name,
        wikipedia_page_id=page_id,
        wikipedia_title=name,
        cladogram={"genus": name},
        article_date=datetime(2026, 7, 8, tzinfo=timezone.utc),
    )


def _fossil(
    *,
    occurrence_no: int,
    dinosaur_id: int,
    collection_no: int = 9954,
    name: str = "Tyrannosaurus rex",
) -> Fossil:
    return Fossil(
        id=occurrence_no,
        dinosaur_id=dinosaur_id,
        identified_name=name,
        latitude=Decimal("51.906399"),
        longitude=Decimal("-113.028900"),
        country_code="CA",
        state="Alberta",
        geological_formation="Scollard",
        min_age_ma=Decimal("66.00"),
        max_age_ma=Decimal("72.20"),
        collection_no=collection_no,
        collection_dates="1946, 1962",
        lithology1="sandstone",
        pres_mode="body",
        preservation_quality="medium",
        common_body_parts="skull, vertebrae",
        occurrence_comments="partial skull and vertebrae",
    )


def test_sync_builds_clean_tables(session: Session):
    dinosaur = _dinosaur()
    session.add(dinosaur)
    session.commit()
    session.refresh(dinosaur)

    session.add(_fossil(occurrence_no=139292, dinosaur_id=dinosaur.id))
    session.add(
        _fossil(
            occurrence_no=139293,
            dinosaur_id=dinosaur.id,
            collection_no=9955,
            name="Tyrannosaurus sp.",
        )
    )
    session.commit()

    summary = sync_clean_tables(session)

    sites = list(session.exec(select(SiteClean)).all())
    fossils = list(session.exec(select(FossilClean)).all())

    assert summary.counters.sites_written == 2
    assert summary.counters.fossils_written == 2
    assert len(sites) == 2
    assert len(fossils) == 2
    assert sync_exit_code(summary) == 0

    fossil_row = next(row for row in fossils if row.fossil_id == 139292)
    assert fossil_row.site_id == 9954
    assert fossil_row.dinosaur_id == dinosaur.id
    assert fossil_row.name == "Tyrannosaurus rex"
    assert fossil_row.type == "body"
    assert fossil_row.sub_category == "skull,vertebra"
    assert fossil_row.preservation_quality == "medium"
    assert fossil_row.collection_year_min == 1946
    assert fossil_row.collection_year_max == 1962
    assert fossil_row.comment is not None
    assert "partial skull and vertebrae" in fossil_row.comment

    site_row = next(row for row in sites if row.site_id == 9954)
    assert site_row.formation == "Scollard"
    assert site_row.rock_type == "sandstone"
    assert site_row.min_age_ma == Decimal("66.00")
    assert site_row.max_age_ma == Decimal("72.20")
    assert site_row.site_type_id is not None
    assert site_row.country_code == "CA"

    site_types = list(session.exec(select(SiteType)).all())
    assert len(site_types) == 1
    assert site_types[0].period == "cretaceous"
    assert site_types[0].rock_type == "sandstone"
    assert site_types[0].id == site_row.site_type_id


def test_sync_dry_run_writes_nothing(session: Session):
    dinosaur = _dinosaur()
    session.add(dinosaur)
    session.commit()
    session.refresh(dinosaur)
    session.add(_fossil(occurrence_no=139292, dinosaur_id=dinosaur.id))
    session.commit()

    summary = sync_clean_tables(session, dry_run=True)

    assert summary.dry_run is True
    assert summary.counters.fossils_written == 1
    assert list(session.exec(select(FossilClean)).all()) == []
    assert list(session.exec(select(SiteClean)).all()) == []


def test_sync_partial_dino_filter(session: Session):
    trex = _dinosaur(name="Tyrannosaurus", page_id=30467)
    allo = _dinosaur(name="Allosaurus", page_id=30468)
    session.add(trex)
    session.add(allo)
    session.commit()
    session.refresh(trex)
    session.refresh(allo)

    session.add(_fossil(occurrence_no=139292, dinosaur_id=trex.id))
    session.add(
        _fossil(
            occurrence_no=200001,
            dinosaur_id=allo.id,
            collection_no=2000,
            name="Allosaurus fragilis",
        )
    )
    session.commit()

    sync_clean_tables(session)
    sync_clean_tables(session, dinos=["Tyrannosaurus"])

    fossils = list(session.exec(select(FossilClean)).all())
    assert len(fossils) == 2
    trex_row = next(row for row in fossils if row.fossil_id == 139292)
    allo_row = next(row for row in fossils if row.fossil_id == 200001)
    assert trex_row.sub_category == "skull,vertebra"
    assert allo_row.fossil_id == 200001


def test_sync_fails_when_collection_no_missing(session: Session):
    dinosaur = _dinosaur()
    session.add(dinosaur)
    session.commit()
    session.refresh(dinosaur)

    fossil = _fossil(occurrence_no=139292, dinosaur_id=dinosaur.id)
    fossil.collection_no = None
    session.add(fossil)
    session.commit()

    summary = sync_clean_tables(session)
    assert summary.counters.fossils_skipped == 1
    assert sync_exit_code(summary) == 1
