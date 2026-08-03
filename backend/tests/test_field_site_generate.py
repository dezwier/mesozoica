"""Tests for procedural field site generation."""

from __future__ import annotations

import random
from collections import Counter
from decimal import Decimal

import pytest
from shapely.geometry import box
from sqlmodel import Session, col, select

from app.models.data_source import DATA_SOURCE_ARCHIVE, DATA_SOURCE_FIELD
from app.models.site import Site
from app.models.site_type import SiteType
from app.services.field_service.field_coordinate_filter import (
    CoordinateSampleConfig,
    CoordinateSampler,
    LandPolygonFilter,
)
from app.services.field_service.field_distributions import (
    ArchiveSiteRef,
    DistributionWeights,
    blend_distributions,
    build_global_distribution,
    closest_distribution,
    nearby_distribution,
    sample_pair,
)
from app.services.site_service.summary import site_row_to_summary
from app.services.field_service.field_generate import (
    FIELD_SITE_ID_START,
    FieldSiteGenerateConfig,
    generate_field_sites,
)


def _archive_site(
    *,
    site_id: int,
    lat: float,
    lon: float,
    period: str = "cretaceous",
    rock_type: str = "sandstone",
) -> Site:
    return Site(
        site_id=site_id,
        latitude=Decimal(str(lat)),
        longitude=Decimal(str(lon)),
        country_code="US",
        state="Montana",
        rock_type=rock_type,
        period=period,
        data_source=DATA_SOURCE_ARCHIVE,
    )


def _site_type(*, period: str, rock_type: str) -> SiteType:
    return SiteType(period=period, rock_type=rock_type)


def _test_coordinate_sampler() -> CoordinateSampler:
    geometry = box(-120.0, 30.0, -70.0, 50.0)
    land_filter = LandPolygonFilter.from_polygons([geometry], source_path="test")
    return CoordinateSampler(land_filter)


def test_blend_renormalizes_when_nearby_empty():
    sites = [
        ArchiveSiteRef(latitude=40.0, longitude=-100.0, period="cretaceous", rock_type="sandstone"),
        ArchiveSiteRef(latitude=41.0, longitude=-101.0, period="jurassic", rock_type="mudstone"),
    ]
    global_counts = build_global_distribution(sites)
    nearby_counts = nearby_distribution(
        sites,
        lat=0.0,
        lon=0.0,
        radius_km=1.0,
    )
    closest_counts = closest_distribution(
        sites,
        lat=0.0,
        lon=0.0,
        neighbor_count=1,
    )

    blended = blend_distributions(
        global_counts=global_counts,
        nearby_counts=nearby_counts,
        closest_counts=closest_counts,
        weights=DistributionWeights(
            global_weight=0.25,
            nearby_weight=0.50,
            closest_weight=0.25,
        ),
    )

    assert sum(nearby_counts.values()) == 0
    assert sum(blended.values()) == pytest.approx(1.0)
    assert ("cretaceous", "sandstone") in blended


def test_sample_pair_respects_weights():
    distribution = {
        ("cretaceous", "sandstone"): 0.9,
        ("jurassic", "mudstone"): 0.1,
    }
    rng = random.Random(0)
    draws = Counter(sample_pair(distribution, rng=rng) for _ in range(1000))
    assert draws[("cretaceous", "sandstone")] > draws[("jurassic", "mudstone")]


def test_generate_field_sites_dry_run(session: Session, monkeypatch):
    session.add(_site_type(period="cretaceous", rock_type="sandstone"))
    session.add(_site_type(period="jurassic", rock_type="mudstone"))
    session.add(_archive_site(site_id=100, lat=40.0, lon=-100.0))
    session.add(_archive_site(site_id=101, lat=41.0, lon=-101.0, period="jurassic", rock_type="mudstone"))
    session.commit()


    config = FieldSiteGenerateConfig(max_items=3, refresh=False)
    summary = generate_field_sites(
        session,
        config=config,
        dry_run=True,
        rng=random.Random(42),
        coordinate_sampler=_test_coordinate_sampler(),
    )

    assert summary.counters.generated == 3
    assert summary.dry_run is True
    assert session.exec(select(Site).where(Site.data_source == DATA_SOURCE_FIELD)).first() is None


