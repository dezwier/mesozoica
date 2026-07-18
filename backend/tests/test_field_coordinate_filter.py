"""Tests for field coordinate filter/enrich split."""

from __future__ import annotations

import random
from pathlib import Path

from shapely.geometry import box

from app.services.site_service.field_coordinate_enrich import CoordinateEnrichment, enrich_coordinate
from app.services.site_service.field_coordinate_filter import (
    CoordinateSampleConfig,
    CoordinateSampler,
    LandPolygonFilter,
    build_coordinate_filter,
    load_land_polygon_filter,
    resolve_land_mask_path,
    warm_coordinate_filter_cache,
)


def test_land_polygon_filter_uses_spatial_index():
    land = LandPolygonFilter.from_polygons(
        [box(-1.0, -1.0, 1.0, 1.0), box(10.0, 10.0, 11.0, 11.0)],
        source_path="test",
    )

    assert land.allows(0.0, 0.0) is True
    assert land.allows(0.0, 5.0) is False
    assert land.allows(10.5, 10.5) is True


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
    load_land_polygon_filter.cache_clear()
    path = str(resolve_land_mask_path())
    first = load_land_polygon_filter(path)
    second = load_land_polygon_filter(path)
    assert first is second


def test_warm_coordinate_filter_cache_loads_default_dataset():
    load_land_polygon_filter.cache_clear()
    filt = warm_coordinate_filter_cache()
    assert filt.name == "land"
    assert isinstance(filt, LandPolygonFilter)
    assert filt.polygon_count > 1000


def test_default_land_dataset_is_10m():
    assert resolve_land_mask_path().name == "natural_earth_land_10m.geojson"
    assert resolve_land_mask_path().exists()


def test_real_land_filter_matches_known_land_and_water_points():
    land = build_coordinate_filter()

    assert land.allows(40.7128, -74.0060) is True  # Manhattan
    assert land.allows(25.0, -40.0) is False  # mid-Atlantic


def test_enrich_coordinate_returns_structured_metadata(monkeypatch):
    monkeypatch.setattr(
        "app.services.site_service.field_coordinate_enrich.lookup_country_state",
        lambda lat, lon: ("US", "Montana"),
    )

    enrichment = enrich_coordinate(40.0, -100.0)

    assert enrichment == CoordinateEnrichment(country_code="US", state="Montana")
