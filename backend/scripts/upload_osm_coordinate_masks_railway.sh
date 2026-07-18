#!/usr/bin/env bash
# Upload locally prepared OSM shapefiles to a Railway volume at /data/osm.
set -euo pipefail

backend_dir="$(cd "$(dirname "$0")/.." && pwd)"
land_shp="${backend_dir}/app/data/osm/land/wgs84_land_polygons.shp"
water_shp="${backend_dir}/app/data/osm/water/wgs84_water_polygons.shp"

if [[ ! -f "$land_shp" || ! -f "$water_shp" ]]; then
  echo "Run make fetch-coordinate-masks first."
  exit 1
fi

railway_project_id() {
  if [[ -n "${RAILWAY_PROJECT_ID:-}" ]]; then
    printf '%s' "${RAILWAY_PROJECT_ID}"
    return 0
  fi
  python3 - <<'PY'
import json
import subprocess

payload = subprocess.check_output(
    ["railway", "status", "--json"],
    text=True,
)
print(json.loads(payload)["id"])
PY
}

run_ssh() {
  (
    cd "$backend_dir"
    if [[ -n "${RAILWAY_SERVICE:-}" ]]; then
      railway ssh \
        -p "$(railway_project_id)" \
        -e "${RAILWAY_ENVIRONMENT:-production}" \
        -s "$RAILWAY_SERVICE" \
        "$@"
    else
      railway ssh "$@"
    fi
  )
}

tmp_tar="$(mktemp "${TMPDIR:-/tmp}/osm-masks.XXXXXX.tar")"
chunk_dir="$(mktemp -d "${TMPDIR:-/tmp}/osm-chunks.XXXXXX")"
cleanup() {
  rm -f "$tmp_tar"
  rm -rf "$chunk_dir"
}
trap cleanup EXIT

echo "Creating tarball from ${backend_dir}/app/data/osm ..."
tar -cf "$tmp_tar" -C "${backend_dir}/app/data" osm
tar_bytes="$(wc -c < "$tmp_tar" | tr -d ' ')"
tar_size="$(du -h "$tmp_tar" | awk '{print $1}')"
service_label="${RAILWAY_SERVICE:-linked service}"
echo "Uploading ${tar_size} to Railway service '${service_label}' at /data/osm ..."
echo "Note: the target service must be running (set FETCH_OSM_COORDINATE_MASKS=false if it crash-loops)."

echo "Step 1/3: Preparing /data on Railway ..."
if ! run_ssh "mkdir -p /data/osm && rm -f /data/osm-masks.tar"; then
  echo "ERROR: Could not reach Railway service or prepare /data."
  echo ""
  echo "Railway SSH often fails on worker / unexposed services (field-generate)"
  echo "even when the deployment shows Active. SSH to the API service (mesozoica) works."
  echo ""
  echo "For field-generate, use in-container fetch instead of upload:"
  echo "  1. Set FETCH_OSM_COORDINATE_MASKS=true"
  echo "  2. Set OSM_SIMPLIFY_TOLERANCE=0.001"
  echo "  3. Bump service memory to 4 GB"
  echo "  4. Redeploy and wait ~10 min for first-boot download into /data/osm"
  echo ""
  echo "Or upload to the API if it has a volume (worker still needs its own copy):"
  echo "  make upload-coordinate-masks-railway RAILWAY_SERVICE=mesozoica"
  exit 1
fi

echo "Step 2/3: Uploading archive in 100 MB chunks (may take 10-20 min) ..."
split -b 100m "$tmp_tar" "${chunk_dir}/chunk-"
run_ssh "rm -f /data/osm-masks.tar"
part_count=0
total_parts="$(find "${chunk_dir}" -name 'chunk-*' | wc -l | tr -d ' ')"
for part in "${chunk_dir}"/chunk-*; do
  part_count=$((part_count + 1))
  echo "  chunk ${part_count}/${total_parts}: $(basename "$part")"
  if ! run_ssh "cat >> /data/osm-masks.tar" < "$part"; then
    echo "ERROR: Upload failed on chunk ${part_count}/${total_parts}."
    exit 1
  fi
done

echo "Step 3/3: Verifying size and extracting on volume ..."
if ! run_ssh "test \$(wc -c < /data/osm-masks.tar) -eq ${tar_bytes}"; then
  echo "ERROR: Remote archive size mismatch (upload incomplete)."
  exit 1
fi
if ! run_ssh \
  "tar -xf /data/osm-masks.tar -C /data && rm -f /data/osm-masks.tar && ls -la /data/osm/land/wgs84_land_polygons.shp /data/osm/water/wgs84_water_polygons.shp"; then
  echo "ERROR: Extract failed on Railway."
  exit 1
fi

echo "Done. Restart the target service to load OSM filters."
