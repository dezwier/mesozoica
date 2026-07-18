"""Fast offline coordinate filters for procedural field-site sampling."""

from __future__ import annotations

import json
import logging
import math
import os
import random
import time
from collections.abc import Sequence
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Protocol, runtime_checkable

from shapely.geometry import MultiPolygon, Point, shape
from shapely.geometry.base import BaseGeometry
from shapely.strtree import STRtree

from app.services.site_service.field_coordinate_geodata import (
    flatten_polygons,
    read_shapefile_polygons,
)
from app.services.site_service.geo_utils import haversine_km

logger = logging.getLogger(__name__)

DEFAULT_DATA_DIR = Path(__file__).resolve().parents[2] / "data"
DEFAULT_LAND_MASK_PATH = DEFAULT_DATA_DIR / "natural_earth_land_10m.geojson"
DEFAULT_OSM_DIR = DEFAULT_DATA_DIR / "osm"
OSM_LAND_DIR = DEFAULT_OSM_DIR / "land"
OSM_WATER_DIR = DEFAULT_OSM_DIR / "water"


@dataclass(frozen=True)
class CoordinateSampleConfig:
    max_coordinate_attempts: int = 200
    min_separation_km: float = 0.01


@runtime_checkable
class CoordinateFilter(Protocol):
    """Offline rule evaluated during rejection sampling."""

    @property
    def name(self) -> str: ...

    @property
    def bounds(self) -> tuple[float, float, float, float]:
        """Return ``(min_lon, min_lat, max_lon, max_lat)``."""

    def allows(self, lat: float, lon: float) -> bool: ...


class PolygonSetFilter:
    """Point-in-polygon check against a preloaded polygon set."""

    def __init__(
        self,
        *,
        name: str,
        polygons: Sequence[BaseGeometry],
        source_path: Path | str,
    ) -> None:
        if not polygons:
            raise ValueError(f"{name} filter requires at least one polygon")
        self.name = name
        self._polygons = list(polygons)
        self._spatial_index = STRtree(self._polygons)
        self.source_path = Path(source_path)
        min_lon = min_lat = float("inf")
        max_lon = max_lat = float("-inf")
        for polygon in self._polygons:
            west, south, east, north = polygon.bounds
            min_lon = min(min_lon, west)
            min_lat = min(min_lat, south)
            max_lon = max(max_lon, east)
            max_lat = max(max_lat, north)
        self._bounds = (min_lon, min_lat, max_lon, max_lat)

    @classmethod
    def from_polygons(
        cls,
        polygons: Sequence[BaseGeometry],
        *,
        name: str = "land",
        source_path: Path | str = "inline",
    ) -> PolygonSetFilter:
        return cls(name=name, polygons=polygons, source_path=source_path)

    @property
    def polygon_count(self) -> int:
        return len(self._polygons)

    @property
    def bounds(self) -> tuple[float, float, float, float]:
        return self._bounds

    def contains(self, lat: float, lon: float) -> bool:
        point = Point(lon, lat)
        indices = self._spatial_index.query(point, predicate="within")
        return len(indices) > 0

    def allows(self, lat: float, lon: float) -> bool:
        return self.contains(lat, lon)


class LandPolygonFilter(PolygonSetFilter):
    """On-land check using preloaded polygons and a spatial index."""

    def __init__(
        self,
        *,
        polygons: Sequence[BaseGeometry],
        source_path: Path | str,
    ) -> None:
        super().__init__(name="land", polygons=polygons, source_path=source_path)

    @classmethod
    def from_polygons(
        cls,
        polygons: Sequence[BaseGeometry],
        *,
        source_path: Path | str = "inline",
    ) -> LandPolygonFilter:
        return cls(polygons=polygons, source_path=source_path)


class WaterExclusionFilter:
    """Reject coordinates that fall inside OSM water polygons."""

    name = "not_water"

    def __init__(self, water_polygons: PolygonSetFilter) -> None:
        self._water = water_polygons

    @property
    def bounds(self) -> tuple[float, float, float, float]:
        return self._water.bounds

    def allows(self, lat: float, lon: float) -> bool:
        return not self._water.contains(lat, lon)


