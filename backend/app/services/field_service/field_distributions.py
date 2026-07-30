"""Weighted geology distributions for procedural field sites."""

from __future__ import annotations

import math
import random
from collections import Counter
from dataclasses import dataclass

from app.services.site_common.geo_utils import haversine_km

PairKey = tuple[str, str]


@dataclass(frozen=True)
class ArchiveSiteRef:
    latitude: float
    longitude: float
    period: str
    rock_type: str


@dataclass(frozen=True)
class DistributionWeights:
    global_weight: float
    nearby_weight: float
    closest_weight: float

    def normalized(self) -> DistributionWeights:
        total = self.global_weight + self.nearby_weight + self.closest_weight
        if total <= 0:
            raise ValueError("distribution weights must sum to a positive value")
        return DistributionWeights(
            global_weight=self.global_weight / total,
            nearby_weight=self.nearby_weight / total,
            closest_weight=self.closest_weight / total,
        )


def build_global_distribution(sites: list[ArchiveSiteRef]) -> Counter[PairKey]:
    return Counter((site.period, site.rock_type) for site in sites)


def nearby_distribution(
    sites: list[ArchiveSiteRef],
    *,
    lat: float,
    lon: float,
    radius_km: float,
) -> Counter[PairKey]:
    counts: Counter[PairKey] = Counter()
    lat_radius = radius_km / 111.0
    cos_lat = max(abs(math.cos(math.radians(lat))), 1e-6)
    lon_radius = radius_km / (111.0 * cos_lat)
    min_lat = lat - lat_radius
    max_lat = lat + lat_radius
    min_lon = lon - lon_radius
    max_lon = lon + lon_radius

    for site in sites:
        if not (min_lat <= site.latitude <= max_lat and min_lon <= site.longitude <= max_lon):
            continue
        if haversine_km(lat, lon, site.latitude, site.longitude) <= radius_km:
            counts[(site.period, site.rock_type)] += 1
    return counts


def closest_distribution(
    sites: list[ArchiveSiteRef],
    *,
    lat: float,
    lon: float,
    neighbor_count: int,
) -> Counter[PairKey]:
    if neighbor_count <= 0 or not sites:
        return Counter()

    ranked = sorted(
        sites,
        key=lambda site: haversine_km(lat, lon, site.latitude, site.longitude),
    )
    nearest = ranked[: min(neighbor_count, len(ranked))]
    return Counter((site.period, site.rock_type) for site in nearest)


def _normalize_counter(counter: Counter[PairKey]) -> dict[PairKey, float]:
    total = sum(counter.values())
    if total <= 0:
        return {}
    return {key: value / total for key, value in counter.items()}


def blend_distributions(
    *,
    global_counts: Counter[PairKey],
    nearby_counts: Counter[PairKey],
    closest_counts: Counter[PairKey],
    weights: DistributionWeights,
) -> dict[PairKey, float]:
    """Blend three normalized distributions, redistributing inactive component weights."""
    normalized = weights.normalized()
    components: list[tuple[float, dict[PairKey, float]]] = [
        (normalized.global_weight, _normalize_counter(global_counts)),
        (normalized.nearby_weight, _normalize_counter(nearby_counts)),
        (normalized.closest_weight, _normalize_counter(closest_counts)),
    ]

    active = [(weight, probs) for weight, probs in components if probs]
    if not active:
        return _normalize_counter(global_counts)

    active_total = sum(weight for weight, _ in active)
    combined: dict[PairKey, float] = {}
    for weight, probs in active:
        scaled = weight / active_total
        for key, prob in probs.items():
            combined[key] = combined.get(key, 0.0) + scaled * prob
    return combined


def sample_pair(
    distribution: dict[PairKey, float],
    *,
    rng: random.Random | None = None,
) -> PairKey | None:
    if not distribution:
        return None
    random_source = rng or random
    keys = list(distribution.keys())
    weights = [distribution[key] for key in keys]
    return random_source.choices(keys, weights=weights, k=1)[0]
