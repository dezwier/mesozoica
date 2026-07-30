"""Shapefile I/O helpers for coordinate polygon filters (pyogrio 0.11+)."""

from __future__ import annotations

from pathlib import Path

from pyogrio import shapely as pyogrio_shapely
from pyogrio.raw import read as raw_read
from pyogrio.raw import write as raw_write
from shapely.geometry.base import BaseGeometry


def flatten_polygons(geometry: BaseGeometry) -> list[BaseGeometry]:
    if geometry.is_empty:
        return []
    if geometry.geom_type == "Polygon":
        return [geometry]
    if geometry.geom_type == "MultiPolygon":
        return [polygon for polygon in geometry.geoms if not polygon.is_empty]
    return []


def read_shapefile_polygons(shapefile_path: Path) -> list[BaseGeometry]:
    """Read all polygon geometries from a shapefile."""
    _fields, _geometry_field, geometry_wkb, _crs = raw_read(str(shapefile_path))
    polygons: list[BaseGeometry] = []
    for geometry in pyogrio_shapely.from_wkb(geometry_wkb):
        if geometry is None or geometry.is_empty:
            continue
        polygons.extend(flatten_polygons(geometry))
    if not polygons:
        raise RuntimeError(f"No polygons loaded from {shapefile_path}")
    return polygons


def write_shapefile_polygons(
    shapefile_path: Path,
    polygons: list[BaseGeometry],
    *,
    crs: str = "EPSG:4326",
) -> None:
    """Write polygon geometries to an ESRI shapefile."""
    if not polygons:
        raise ValueError("write_shapefile_polygons requires at least one polygon")

    shapefile_path.parent.mkdir(parents=True, exist_ok=True)
    geometry_wkb = pyogrio_shapely.to_wkb(polygons)
    raw_write(
        str(shapefile_path),
        geometry_wkb,
        {},
        [],
        crs=crs,
        driver="ESRI Shapefile",
        geometry_type="Polygon",
    )