class CompositeCoordinateFilter:
    """Run multiple offline filters; all must pass."""

    name = "composite"

    def __init__(self, filters: Sequence[CoordinateFilter]) -> None:
        if not filters:
            raise ValueError("CompositeCoordinateFilter requires at least one filter")
        self._filters = list(filters)

    @property
    def filters(self) -> tuple[CoordinateFilter, ...]:
        return tuple(self._filters)

    @property
    def bounds(self) -> tuple[float, float, float, float]:
        min_lon = max(item.bounds[0] for item in self._filters)
        min_lat = max(item.bounds[1] for item in self._filters)
        max_lon = min(item.bounds[2] for item in self._filters)
        max_lat = min(item.bounds[3] for item in self._filters)
        return min_lon, min_lat, max_lon, max_lat

    def allows(self, lat: float, lon: float) -> bool:
        return all(item.allows(lat, lon) for item in self._filters)


class CoordinateSampler:
    """Rejection-sample coordinates that pass a filter stack."""

    def __init__(self, coordinate_filter: CoordinateFilter) -> None:
        self.filter = coordinate_filter
        self.min_lon, self.min_lat, self.max_lon, self.max_lat = coordinate_filter.bounds

    def sample(
        self,
        *,
        existing: list[tuple[float, float]],
        config: CoordinateSampleConfig,
        rng: random.Random | None = None,
    ) -> tuple[float, float] | None:
        random_source = rng or random
        for _ in range(config.max_coordinate_attempts):
            lon = random_source.uniform(self.min_lon, self.max_lon)
            lat = random_source.uniform(self.min_lat, self.max_lat)
            if not self.filter.allows(lat, lon):
                continue
            if _too_close(lat, lon, existing, config.min_separation_km):
                continue
            return lat, lon
        return None

    def sample_in_radius(
        self,
        *,
        center_lat: float,
        center_lon: float,
        radius_km: float,
        existing: list[tuple[float, float]],
        config: CoordinateSampleConfig,
        rng: random.Random | None = None,
    ) -> tuple[float, float] | None:
        random_source = rng or random
        cos_lat = max(abs(math.cos(math.radians(center_lat))), 1e-6)
        for _ in range(config.max_coordinate_attempts):
            angle = random_source.uniform(0, 2 * math.pi)
            distance_km = radius_km * math.sqrt(random_source.uniform(0, 1))
            lat = center_lat + (distance_km / 111.0) * math.cos(angle)
            lon = center_lon + (distance_km / (111.0 * cos_lat)) * math.sin(angle)
            if not self.filter.allows(lat, lon):
                continue
            if _too_close(lat, lon, existing, config.min_separation_km):
                continue
            return lat, lon
        return None


def _too_close(
    lat: float,
    lon: float,
    existing: list[tuple[float, float]],
    min_separation_km: float,
) -> bool:
    for other_lat, other_lon in existing:
        if haversine_km(lat, lon, other_lat, other_lon) < min_separation_km:
            return True
    return False


def resolve_coordinate_data_dir() -> Path:
    override = os.getenv("FIELD_COORDINATE_DATA_DIR")
    if override:
        return Path(override)
    return DEFAULT_DATA_DIR


def resolve_land_mask_path(path: str | None = None) -> Path:
    if path:
        return Path(path)
    return DEFAULT_LAND_MASK_PATH


def resolve_osm_land_dir() -> Path:
    return resolve_coordinate_data_dir() / "osm" / "land"


def resolve_osm_water_dir() -> Path:
    return resolve_coordinate_data_dir() / "osm" / "water"


def _flatten_polygons(geometry: BaseGeometry) -> list[BaseGeometry]:
    return flatten_polygons(geometry)


def _find_shapefile(directory: Path) -> Path:
    matches = sorted(directory.glob("*.shp"))
    if not matches:
        raise FileNotFoundError(f"No .shp files found in {directory}")
    return matches[0]


def _load_shapefile_polygons(shapefile_path: Path) -> list[BaseGeometry]:
    return read_shapefile_polygons(shapefile_path)


def osm_coordinate_masks_available() -> bool:
    land_dir = resolve_osm_land_dir()
    water_dir = resolve_osm_water_dir()
    try:
        _find_shapefile(land_dir)
        _find_shapefile(water_dir)
    except FileNotFoundError:
        return False
    return True


