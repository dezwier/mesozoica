"""Tests for site table sync orchestration."""

from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal

from sqlmodel import Session, select

from app.models.dinosaur import Dinosaur
from app.models.fossil import Fossil
from app.models.site import Site
from app.services.site_service.sync import site_sync_exit_code, sync_sites


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


def test_sync_builds_site_table_and_links_fossils(session: Session):
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

    summary = sync_sites(session)

    sites = list(session.exec(select(Site)).all())
    fossils = list(session.exec(select(Fossil)).all())

    assert summary.counters.sites_written == 2
    assert summary.counters.fossils_linked == 2
    assert len(sites) == 2
    assert len(fossils) == 2
    assert site_sync_exit_code(summary) == 0

    fossil_row = next(row for row in fossils if row.id == 139292)
    assert fossil_row.site_id == 9954
    assert fossil_row.dinosaur_id == dinosaur.id

    site_row = next(row for row in sites if row.site_id == 9954)
    assert site_row.formation == "Scollard"
    assert site_row.rock_type == "sandstone"
    assert site_row.min_age_ma == Decimal("66.00")
    assert site_row.max_age_ma == Decimal("72.20")
    assert site_row.site_type_id is None
    assert site_row.country_code == "CA"


def test_sync_uses_llm_imp_rock_type_when_pbdb_lithology_missing(session: Session):
    dinosaur = _dinosaur()
    session.add(dinosaur)
    session.commit()
    session.refresh(dinosaur)

    fossil = _fossil(occurrence_no=139294, dinosaur_id=dinosaur.id)
    fossil.lithology1 = None
    fossil.lithdescript = None
    fossil.stratcomments = None
    fossil.lithadj1 = None
    fossil.llm_imp_rock_type = "mudstone"
    session.add(fossil)
    session.commit()

    sync_sites(session)

    site_row = session.exec(select(Site).where(Site.site_id == 9954)).one()
    assert site_row.rock_type == "mudstone"


def test_sync_prefers_pbdb_lithology_over_llm_imp_rock_type(session: Session):
    dinosaur = _dinosaur()
    session.add(dinosaur)
    session.commit()
    session.refresh(dinosaur)

    fossil = _fossil(occurrence_no=139295, dinosaur_id=dinosaur.id)
    fossil.lithology1 = "sandstone"
    fossil.llm_imp_rock_type = "mudstone"
    session.add(fossil)
    session.commit()

    sync_sites(session)

    site_row = session.exec(select(Site).where(Site.site_id == 9954)).one()
    assert site_row.rock_type == "sandstone"


def test_sync_uses_llm_imp_rock_type_when_pbdb_lithology_not_reported(session: Session):
    dinosaur = _dinosaur()
    session.add(dinosaur)
    session.commit()
    session.refresh(dinosaur)

    fossil = _fossil(occurrence_no=139296, dinosaur_id=dinosaur.id)
    fossil.lithology1 = "not reported"
    fossil.llm_imp_rock_type = "shale"
    session.add(fossil)
    session.commit()

    sync_sites(session)

    site_row = session.exec(select(Site).where(Site.site_id == 9954)).one()
    assert site_row.rock_type == "shale"


def test_sync_dry_run_writes_nothing(session: Session):
    dinosaur = _dinosaur()
    session.add(dinosaur)
    session.commit()
    session.refresh(dinosaur)
    session.add(_fossil(occurrence_no=139292, dinosaur_id=dinosaur.id))
    session.commit()

    summary = sync_sites(session, dry_run=True)

    assert summary.dry_run is True
    assert summary.counters.fossils_linked == 1
    assert list(session.exec(select(Site)).all()) == []
    fossil = session.exec(select(Fossil).where(Fossil.id == 139292)).one()
    assert fossil.site_id is None


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

    sync_sites(session)
    sync_sites(session, dinos=["Tyrannosaurus"])

    fossils = list(session.exec(select(Fossil)).all())
    assert len(fossils) == 2
    trex_fossil = next(row for row in fossils if row.id == 139292)
    allo_fossil = next(row for row in fossils if row.id == 200001)
    assert trex_fossil.site_id == 9954
    assert allo_fossil.site_id == 2000


def test_sync_fails_when_collection_no_missing(session: Session):
    dinosaur = _dinosaur()
    session.add(dinosaur)
    session.commit()
    session.refresh(dinosaur)

    fossil = _fossil(occurrence_no=139292, dinosaur_id=dinosaur.id)
    fossil.collection_no = None
    session.add(fossil)
    session.commit()

    summary = sync_sites(session)
    assert summary.counters.fossils_skipped == 1
    assert site_sync_exit_code(summary) == 1
    assert fossil.site_id is None
