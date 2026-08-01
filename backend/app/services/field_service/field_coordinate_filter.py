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

from app.services.field_service.field_coordinate_geodata import (
    flatten_polygons,
    read_shapefile_polygons,
)
from app.services.site_common.geo_utils import haversine_km

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

    def sample_in_square(
        self,
        *,
        south: float,
        north: float,
        west: float,
        east: float,
        existing: list[tuple[float, float]],
        config: CoordinateSampleConfig,
        rng: random.Random | None = None,
    ) -> tuple[float, float] | None:
        """Uniform sample inside an axis-aligned lat/lon square (legacy helper)."""
        random_source = rng or random
        lo_lat, hi_lat = min(south, north), max(south, north)
        lo_lon, hi_lon = min(west, east), max(west, east)
        if hi_lat <= lo_lat or hi_lon <= lo_lon:
            return None
        for _ in range(config.max_coordinate_attempts):
            lat = random_source.uniform(lo_lat, hi_lat)
            lon = random_source.uniform(lo_lon, hi_lon)
            if not self.filter.allows(lat, lon):
                continue
            if _too_close(lat, lon, existing, config.min_separation_km):
                continue
            return lat, lon
        return None

    def sample_in_cell(
        self,
        *,
        ix: int,
        iy: int,
        cell_size_m: float,
        existing: list[tuple[float, float]],
        config: CoordinateSampleConfig,
        rng: random.Random | None = None,
    ) -> tuple[float, float] | None:
        """Uniform sample inside the meter-space density square ``(ix, iy)``.

        Sampling in projected meters (not lat/lon) keeps sites inside the true
        cell; a lat/lon AABB overshoots curved lon edges into neighbor cells.
        """
        from app.services.site_common.survey_grid import (
            cell_meter_bounds,
            meters_to_latlon,
        )

        random_source = rng or random
        x0, x1, y0, y1 = cell_meter_bounds(ix, iy, cell_size_m=cell_size_m)
        # Keep samples in the half-open cell [x0, x1) × [y0, y1).
        eps = min(1e-3, (x1 - x0) * 1e-9)
        for _ in range(config.max_coordinate_attempts):
            x = random_source.uniform(x0, x1 - eps)
            y = random_source.uniform(y0, y1 - eps)
            lat, lon = meters_to_latlon(x, y)
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


@lru_cache(maxsize=1)
def resolve_coordinate_data_dir() -> Path:
    override = os.getenv("FIELD_COORDINATE_DATA_DIR")
    if override:
        configured = Path(override)
        if _osm_masks_available_at(configured):
            return configured
        if configured != DEFAULT_DATA_DIR and _osm_masks_available_at(DEFAULT_DATA_DIR):
            logger.info(
                "OSM coordinate masks not found under %s/osm; using %s/osm",
                configured,
                DEFAULT_DATA_DIR,
            )
            return DEFAULT_DATA_DIR
        return configured
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


def _osm_masks_available_at(data_dir: Path) -> bool:
    land_dir = data_dir / "osm" / "land"
    water_dir = data_dir / "osm" / "water"
    try:
        _find_shapefile(land_dir)
        _find_shapefile(water_dir)
    except FileNotFoundError:
        return False
    return True


def osm_coordinate_masks_available() -> bool:
    return _osm_masks_available_at(resolve_coordinate_data_dir())


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


def build_osm_coordinate_filter() -> CoordinateFilter:
    """Build the production OSM land + water filter stack."""
    if not osm_coordinate_masks_available():
        data_root = resolve_coordinate_data_dir()
        raise RuntimeError(
            f"OSM coordinate masks required but missing under {data_root / 'osm'}"
        )
    land_filter = load_osm_land_filter(str(resolve_osm_land_dir()))
    water_filter = load_osm_water_exclusion_filter(str(resolve_osm_water_dir()))
    return CompositeCoordinateFilter([land_filter, water_filter])


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

    return build_osm_coordinate_filter()


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
    if land_mask_path:
        return load_land_polygon_filter(str(resolve_land_mask_path(land_mask_path)))
    return build_osm_coordinate_filter()


def _fetch_osm_masks_enabled() -> bool:
    value = os.getenv("FETCH_OSM_COORDINATE_MASKS", "true").strip().lower()
    return value not in {"0", "false", "no", "off"}


def ensure_osm_coordinate_masks_on_disk() -> None:
    """Download OSM shapefiles when missing (worker startup / volume first boot)."""
    if osm_coordinate_masks_available():
        logger.info("OSM coordinate masks already present under %s/osm", resolve_coordinate_data_dir())
        return
    if not _fetch_osm_masks_enabled():
        data_dir = resolve_coordinate_data_dir()
        hint = ""
        if data_dir != DEFAULT_DATA_DIR and not _osm_masks_available_at(DEFAULT_DATA_DIR):
            hint = " Run `make fetch-coordinate-masks` locally first."
        raise RuntimeError(
            f"OSM coordinate masks missing under {data_dir / 'osm'}"
            " and FETCH_OSM_COORDINATE_MASKS is disabled."
            f"{hint}"
        )

    from scripts.fetch_osm_coordinate_masks import run_fetch

    data_dir = resolve_coordinate_data_dir() / "osm"
    simplify = float(os.getenv("OSM_SIMPLIFY_TOLERANCE", "0.0001"))
    logger.info(
        "OSM coordinate masks missing; fetching into %s (simplify=%s)",
        data_dir,
        simplify,
    )
    run_fetch(data_dir=data_dir, simplify_tolerance=simplify, force=False)
    if not osm_coordinate_masks_available():
        raise RuntimeError(
            f"OSM coordinate mask fetch completed but files are still missing under {data_dir}"
        )


def clear_coordinate_filter_cache() -> None:
    """Clear cached polygon filters (mainly for tests)."""
    resolve_coordinate_data_dir.cache_clear()
    load_osm_land_filter.cache_clear()
    load_osm_water_exclusion_filter.cache_clear()
    load_land_polygon_filter.cache_clear()
