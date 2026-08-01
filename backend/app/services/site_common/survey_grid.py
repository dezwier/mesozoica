"""Shared 200 m survey grid math (Formation Map footprint / snap).

Uses equirectangular meters with latitude-scaled longitude so client and
server snap the same GPS point to the same cell center.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

METERS_PER_DEG_LAT = 111320.0


def _meters_per_deg_lon(lat: float) -> float:
    cos_lat = abs(math.cos(math.radians(lat)))
    return METERS_PER_DEG_LAT * max(cos_lat, 0.2)


def latlon_to_meters(lat: float, lon: float) -> tuple[float, float]:
    """Project to meters (x east, y north) for grid indexing."""
    y = lat * METERS_PER_DEG_LAT
    x = lon * _meters_per_deg_lon(lat)
    return x, y


def meters_to_latlon(x: float, y: float) -> tuple[float, float]:
    lat = y / METERS_PER_DEG_LAT
    lon = x / _meters_per_deg_lon(lat)
    return lat, lon


def cell_indices(lat: float, lon: float, *, cell_size_m: float) -> tuple[int, int]:
    x, y = latlon_to_meters(lat, lon)
    return int(math.floor(x / cell_size_m)), int(math.floor(y / cell_size_m))


def cell_center_latlon(ix: int, iy: int, *, cell_size_m: float) -> tuple[float, float]:
    x = (ix + 0.5) * cell_size_m
    y = (iy + 0.5) * cell_size_m
    return meters_to_latlon(x, y)


def cell_meter_bounds(
    ix: int, iy: int, *, cell_size_m: float
) -> tuple[float, float, float, float]:
    """Return ``(x0, x1, y0, y1)`` half-open meter bounds for cell ``(ix, iy)``."""
    cell = max(float(cell_size_m), 1.0)
    x0 = ix * cell
    y0 = iy * cell
    return x0, x0 + cell, y0, y0 + cell


def cell_latlon_bbox(
    ix: int,
    iy: int,
    *,
    cell_size_m: float,
    pad_m: float = 1.0,
) -> tuple[float, float, float, float]:
    """Lat/lon AABB covering the meter-space cell (for SQL prefilter only).

    Returns ``(south, north, west, east)``. Always pad slightly — lon edges are
    curved in lat/lon, so callers must still filter with ``cell_indices``.
    """
    x0, x1, y0, y1 = cell_meter_bounds(ix, iy, cell_size_m=cell_size_m)
    pad = max(float(pad_m), 0.0)
    corners = (
        meters_to_latlon(x0 - pad, y0 - pad),
        meters_to_latlon(x1 + pad, y0 - pad),
        meters_to_latlon(x0 - pad, y1 + pad),
        meters_to_latlon(x1 + pad, y1 + pad),
    )
    lats = [c[0] for c in corners]
    lons = [c[1] for c in corners]
    return min(lats), max(lats), min(lons), max(lons)


def point_in_cell(
    lat: float,
    lon: float,
    *,
    ix: int,
    iy: int,
    cell_size_m: float,
) -> bool:
    return cell_indices(lat, lon, cell_size_m=cell_size_m) == (ix, iy)


def snap_to_cell_center(
    lat: float,
    lon: float,
    *,
    cell_size_m: float,
) -> tuple[float, float]:
    ix, iy = cell_indices(lat, lon, cell_size_m=cell_size_m)
    return cell_center_latlon(ix, iy, cell_size_m=cell_size_m)


def snap_wideness_m(
    wideness_m: float,
    *,
    cell_size_m: float,
    min_wideness_m: float,
    max_wideness_m: float,
) -> float:
    cell = max(float(cell_size_m), 1.0)
    lo = max(float(min_wideness_m), cell)
    hi = max(float(max_wideness_m), lo)
    raw = max(lo, min(hi, float(wideness_m)))
    n = max(1, int(round(raw / cell)))
    return float(n * cell)


@dataclass(frozen=True)
class GridFootprint:
    """Axis-aligned lat/lon bbox covering an N×N block of cells."""

    center_lat: float
    center_lon: float
    wideness_m: float
    cell_size_m: float
    n: int
    west: float
    east: float
    south: float
    north: float
    half_diagonal_m: float


def footprint_for_center(
    center_lat: float,
    center_lon: float,
    *,
    wideness_m: float,
    cell_size_m: float,
) -> GridFootprint:
    """N×N cells with anchor cell as central as possible (even N biases +E/+N)."""
    cell = max(float(cell_size_m), 1.0)
    n = max(1, int(round(float(wideness_m) / cell)))
    side_m = n * cell
    ix, iy = cell_indices(center_lat, center_lon, cell_size_m=cell)
    # Re-snap so stored centers that already are cell centers stay stable.
    center_lat, center_lon = cell_center_latlon(ix, iy, cell_size_m=cell)

    half_lo = (n - 1) // 2
    half_hi = n // 2
    ix0, ix1 = ix - half_lo, ix + half_hi
    iy0, iy1 = iy - half_lo, iy + half_hi

    # Cell (ix,iy) covers [ix*s, (ix+1)*s) × [iy*s, (iy+1)*s).
    x_west = ix0 * cell
    x_east = (ix1 + 1) * cell
    y_south = iy0 * cell
    y_north = (iy1 + 1) * cell

    sw_lat, sw_lon = meters_to_latlon(x_west, y_south)
    se_lat, se_lon = meters_to_latlon(x_east, y_south)
    nw_lat, nw_lon = meters_to_latlon(x_west, y_north)
    ne_lat, ne_lon = meters_to_latlon(x_east, y_north)
    south = min(sw_lat, se_lat)
    north = max(nw_lat, ne_lat)
    west = min(sw_lon, nw_lon)
    east = max(se_lon, ne_lon)

    half_diag = math.sqrt(2.0) * (side_m / 2.0)
    return GridFootprint(
        center_lat=center_lat,
        center_lon=center_lon,
        wideness_m=side_m,
        cell_size_m=cell,
        n=n,
        west=west,
        east=east,
        south=south,
        north=north,
        half_diagonal_m=half_diag,
    )
