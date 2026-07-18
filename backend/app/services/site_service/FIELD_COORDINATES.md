# Field coordinate filter and enrich

Procedural field sites pick random coordinates in two stages:

1. **Filter** — fast offline checks while sampling (may run hundreds of times).
2. **Enrich** — slower metadata lookup after a coordinate is accepted (once per site).

## Filter (offline, in-memory)

While generating sites the API/worker asks: “Is this point allowed?”

Current rules (when OSM masks are present):

| Filter | Source | Status |
|--------|--------|--------|
| On OSM land | `backend/app/data/osm/land/*.shp` | Active |
| Not in OSM water | `backend/app/data/osm/water/*.shp` | Active |

**Fallback** (CI / dev without OSM data): Natural Earth 10m land GeoJSON only.

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

This downloads ~880 MB land + ~860 MB water archives from [osmdata.openstreetmap.de](https://osmdata.openstreetmap.de/), simplifies to ~10 m tolerance by default, and writes shapefiles under `backend/app/data/osm/`. The directory is gitignored.

Options:

```bash
cd backend
python -m scripts.fetch_osm_coordinate_masks --help
python -m scripts.fetch_osm_coordinate_masks --simplify-tolerance 0 --force
```

Override storage location with `FIELD_COORDINATE_DATA_DIR` (e.g. a Railway volume mounted at `/data`).

### Production (Railway volume — recommended)

OSM shapefiles are **gitignored** and are **not** baked into the Docker image. Store them on a **shared Railway volume** so they are downloaded once and reused across deploys.

`make run-field-site-coordinate-prune` uses `railway run`, which executes **on your machine** with Railway env vars. It reads local `backend/app/data/osm/` and talks to the remote DB. That is why prune can succeed while production still logs the Natural Earth fallback.

#### One-time Railway setup

Railway **does not support sharing one volume across services**. Upload OSM masks to the **field-generate worker** (the service that creates field sites). The API does not need them.

1. Mount a volume at **`/data`** on:
   - API service
   - field-ensure worker
   - cron service (if running coordinate prune)
2. Set on each of those services:
   ```bash
   FIELD_COORDINATE_DATA_DIR=/data
   FETCH_OSM_COORDINATE_MASKS=false
   ```
   (`CURATED_IMAGES_DATA_ROOT=/data` on the API for card images uses that service's volume only.)

   `FETCH_OSM_COORDINATE_MASKS=false` stops the container from trying to download OSM on boot (often OOM on Railway). Upload from your laptop instead (step 3).

3. **Upload local masks to the worker** (you already ran `make fetch-coordinate-masks`):
   ```bash
   make upload-coordinate-masks-railway RAILWAY_SERVICE=field-generate
   ```
   The worker must be **running** during upload (`FETCH_OSM_COORDINATE_MASKS=false` if it crash-loops). List services: `cd backend && railway status --json`.
4. **Redeploy / restart** API and field-ensure worker.

Logs should show `Loaded OSM land filter`, not Natural Earth fallback.

#### Alternative: fetch on Railway (needs 2 GB+ RAM)

If you prefer Railway to download OSM itself, set `FETCH_OSM_COORDINATE_MASKS=true` and bump API memory to 2 GB+. First boot takes ~5–10 minutes.

#### Troubleshooting

If logs show `OSM fetch lock released but masks are still missing` in a loop, the in-container fetch failed (usually OOM):

1. Set `FETCH_OSM_COORDINATE_MASKS=false` on API + worker
2. Redeploy to stop the loop
3. Run `make upload-coordinate-masks-railway` **once per service** (API + worker)
4. Restart API + worker

### Loading and RAM

Polygon filters load **once per process** via `@lru_cache`.
The API server and field-ensure worker each keep one in-memory copy after the first use.

Startup preload:

- API: `warm_coordinate_filter_cache()` in app lifespan
- Worker: same call in `field_ensure_worker.main()`

Approximate footprint with simplified OSM masks:

| Layer | Disk (simplified) | RSS after load (est.) |
|-------|-------------------|------------------------|
| OSM land | ~50–150 MB | ~200–500 MB |
| OSM water | ~50–150 MB | ~200–500 MB |
| Combined | | ~400 MB–1 GB per process |

Natural Earth 10m fallback: ~150 MB RSS, ~10 MB on disk (committed for CI).

Point lookup: ~0.003 ms via Shapely `STRtree` + `predicate="within"`.

Legacy override: `land_mask_path` in field-site config forces Natural Earth GeoJSON.

## Enrich (after accept)

After filtering succeeds, enrichment runs **once** for the accepted coordinate.

Current fields:

| Field | Source |
|-------|--------|
| `country_code` | `reverse_geocoder` (offline GeoNames DB) |
| `state` | `reverse_geocoder` |

## Retroactive cleanup

Remove existing field sites that fail the current filter stack:

```bash
make run-field-site-coordinate-prune CRON_EXTRA='--dry-run'
make run-field-site-coordinate-prune
```

Registered as cron job `field_site_coordinate_prune` (disabled by default in `crons.yaml`).

Sparse areas backfill automatically via the existing field-ensure worker on resume/move/scan.

## Flutter map tiles

The map uses Carto OSM no-labels basemaps (light/dark) so coastlines align with the OSM polygon filters. See `flutter/lib/config/map_config.dart`.

## Code map

| Module | Role |
|--------|------|
| `field_coordinate_filter.py` | Filter protocol, OSM/NE polygons, sampler |
| `field_coordinate_enrich.py` | Post-accept metadata |
| `field_coordinate_prune.py` | Delete invalid existing field sites |
| `field_generate.py` | Orchestrates filter → geology → enrich → `Site` row |
| `scripts/fetch_osm_coordinate_masks.py` | Download/prepare OSM shapefiles |

## Deploy sequence

1. Mount shared Railway volume at `/data` on API + field-ensure worker (+ cron if needed)
2. Set `FIELD_COORDINATE_DATA_DIR=/data` on those services
3. Deploy backend code (first boot fetches OSM masks into the volume once)
4. Confirm logs show `Loaded OSM land filter` (not Natural Earth fallback)
5. `make run-field-site-coordinate-prune CRON_EXTRA='--dry-run'` — review counts
6. `make run-field-site-coordinate-prune` — delete invalid sites
7. Ship Flutter app with Carto OSM tiles

Local dev (optional):

```bash
make fetch-coordinate-masks
```
