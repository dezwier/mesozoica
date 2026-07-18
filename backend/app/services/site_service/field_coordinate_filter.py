"""Fast offline coordinate filters for procedural field-site sampling."""

from __future__ import annotations

import json
import logging
import math
import random
import time
from collections.abc import Sequence
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Protocol, runtime_checkable

from shapely.geometry import Point, shape
from shapely.geometry.base import BaseGeometry
from shapely.strtree import STRtree

from app.services.site_service.geo_utils import haversine_km

logger = logging.getLogger(__name__)

DEFAULT_LAND_MASK_PATH = (
    Path(__file__).resolve().parents[2] / "data" / "natural_earth_land_10m.geojson"
)


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


class LandPolygonFilter:
    """On-land check using preloaded polygons and a spatial index."""

    name = "land"

    def __init__(
        self,
        *,
        polygons: Sequence[BaseGeometry],
        source_path: Path,
    ) -> None:
        if not polygons:
            raise ValueError("LandPolygonFilter requires at least one polygon")
        self._polygons = list(polygons)
        self._spatial_index = STRtree(self._polygons)
        self.source_path = source_path
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
        source_path: Path | str = "inline",
    ) -> LandPolygonFilter:
        return cls(polygons=polygons, source_path=Path(source_path))

    @property
    def polygon_count(self) -> int:
        return len(self._polygons)

    @property
    def bounds(self) -> tuple[float, float, float, float]:
        return self._bounds

    def allows(self, lat: float, lon: float) -> bool:
        point = Point(lon, lat)
        indices = self._spatial_index.query(point, predicate="within")
        return len(indices) > 0


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
        min_lon = max(f.bounds[0] for f in self._filters)
        min_lat = max(f.bounds[1] for f in self._filters)
        max_lon = min(f.bounds[2] for f in self._filters)
        max_lat = min(f.bounds[3] for f in self._filters)
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


def resolve_land_mask_path(path: str | None = None) -> Path:
    if path:
        return Path(path)
    return DEFAULT_LAND_MASK_PATH


def _flatten_land_polygons(geometry: BaseGeometry) -> list[BaseGeometry]:
    if geometry.is_empty:
        return []
    if geometry.geom_type == "Polygon":
        return [geometry]
    if geometry.geom_type == "MultiPolygon":
        return [polygon for polygon in geometry.geoms if not polygon.is_empty]
    return []


@lru_cache(maxsize=4)
def load_land_polygon_filter(resolved_path: str) -> LandPolygonFilter:
    """Load land polygons once per process and cache in memory."""
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
            polygons.extend(_flatten_land_polygons(shape(geometry)))
        except Exception:
            logger.debug("Skipping invalid land geometry feature", exc_info=True)

    if not polygons:
        raise RuntimeError(f"No land geometries loaded from {geojson_path}")

    land_filter = LandPolygonFilter(polygons=polygons, source_path=geojson_path)
    elapsed_s = time.monotonic() - started
    logger.info(
        "Loaded land polygon filter path=%s polygons=%d elapsed_s=%.2f",
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
    land_filter = load_land_polygon_filter(str(resolve_land_mask_path(land_mask_path)))
    filters: list[CoordinateFilter] = [land_filter]
    if exclude_military:
        logger.warning(
            "exclude_military=true is not implemented yet; using land-only filter"
        )
    if len(filters) == 1:
        return filters[0]
    return CompositeCoordinateFilter(filters)


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
    """Eager-load the land filter so the first request avoids disk/parse cost."""
    return build_coordinate_filter(land_mask_path=land_mask_path)
