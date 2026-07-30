# Field coordinate filter and enrich

Procedural field sites pick random coordinates in two stages:

1. **Filter** — fast offline checks while sampling (may run hundreds of times).
2. **Enrich** — slower metadata lookup after a coordinate is accepted (once per site).

## Filter (offline, in-memory)

While generating sites the worker/prune job asks: “Is this point allowed?”

Production rules (**required — no fallback**):

| Filter | Source | Status |
|--------|--------|--------|
| On OSM land | `{FIELD_COORDINATE_DATA_DIR}/osm/land/*.shp` | Required |
| Not in OSM water | `{FIELD_COORDINATE_DATA_DIR}/osm/water/*.shp` | Required |

The field-ensure **worker** and **field_site_coordinate_prune** cron **fail startup** if OSM shapefiles are missing. There is no Natural Earth fallback in production.

Unit tests inject inline polygon fixtures or pass `land_mask_path` explicitly.

Future rules (same pipeline, still offline):

- Exclude military areas
- Exclude protected areas
- Admin blocklist from Postgres

Filters use **preloaded polygon maps**, not live HTTP APIs.

### Fetch OSM masks

From repo root:

```bash
make fetch-coordinate-masks
```

This downloads ~880 MB land + ~860 MB water archives from [osmdata.openstreetmap.de](https://osmdata.openstreetmap.de/), simplifies to ~10 m tolerance by default (`OSM_SIMPLIFY_TOLERANCE=0.0001`), and writes shapefiles under `backend/app/data/osm/`. The directory is gitignored.

Options:

```bash
cd backend
python -m scripts.fetch_osm_coordinate_masks --help
python -m scripts.fetch_osm_coordinate_masks --simplify-tolerance 0 --force
```

Override storage location with `FIELD_COORDINATE_DATA_DIR` (e.g. a Railway volume mounted at `/data`).

### Production (Railway volume — required)

OSM shapefiles are **gitignored** and are **not** baked into the Docker image. Store them on a **Railway volume** on the field-generate worker.

#### One-time Railway setup

Railway **does not support sharing one volume across services**. Only **field-generate** (the worker) needs OSM masks on its volume. The prune cron must use the same masks (fetch locally before `make run-field-site-coordinate-prune`, or run prune in an environment with OSM data).

1. Mount a volume at **`/data`** on **field-generate**.
2. Set on field-generate:
   ```bash
   FIELD_COORDINATE_DATA_DIR=/data
   FETCH_OSM_COORDINATE_MASKS=true
   OSM_SIMPLIFY_TOLERANCE=0.0001
   ```
3. Bump worker memory to **4 GB** (Settings → Resources).
4. Redeploy and watch logs (~10 min first boot). Later restarts reuse `/data/osm/`.
5. After masks exist, set `FETCH_OSM_COORDINATE_MASKS=false` to skip future boot fetches.

The API (`mesozoica`) does not need OSM on a volume — it only enqueues jobs without loading coordinate filters.

#### Upload OSM masks (optional)

Railway **SSH upload only works on web/exposed services** (e.g. `mesozoica`). It usually **fails on workers** (`field-generate`) even when deployment shows Active.

Prefer **in-container fetch** on field-generate (steps above).

#### Troubleshooting

If the worker exits on startup or logs fetch failure:

1. Confirm `FIELD_COORDINATE_DATA_DIR=/data` and the volume is mounted.
2. Keep `OSM_SIMPLIFY_TOLERANCE=0.0001` (~10 m). Do not fall back to Natural Earth.
3. Bump field-generate memory to **4 GB**.
4. Logs must show `Loaded OSM land filter` and `Loaded OSM water exclusion filter`.

### Loading and RAM

Polygon filters load **once per process** via `@lru_cache` on the worker and prune job only.

Startup preload:

- Worker: `ensure_osm_coordinate_masks_on_disk()` then `warm_coordinate_filter_cache()` in `field_ensure_worker.main()`
- Prune cron: same sequence in `field_site_coordinate_prune.run_prune_job()`

Approximate footprint with 10 m OSM masks:

| Layer | Disk (simplified) | RSS after load (est.) |
|-------|-------------------|------------------------|
| OSM land | ~50–150 MB | ~200–500 MB |
| OSM water | ~50–150 MB | ~200–500 MB |
| Combined | | ~400 MB–1 GB per process |

Point lookup: ~0.003 ms via Shapely `STRtree` + `predicate="within"`.

## Enrich (after accept)

After filtering succeeds, enrichment runs **once** for the accepted coordinate.

Current fields:

| Field | Source |
|-------|--------|
| `country_code` | `reverse_geocoder` (offline GeoNames DB) |
| `state` | `reverse_geocoder` |

## Retroactive cleanup

Remove existing field sites that fail the OSM filter stack:

```bash
make fetch-coordinate-masks   # if not already present locally
make run-field-site-coordinate-prune CRON_EXTRA='--dry-run'
make run-field-site-coordinate-prune
```

Registered as cron job `field_site_coordinate_prune` (disabled by default in `crons.yaml`).

Sparse areas backfill automatically via the field-ensure worker on resume/move/scan.

**Local prune via `make run-field-site-coordinate-prune`:** `railway run` injects Railway's `FIELD_COORDINATE_DATA_DIR=/data`, which does not exist on your Mac. If OSM masks are present under `backend/app/data/osm/` (from `make fetch-coordinate-masks`), the code automatically uses that local copy. Run `make fetch-coordinate-masks` once if prune fails with missing masks.

## Flutter map tiles

The map uses Carto OSM no-labels basemaps (light/dark) so coastlines align with the OSM polygon filters. See `flutter/lib/config/map_config.dart`.

## Code map

| Module | Role |
|--------|------|
| `field_coordinate_filter.py` | Filter protocol, OSM polygons, sampler |
| `field_coordinate_enrich.py` | Post-accept metadata |
| `field_coordinate_prune.py` | Delete invalid existing field sites |
| `field_generate.py` | Orchestrates filter → geology → enrich → `Site` row |
| `scripts/fetch_osm_coordinate_masks.py` | Download/prepare OSM shapefiles |

## Deploy sequence

1. Mount Railway volume at `/data` on field-generate worker
2. Set `FIELD_COORDINATE_DATA_DIR=/data`, `OSM_SIMPLIFY_TOLERANCE=0.0001`, 4 GB RAM
3. Deploy backend code (first boot fetches OSM masks into the volume once)
4. Confirm logs show `Loaded OSM land filter` and `Loaded OSM water exclusion filter`
5. `make run-field-site-coordinate-prune CRON_EXTRA='--dry-run'` — review counts (requires local OSM masks)
6. `make run-field-site-coordinate-prune` — delete invalid sites
7. Ship Flutter app with Carto OSM tiles

Local dev:

```bash
make fetch-coordinate-masks
make run-field-ensure-worker
```
