#!/bin/sh
set -e

resolve_coord_dir() {
  if [ -n "${FIELD_COORDINATE_DATA_DIR:-}" ]; then
    printf '%s' "${FIELD_COORDINATE_DATA_DIR}"
  elif [ -d /data ] && [ -w /data ]; then
    printf '%s' /data
  else
    printf '%s' /app/app/data
  fi
}

wait_for_volume() {
  coord_dir="$1"
  waited=0
  while [ ! -d "$coord_dir" ] || [ ! -w "$coord_dir" ]; do
    if [ "$waited" -ge 120 ]; then
      echo "ERROR: Coordinate data directory not writable: ${coord_dir}"
      return 1
    fi
    echo "INFO: Waiting for writable coordinate data directory: ${coord_dir} ..."
    sleep 2
    waited=$((waited + 2))
  done
}

masks_ready() {
  [ -f "$land_shp" ] && [ -f "$water_shp" ]
}

fetch_masks() {
  simplify="${OSM_SIMPLIFY_TOLERANCE:-0.0001}"
  echo "INFO: Fetching OSM coordinate masks into ${coord_dir}/osm (simplify=${simplify}) ..."
  mkdir -p "${coord_dir}/osm"
  python -m scripts.fetch_osm_coordinate_masks \
    --data-dir "${coord_dir}/osm" \
    --simplify-tolerance "${simplify}"
}

ensure_masks() {
  if masks_ready; then
    echo "INFO: OSM coordinate masks present at ${coord_dir}/osm"
    return 0
  fi

  if [ "${FETCH_OSM_COORDINATE_MASKS:-true}" = "false" ]; then
    echo "WARN: OSM coordinate masks missing under ${coord_dir}/osm; using Natural Earth fallback."
    return 0
  fi

  fetch_attempts=0
  while ! masks_ready; do
    if mkdir "$lock_dir" 2>/dev/null; then
      trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT INT TERM
      if fetch_masks; then
        rmdir "$lock_dir" 2>/dev/null || true
        trap - EXIT INT TERM
        echo "INFO: OSM coordinate masks ready at ${coord_dir}/osm"
        return 0
      fi
      echo "ERROR: OSM coordinate mask fetch failed (attempt $((fetch_attempts + 1)))."
      rmdir "$lock_dir" 2>/dev/null || true
      trap - EXIT INT TERM
      fetch_attempts=$((fetch_attempts + 1))
      if [ "$fetch_attempts" -ge 3 ]; then
        echo "ERROR: OSM fetch failed after 3 attempts; starting with Natural Earth fallback."
        echo "ERROR: Check service memory (recommend 2 GB+ for first fetch) and volume mount at ${coord_dir}."
        return 0
      fi
      sleep 15
      continue
    fi

    echo "INFO: Another instance is fetching OSM coordinate masks; waiting ..."
    waited=0
    while ! masks_ready; do
      if [ ! -d "$lock_dir" ]; then
        break
      fi
      if [ "$waited" -ge 3600 ]; then
        echo "ERROR: Timed out waiting for OSM coordinate masks."
        return 0
      fi
      sleep 5
      waited=$((waited + 5))
    done
  done

  return 0
}

coord_dir="$(resolve_coord_dir)"
land_shp="${coord_dir}/osm/land/wgs84_land_polygons.shp"
water_shp="${coord_dir}/osm/water/wgs84_water_polygons.shp"
lock_dir="${coord_dir}/osm/.fetch.lock"

wait_for_volume "$coord_dir" || true
ensure_masks

exec "$@"
