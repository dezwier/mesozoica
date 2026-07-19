"""Tests for field coordinate filter/enrich split."""

from __future__ import annotations

import random
from pathlib import Path

import pytest
from shapely.geometry import box

from app.services.site_service.field_coordinate_enrich import CoordinateEnrichment, enrich_coordinate
from app.services.site_service.field_coordinate_filter import (
    CompositeCoordinateFilter,
    CoordinateSampleConfig,
    CoordinateSampler,
    LandPolygonFilter,
    PolygonSetFilter,
    WaterExclusionFilter,
    build_coordinate_filter,
    build_osm_coordinate_filter,
    clear_coordinate_filter_cache,
    load_land_polygon_filter,
    resolve_land_mask_path,
    warm_coordinate_filter_cache,
)


def test_polygon_set_filter_uses_spatial_index():
    land = PolygonSetFilter.from_polygons(
        [box(-1.0, -1.0, 1.0, 1.0), box(10.0, 10.0, 11.0, 11.0)],
        name="land",
        source_path="test",
    )

    assert land.allows(0.0, 0.0) is True
    assert land.allows(0.0, 5.0) is False
    assert land.allows(10.5, 10.5) is True


def test_water_exclusion_filter_rejects_water_points():
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
    filt = CompositeCoordinateFilter([land, WaterExclusionFilter(water)])

    assert filt.allows(1.5, 1.5) is True
    assert filt.allows(0.0, 0.0) is False


def test_coordinate_sampler_rejects_points_outside_filter():
    land = LandPolygonFilter.from_polygons([box(-1.0, -1.0, 1.0, 1.0)], source_path="test")
    sampler = CoordinateSampler(land)
    config = CoordinateSampleConfig(max_coordinate_attempts=50, min_separation_km=0.0)

    sample = sampler.sample(existing=[], config=config, rng=random.Random(0))

    assert sample is not None
    lat, lon = sample
    assert -1.0 <= lon <= 1.0
    assert -1.0 <= lat <= 1.0


def test_load_land_polygon_filter_is_cached():
    clear_coordinate_filter_cache()
    path = str(resolve_land_mask_path())
    first = load_land_polygon_filter(path)
    second = load_land_polygon_filter(path)
    assert first is second


def test_warm_coordinate_filter_cache_requires_osm_or_override(monkeypatch):
    monkeypatch.setattr(
        "app.services.site_service.field_coordinate_filter.osm_coordinate_masks_available",
        lambda: False,
    )
    clear_coordinate_filter_cache()
    with pytest.raises(RuntimeError, match="OSM coordinate masks required"):
        warm_coordinate_filter_cache()


def test_build_coordinate_filter_allows_land_mask_override():
    clear_coordinate_filter_cache()
    filt = build_coordinate_filter(
        land_mask_path=str(resolve_land_mask_path()),
    )
    assert filt.name == "land"
    assert isinstance(filt, LandPolygonFilter)
    assert filt.polygon_count > 1000


def test_build_osm_coordinate_filter_requires_masks(monkeypatch):
    monkeypatch.setattr(
        "app.services.site_service.field_coordinate_filter.osm_coordinate_masks_available",
        lambda: False,
    )
    clear_coordinate_filter_cache()
    with pytest.raises(RuntimeError, match="OSM coordinate masks required"):
        build_osm_coordinate_filter()


def test_enrich_coordinate_returns_structured_metadata(monkeypatch):
    monkeypatch.setattr(
        "app.services.site_service.field_coordinate_enrich.lookup_country_state",
        lambda lat, lon: ("US", "Montana"),
    )

    enrichment = enrich_coordinate(40.0, -100.0)

    assert enrichment == CoordinateEnrichment(country_code="US", state="Montana")
