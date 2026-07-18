#!/bin/sh
set -e

if [ -n "${FIELD_COORDINATE_DATA_DIR:-}" ]; then
  coord_dir="${FIELD_COORDINATE_DATA_DIR}"
elif [ -d /data ] && [ -w /data ]; then
  coord_dir=/data
else
  coord_dir=/app/app/data
fi

land_shp="${coord_dir}/osm/land/wgs84_land_polygons.shp"
water_shp="${coord_dir}/osm/water/wgs84_water_polygons.shp"
lock_dir="${coord_dir}/osm/.fetch.lock"

fetch_masks() {
  echo "INFO: OSM coordinate masks missing; fetching into ${coord_dir}/osm ..."
  mkdir -p "${coord_dir}/osm"
  python -m scripts.fetch_osm_coordinate_masks --data-dir "${coord_dir}/osm"
}

wait_for_masks() {
  echo "INFO: Waiting for OSM coordinate masks on shared volume ..."
  waited=0
  while [ ! -f "$land_shp" ] || [ ! -f "$water_shp" ]; do
    if [ ! -d "$lock_dir" ]; then
      if [ -f "$land_shp" ] && [ -f "$water_shp" ]; then
        return 0
      fi
      echo "WARN: OSM fetch lock released but masks are still missing."
      return 1
    fi
    if [ "$waited" -ge 3600 ]; then
      echo "ERROR: Timed out waiting for OSM coordinate masks."
      return 1
    fi
    sleep 5
    waited=$((waited + 5))
  done
}

if [ ! -f "$land_shp" ] || [ ! -f "$water_shp" ]; then
  if [ "${FETCH_OSM_COORDINATE_MASKS:-true}" = "false" ]; then
    echo "WARN: OSM coordinate masks missing under ${coord_dir}/osm; using Natural Earth fallback."
  elif mkdir "$lock_dir" 2>/dev/null; then
    trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT INT TERM
    fetch_masks
    rmdir "$lock_dir" 2>/dev/null || true
    trap - EXIT INT TERM
  else
    wait_for_masks
  fi
fi

exec "$@"
