"""Download OSM land/water polygon shapefiles for field-site coordinate filtering."""

from __future__ import annotations

import argparse
import logging
import shutil
import tempfile
import zipfile
from pathlib import Path
from urllib.request import urlretrieve

from shapely.geometry.base import BaseGeometry

from app.services.field_service.field_coordinate_geodata import (
    flatten_polygons,
    read_shapefile_polygons,
    write_shapefile_polygons,
)

logger = logging.getLogger(__name__)

DEFAULT_DATA_DIR = Path(__file__).resolve().parents[1] / "app" / "data" / "osm"
DEFAULT_SIMPLIFY_TOLERANCE = 0.0001

DATASETS = {
    "land": {
        "url": "https://osmdata.openstreetmap.de/download/land-polygons-split-4326.zip",
        "extract_subdir": "land-polygons-split-4326",
        "output_subdir": "land",
        "output_stem": "wgs84_land_polygons",
    },
    "water": {
        "url": "https://osmdata.openstreetmap.de/download/water-polygons-split-4326.zip",
        "extract_subdir": "water-polygons-split-4326",
        "output_subdir": "water",
        "output_stem": "wgs84_water_polygons",
    },
}


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Download OSM land/water polygon shapefiles for coordinate filtering."
    )
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=DEFAULT_DATA_DIR,
        help=f"Output root directory (default: {DEFAULT_DATA_DIR})",
    )
    parser.add_argument(
        "--simplify-tolerance",
        type=float,
        default=DEFAULT_SIMPLIFY_TOLERANCE,
        help="Douglas-Peucker tolerance in degrees (~0.0001 ≈ 10 m). Use 0 to keep full resolution.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-download even when output shapefiles already exist.",
    )
    return parser.parse_args()


def _find_shapefile(root: Path) -> Path:
    matches = sorted(root.rglob("*.shp"))
    if not matches:
        raise FileNotFoundError(f"No .shp files found under {root}")
    return matches[0]


def _write_simplified_shapefile(
    *,
    source_shp: Path,
    dest_shp: Path,
    simplify_tolerance: float,
) -> int:
    geometries = read_shapefile_polygons(source_shp)
    simplified: list[BaseGeometry] = []
    for geometry in geometries:
        if simplify_tolerance > 0:
            geometry = geometry.simplify(simplify_tolerance, preserve_topology=True)
        simplified.extend(flatten_polygons(geometry))

    if not simplified:
        raise RuntimeError(f"No geometries produced from {source_shp}")

    if dest_shp.exists():
        for suffix in (".shp", ".shx", ".dbf", ".prj", ".cpg"):
            path = dest_shp.with_suffix(suffix)
            if path.exists():
                path.unlink()

    write_shapefile_polygons(dest_shp, simplified)
    return len(simplified)


def _copy_shapefile(source_shp: Path, dest_shp: Path) -> None:
    dest_shp.parent.mkdir(parents=True, exist_ok=True)
    for suffix in (".shp", ".shx", ".dbf", ".prj", ".cpg"):
        src = source_shp.with_suffix(suffix)
        if src.exists():
            shutil.copy2(src, dest_shp.with_suffix(suffix))


def _prepare_dataset(
    *,
    name: str,
    data_dir: Path,
    simplify_tolerance: float,
    force: bool,
) -> int:
    meta = DATASETS[name]
    output_dir = data_dir / meta["output_subdir"]
    output_shp = output_dir / f"{meta['output_stem']}.shp"
    if output_shp.exists() and not force:
        logger.info("Skip %s — already present at %s", name, output_shp)
        return len(read_shapefile_polygons(output_shp))

    logger.info("Downloading %s polygons from %s", name, meta["url"])
    with tempfile.TemporaryDirectory(prefix=f"osm-{name}-") as tmp:
        tmp_path = Path(tmp)
        zip_path = tmp_path / f"{name}.zip"
        urlretrieve(meta["url"], zip_path)
        with zipfile.ZipFile(zip_path) as archive:
            archive.extractall(tmp_path)

        source_root = tmp_path / meta["extract_subdir"]
        if not source_root.exists():
            source_root = tmp_path
        source_shp = _find_shapefile(source_root)

        if simplify_tolerance > 0:
            polygon_count = _write_simplified_shapefile(
                source_shp=source_shp,
                dest_shp=output_shp,
                simplify_tolerance=simplify_tolerance,
            )
        else:
            _copy_shapefile(source_shp, output_shp)
            polygon_count = len(read_shapefile_polygons(output_shp))

    logger.info(
        "Prepared %s polygons=%d simplify=%s output=%s",
        name,
        polygon_count,
        simplify_tolerance,
        output_shp,
    )
    return polygon_count


def run_fetch(
    *,
    data_dir: Path,
    simplify_tolerance: float,
    force: bool,
) -> int:
    totals = {
        name: _prepare_dataset(
            name=name,
            data_dir=data_dir,
            simplify_tolerance=simplify_tolerance,
            force=force,
        )
        for name in DATASETS
    }
    logger.info("OSM coordinate masks ready in %s — %s", data_dir, totals)
    return 0


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    args = _parse_args()
    try:
        return run_fetch(
            data_dir=args.data_dir,
            simplify_tolerance=args.simplify_tolerance,
            force=args.force,
        )
    except Exception:
        logger.exception("Failed to fetch OSM coordinate masks")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
