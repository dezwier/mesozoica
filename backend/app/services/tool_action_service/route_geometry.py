"""Route geometry helpers for tool-action missions."""

from __future__ import annotations

from dataclasses import dataclass

from app.services.site_service.geo_utils import haversine_km


@dataclass(frozen=True)
class RoutePoint:
    lat: float
    lon: float


def route_length_km(points: list[RoutePoint]) -> float:
    if len(points) < 2:
        return 0.0
    total = 0.0
    for i in range(1, len(points)):
        total += haversine_km(
            points[i - 1].lat,
            points[i - 1].lon,
            points[i].lat,
            points[i].lon,
        )
    return total


def point_at_fraction(points: list[RoutePoint], fraction: float) -> RoutePoint:
    """Return the point at [fraction] of total arc length (0..1)."""
    if not points:
        raise ValueError("route must not be empty")
    if len(points) == 1:
        return points[0]
    frac = min(1.0, max(0.0, fraction))
    total = route_length_km(points)
    if total <= 0:
        return points[0]
    target = total * frac
    traveled = 0.0
    for i in range(1, len(points)):
        a = points[i - 1]
        b = points[i]
        seg = haversine_km(a.lat, a.lon, b.lat, b.lon)
        if seg <= 0:
            continue
        if traveled + seg >= target:
            t = (target - traveled) / seg
            return RoutePoint(
                lat=a.lat + (b.lat - a.lat) * t,
                lon=a.lon + (b.lon - a.lon) * t,
            )
        traveled += seg
    return points[-1]


def prefix_up_to_fraction(
    points: list[RoutePoint], fraction: float
) -> list[RoutePoint]:
    """Vertices from start up to [fraction], ending at the interpolated point.

    Fraction 0 returns ``[start]``. Fraction 1 returns a copy of the full route.
    """
    if not points:
        raise ValueError("route must not be empty")
    if len(points) == 1:
        return [points[0]]
    frac = min(1.0, max(0.0, fraction))
    if frac <= 0:
        return [points[0]]
    if frac >= 1:
        return list(points)

    total = route_length_km(points)
    if total <= 0:
        return [points[0]]

    target = total * frac
    prefix: list[RoutePoint] = [points[0]]
    traveled = 0.0
    for i in range(1, len(points)):
        a = points[i - 1]
        b = points[i]
        seg = haversine_km(a.lat, a.lon, b.lat, b.lon)
        if seg <= 0:
            continue
        if traveled + seg >= target:
            t = (target - traveled) / seg
            end = RoutePoint(
                lat=a.lat + (b.lat - a.lat) * t,
                lon=a.lon + (b.lon - a.lon) * t,
            )
            # Avoid duplicating when we land exactly on a vertex.
            if end != a:
                prefix.append(end)
            return prefix
        prefix.append(b)
        traveled += seg
    return list(points)


def sample_along_route(
    points: list[RoutePoint],
    *,
    spacing_km: float,
) -> list[RoutePoint]:
    """Sample points every ``spacing_km`` along the polyline (includes endpoints)."""
    if not points:
        return []
    if len(points) == 1 or spacing_km <= 0:
        return [points[0]]

    samples: list[RoutePoint] = [points[0]]
    next_at = spacing_km
    traveled = 0.0

    for i in range(1, len(points)):
        a = points[i - 1]
        b = points[i]
        seg = haversine_km(a.lat, a.lon, b.lat, b.lon)
        if seg <= 0:
            continue
        while traveled + seg >= next_at:
            t = (next_at - traveled) / seg
            samples.append(
                RoutePoint(
                    lat=a.lat + (b.lat - a.lat) * t,
                    lon=a.lon + (b.lon - a.lon) * t,
                )
            )
            next_at += spacing_km
        traveled += seg

    if samples[-1] != points[-1]:
        samples.append(points[-1])
    return samples


def point_to_route_distance_km(
    point: RoutePoint,
    route: list[RoutePoint],
) -> tuple[float, float, RoutePoint]:
    """Return (min distance km, arclength to closest point, closest point on route)."""
    if not route:
        raise ValueError("route must not be empty")
    if len(route) == 1:
        d = haversine_km(point.lat, point.lon, route[0].lat, route[0].lon)
        return d, 0.0, route[0]

    best_dist = float("inf")
    best_along = 0.0
    best_point = route[0]
    along = 0.0

    for i in range(1, len(route)):
        a = route[i - 1]
        b = route[i]
        seg = haversine_km(a.lat, a.lon, b.lat, b.lon)
        if seg <= 0:
            continue
        # Project in local equirectangular metres for a stable closest-point.
        ax, ay = _to_local_m(a.lat, a.lon, a.lat)
        bx, by = _to_local_m(b.lat, b.lon, a.lat)
        px, py = _to_local_m(point.lat, point.lon, a.lat)
        abx, aby = bx - ax, by - ay
        apx, apy = px - ax, py - ay
        ab2 = abx * abx + aby * aby
        t = 0.0 if ab2 <= 0 else max(0.0, min(1.0, (apx * abx + apy * aby) / ab2))
        cx = ax + abx * t
        cy = ay + aby * t
        clat, clon = _from_local_m(cx, cy, a.lat, a.lon)
        candidate = RoutePoint(lat=clat, lon=clon)
        dist = haversine_km(point.lat, point.lon, candidate.lat, candidate.lon)
        if dist < best_dist:
            best_dist = dist
            best_along = along + seg * t
            best_point = candidate
        along += seg

    return best_dist, best_along, best_point


def _to_local_m(lat: float, lon: float, origin_lat: float) -> tuple[float, float]:
    import math

    metres_per_deg_lat = 111_320.0
    metres_per_deg_lon = 111_320.0 * math.cos(math.radians(origin_lat))
    return lon * metres_per_deg_lon, lat * metres_per_deg_lat


def _from_local_m(
    x: float, y: float, origin_lat: float, origin_lon: float
) -> tuple[float, float]:
    import math

    metres_per_deg_lat = 111_320.0
    metres_per_deg_lon = 111_320.0 * math.cos(math.radians(origin_lat))
    if abs(metres_per_deg_lon) < 1e-9:
        metres_per_deg_lon = 1e-9
    return y / metres_per_deg_lat, x / metres_per_deg_lon
