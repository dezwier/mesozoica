"""Tests for site_type table sync orchestration."""

from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal

from sqlmodel import Session, select

from app.models.dinosaur import Dinosaur
from app.models.fossil import Fossil
from app.models.site import Site
from app.models.site_type import SiteType
from app.services.site_service.site_type_sync import sync_site_types
from app.services.site_service.sync import sync_sites


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
        lithology1="sandstone",
    )


def test_site_type_sync_builds_types_and_assigns_site(session: Session):
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

    sync_sites(session)
    summary = sync_site_types(session)

    sites = list(session.exec(select(Site)).all())
    site_types = list(session.exec(select(SiteType)).all())

    assert summary.counters.site_types_written == 1
    assert summary.counters.sites_updated == 2
    assert len(site_types) == 1
    assert site_types[0].period == "cretaceous"
    assert site_types[0].rock_type == "sandstone"

    site_row = next(row for row in sites if row.site_id == 9954)
    assert site_row.site_type_id == site_types[0].id


def test_site_type_sync_dry_run_writes_nothing(session: Session):
    dinosaur = _dinosaur()
    session.add(dinosaur)
    session.commit()
    session.refresh(dinosaur)
    session.add(_fossil(occurrence_no=139292, dinosaur_id=dinosaur.id))
    session.commit()
    sync_sites(session)

    summary = sync_site_types(session, dry_run=True)

    assert summary.dry_run is True
    assert list(session.exec(select(SiteType)).all()) == []
    site = session.exec(select(Site).where(Site.site_id == 9954)).one()
    assert site.site_type_id is None


def test_site_type_sync_preserves_main_image_url_on_full_refresh(session: Session):
    dinosaur = _dinosaur()
    session.add(dinosaur)
    session.commit()
    session.refresh(dinosaur)
    session.add(_fossil(occurrence_no=139292, dinosaur_id=dinosaur.id))
    session.commit()
    sync_sites(session)

    first = sync_site_types(session)
    site_type = session.exec(select(SiteType)).one()
    site_type.main_image_url = (
        "https://example.com/media/site-types/cretaceous_sandstone.png?v=abc"
    )
    session.add(site_type)
    session.commit()

    sync_site_types(session)

    refreshed = session.exec(select(SiteType)).one()
    assert refreshed.main_image_url == (
        "https://example.com/media/site-types/cretaceous_sandstone.png?v=abc"
    )
    assert refreshed.period == "cretaceous"
    assert refreshed.rock_type == "sandstone"


def test_site_type_sync_partial_dino_filter(session: Session):
    trex = _dinosaur(name="Tyrannosaurus", page_id=30467)
    allo = _dinosaur(name="Allosaurus", page_id=30468)
    session.add(trex)
    session.add(allo)
    session.commit()
    session.refresh(trex)
    session.refresh(allo)

    session.add(_fossil(occurrence_no=139292, dinosaur_id=trex.id))
    allo_fossil = _fossil(
        occurrence_no=200001,
        dinosaur_id=allo.id,
        collection_no=2000,
        name="Allosaurus fragilis",
    )
    allo_fossil.lithology1 = "mudstone"
    session.add(allo_fossil)
    session.commit()

    sync_sites(session)
    sync_site_types(session)
    sync_site_types(session, dinos=["Tyrannosaurus"])

    site_types = list(session.exec(select(SiteType)).all())
    assert len(site_types) == 2
    trex_site = session.exec(select(Site).where(Site.site_id == 9954)).one()
    allo_site = session.exec(select(Site).where(Site.site_id == 2000)).one()
    assert trex_site.site_type_id is not None
    assert allo_site.site_type_id is not None
