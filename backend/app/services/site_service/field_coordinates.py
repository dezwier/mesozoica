"""Safe land coordinate sampling for procedural field sites."""

from __future__ import annotations

import json
import logging
import random
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

from shapely.geometry import MultiPolygon, Point, shape
from shapely.geometry.base import BaseGeometry

from app.services.site_service.geo_utils import haversine_km

logger = logging.getLogger(__name__)

DEFAULT_LAND_MASK_PATH = (
    Path(__file__).resolve().parents[2] / "data" / "natural_earth_land_110m.geojson"
)


@dataclass(frozen=True)
class CoordinateSampleConfig:
    max_coordinate_attempts: int = 200
    min_separation_km: float = 1.0


@dataclass(frozen=True)
class LandMask:
    geometry: BaseGeometry
    min_lon: float
    min_lat: float
    max_lon: float
    max_lat: float

    def contains(self, lat: float, lon: float) -> bool:
        return self.geometry.contains(Point(lon, lat))

    def sample(
        self,
        *,
        existing: list[tuple[float, float]],
        config: CoordinateSampleConfig,
        rng: random.Random | None = None,
    ) -> tuple[float, float] | None:
        """Rejection-sample a land point separated from existing field coordinates."""
        random_source = rng or random
        for _ in range(config.max_coordinate_attempts):
            lon = random_source.uniform(self.min_lon, self.max_lon)
            lat = random_source.uniform(self.min_lat, self.max_lat)
            if not self.contains(lat, lon):
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
def load_land_mask(path: str | None = None) -> LandMask:
    """Load Natural Earth land polygons and return a queryable mask."""
    geojson_path = Path(path) if path else DEFAULT_LAND_MASK_PATH
    with geojson_path.open(encoding="utf-8") as handle:
        payload = json.load(handle)

    polygons: list[BaseGeometry] = []
    for feature in payload.get("features", []):
        geometry = feature.get("geometry")
        if not geometry:
            continue
        try:
            polygons.append(shape(geometry))
        except Exception:
            logger.debug("Skipping invalid land geometry feature", exc_info=True)

    if not polygons:
        raise RuntimeError(f"No land geometries loaded from {geojson_path}")

    merged: BaseGeometry
    if len(polygons) == 1:
        merged = polygons[0]
    else:
        merged = MultiPolygon([poly for poly in polygons if not poly.is_empty])

    min_lon, min_lat, max_lon, max_lat = merged.bounds
    return LandMask(
        geometry=merged,
        min_lon=min_lon,
        min_lat=min_lat,
        max_lon=max_lon,
        max_lat=max_lat,
    )