@lru_cache(maxsize=4)
def load_osm_land_filter(resolved_land_dir: str) -> PolygonSetFilter:
    """Load OSM land polygons once per process and cache in memory."""
    land_dir = Path(resolved_land_dir)
    shapefile_path = _find_shapefile(land_dir)
    started = time.monotonic()
    polygons = _load_shapefile_polygons(shapefile_path)
    land_filter = PolygonSetFilter(
        name="osm_land",
        polygons=polygons,
        source_path=shapefile_path,
    )
    logger.info(
        "Loaded OSM land filter path=%s polygons=%d elapsed_s=%.2f",
        shapefile_path,
        land_filter.polygon_count,
        time.monotonic() - started,
    )
    return land_filter


@lru_cache(maxsize=4)
def load_osm_water_exclusion_filter(resolved_water_dir: str) -> WaterExclusionFilter:
    """Load OSM water polygons once per process and cache in memory."""
    water_dir = Path(resolved_water_dir)
    shapefile_path = _find_shapefile(water_dir)
    started = time.monotonic()
    polygons = _load_shapefile_polygons(shapefile_path)
    water_polygons = PolygonSetFilter(
        name="osm_water",
        polygons=polygons,
        source_path=shapefile_path,
    )
    water_filter = WaterExclusionFilter(water_polygons)
    logger.info(
        "Loaded OSM water exclusion filter path=%s polygons=%d elapsed_s=%.2f",
        shapefile_path,
        water_polygons.polygon_count,
        time.monotonic() - started,
    )
    return water_filter


@lru_cache(maxsize=4)
def load_land_polygon_filter(resolved_path: str) -> LandPolygonFilter:
    """Load Natural Earth land polygons once per process and cache in memory."""
    geojson_path = Path(resolved_path)
    started = time.monotonic()
    with geojson_path.open(encoding="utf-8") as handle:
        payload = json.load(handle)

    polygons: list[BaseGeometry] = []
    for feature in payload.get("features", []):
        geometry = feature.get("geometry")
        if not geometry:
            continue
        try:
            polygons.extend(_flatten_polygons(shape(geometry)))
        except Exception:
            logger.debug("Skipping invalid land geometry feature", exc_info=True)

    if not polygons:
        raise RuntimeError(f"No land geometries loaded from {geojson_path}")

    merged: BaseGeometry
    if len(polygons) == 1:
        merged = polygons[0]
    else:
        merged = MultiPolygon([polygon for polygon in polygons if not polygon.is_empty])
        polygons = _flatten_polygons(merged)

    land_filter = LandPolygonFilter(polygons=polygons, source_path=geojson_path)
    elapsed_s = time.monotonic() - started
    logger.info(
        "Loaded Natural Earth land filter path=%s polygons=%d elapsed_s=%.2f",
        geojson_path,
        land_filter.polygon_count,
        elapsed_s,
    )
    return land_filter


def build_coordinate_filter(
    *,
    land_mask_path: str | None = None,
    exclude_military: bool = False,
) -> CoordinateFilter:
    """Build the offline filter stack used during coordinate sampling."""
    if exclude_military:
        logger.warning(
            "exclude_military=true is not implemented yet; using land/water filters only"
        )

    if land_mask_path:
        return load_land_polygon_filter(str(resolve_land_mask_path(land_mask_path)))

    if osm_coordinate_masks_available():
        land_filter = load_osm_land_filter(str(resolve_osm_land_dir()))
        water_filter = load_osm_water_exclusion_filter(str(resolve_osm_water_dir()))
        return CompositeCoordinateFilter([land_filter, water_filter])

    logger.warning(
        "OSM coordinate masks not found under %s; falling back to Natural Earth land",
        resolve_osm_land_dir().parent,
    )
    return load_land_polygon_filter(str(resolve_land_mask_path(None)))


def build_coordinate_sampler(
    *,
    land_mask_path: str | None = None,
    exclude_military: bool = False,
    coordinate_filter: CoordinateFilter | None = None,
) -> CoordinateSampler:
    filt = coordinate_filter or build_coordinate_filter(
        land_mask_path=land_mask_path,
        exclude_military=exclude_military,
    )
    return CoordinateSampler(filt)


def warm_coordinate_filter_cache(*, land_mask_path: str | None = None) -> CoordinateFilter:
    """Eager-load coordinate filters so the first request avoids disk/parse cost."""
    return build_coordinate_filter(land_mask_path=land_mask_path)


def clear_coordinate_filter_cache() -> None:
    """Clear cached polygon filters (mainly for tests)."""
    load_osm_land_filter.cache_clear()
    load_osm_water_exclusion_filter.cache_clear()
    load_land_polygon_filter.cache_clear()
