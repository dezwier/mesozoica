"""Tests for retroactive field-site coordinate pruning."""

from __future__ import annotations

from decimal import Decimal

from shapely.geometry import box
from sqlmodel import Session, select

from app.models.data_source import DATA_SOURCE_ARCHIVE, DATA_SOURCE_FIELD
from app.models.site import Site
from app.services.site_service.field_coordinate_filter import (
    CompositeCoordinateFilter,
    PolygonSetFilter,
    WaterExclusionFilter,
)
from app.services.site_service.field_coordinate_prune import prune_invalid_field_sites


def _field_site(*, site_id: int, lat: float, lon: float) -> Site:
    return Site(
        site_id=site_id,
        latitude=Decimal(str(lat)),
        longitude=Decimal(str(lon)),
        rock_type="sandstone",
        period="cretaceous",
        data_source=DATA_SOURCE_FIELD,
    )


def _test_filter() -> CompositeCoordinateFilter:
    land = PolygonSetFilter.from_polygons(
        [box(-2.0, -2.0, 2.0, 2.0)],
        name="land",
        source_path="test",
    )
    water = PolygonSetFilter.from_polygons(
        [box(-0.5, -0.5, 0.5, 0.5)],
        name="water",
        source_path="test",
    )
    return CompositeCoordinateFilter([land, WaterExclusionFilter(water)])


def test_prune_deletes_invalid_field_sites(session: Session, monkeypatch):
    session.add(
        Site(
            site_id=100,
            latitude=Decimal("1.5"),
            longitude=Decimal("1.5"),
            rock_type="sandstone",
            period="cretaceous",
            data_source=DATA_SOURCE_ARCHIVE,
        )
    )
    session.add(_field_site(site_id=1_000_000_001, lat=1.5, lon=1.5))
    session.add(_field_site(site_id=1_000_000_002, lat=0.0, lon=0.0))
    session.commit()

    monkeypatch.setattr(
        "app.services.site_service.field_coordinate_prune.build_osm_coordinate_filter",
        _test_filter,
    )

    summary = prune_invalid_field_sites(session, dry_run=False)

    assert summary.checked == 2
    assert summary.deleted == 1
    assert summary.kept == 1

    remaining = list(
        session.exec(select(Site).where(Site.data_source == DATA_SOURCE_FIELD)).all()
    )
    assert len(remaining) == 1
    assert float(remaining[0].latitude) == 1.5
    assert float(remaining[0].longitude) == 1.5

    archive = list(
        session.exec(select(Site).where(Site.data_source == DATA_SOURCE_ARCHIVE)).all()
    )
    assert len(archive) == 1


def test_prune_dry_run_leaves_database_unchanged(session: Session, monkeypatch):
    session.add(_field_site(site_id=1_000_000_003, lat=0.0, lon=0.0))
    session.commit()

    monkeypatch.setattr(
        "app.services.site_service.field_coordinate_prune.build_osm_coordinate_filter",
        _test_filter,
    )

    summary = prune_invalid_field_sites(session, dry_run=True)

    assert summary.deleted == 1
    remaining = list(
        session.exec(select(Site).where(Site.data_source == DATA_SOURCE_FIELD)).all()
    )
    assert len(remaining) == 1