def test_generate_field_sites_append_and_refresh(session: Session, monkeypatch):
    session.add(_site_type(period="cretaceous", rock_type="sandstone"))
    session.add(_archive_site(site_id=100, lat=40.0, lon=-100.0))
    session.add(
        Site(
            site_id=FIELD_SITE_ID_START,
            latitude=Decimal("40.100000"),
            longitude=Decimal("-100.100000"),
            rock_type="sandstone",
            period="cretaceous",
            data_source=DATA_SOURCE_FIELD,
        )
    )
    session.commit()


    append_summary = generate_field_sites(
        session,
        config=FieldSiteGenerateConfig(max_items=2, refresh=False),
        dry_run=False,
        rng=random.Random(7),
        coordinate_sampler=_test_coordinate_sampler(),
    )
    assert append_summary.counters.generated == 2
    field_sites = list(session.exec(select(Site).where(Site.data_source == DATA_SOURCE_FIELD)).all())
    assert len(field_sites) == 3

    refresh_summary = generate_field_sites(
        session,
        config=FieldSiteGenerateConfig(max_items=1, refresh=True),
        dry_run=False,
        rng=random.Random(8),
        coordinate_sampler=_test_coordinate_sampler(),
    )
    assert refresh_summary.counters.deleted_on_refresh == 3
    assert refresh_summary.counters.generated == 1
    field_sites = list(session.exec(select(Site).where(Site.data_source == DATA_SOURCE_FIELD)).all())
    assert len(field_sites) == 1
    assert field_sites[0].site_id >= FIELD_SITE_ID_START

    archive_sites = list(session.exec(select(Site).where(Site.data_source == DATA_SOURCE_ARCHIVE)).all())
    assert len(archive_sites) == 1


def test_generate_field_sites_sets_expected_fields(session: Session, monkeypatch):
    site_type = _site_type(period="cretaceous", rock_type="sandstone")
    session.add(site_type)
    session.add(_archive_site(site_id=100, lat=40.0, lon=-100.0))
    session.commit()
    session.refresh(site_type)

    generate_field_sites(
        session,
        config=FieldSiteGenerateConfig(max_items=1, refresh=True),
        dry_run=False,
        rng=random.Random(1),
        coordinate_sampler=_test_coordinate_sampler(),
    )

    site = session.exec(select(Site).where(Site.data_source == DATA_SOURCE_FIELD)).first()
    assert site is not None
    assert site.data_source == DATA_SOURCE_FIELD
    # Country/state deferred until discovery.
    assert site.country_code is None
    assert site.state is None
    assert site.how_discovered is None
    assert site.period == "cretaceous"
    assert site.rock_type == "sandstone"
    assert site.site_type_id == site_type.id
    assert site.formation is None
    assert site.min_age_ma is None
    assert site.max_age_ma is None
    assert site.odd_dino_count is not None and 0.0 <= site.odd_dino_count <= 1.0
    assert site.odd_fossil_count is not None and 0.0 <= site.odd_fossil_count <= 1.0
    assert site.odd_completeness is not None and 0.0 <= site.odd_completeness <= 1.0
    assert site.odd_quality is not None and 0.0 <= site.odd_quality <= 1.0
    assert site.odd_depth is not None and 0.0 <= site.odd_depth <= 1.0

    from app.services.site_service.list import get_site_by_id

    row = get_site_by_id(session, site.site_id, data_source=DATA_SOURCE_FIELD)
    assert row.status == "hidden"
    summary = site_row_to_summary(row)
    assert summary.odd_dino_count is None
    assert summary.odd_depth is None
    assert summary.odd_dino_band is not None
    assert summary.odd_depth_band is not None
    exact = site_row_to_summary(row, include_exact_odds=True)
    assert exact.odd_dino_count == site.odd_dino_count
    assert exact.odd_depth == site.odd_depth
    assert summary.how_discovered is None


def test_coordinate_sampler_respects_min_separation():
    sampler = _test_coordinate_sampler()
    config = CoordinateSampleConfig(max_coordinate_attempts=20, min_separation_km=10_000.0)
    first = sampler.sample(existing=[], config=config, rng=random.Random(1))
    second = sampler.sample(existing=[first] if first else [], config=config, rng=random.Random(2))
    assert first is not None
    assert second is None
