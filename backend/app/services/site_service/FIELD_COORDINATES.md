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

Railway **does not support sharing one volume across services**. Only **field-generate** (the worker) needs OSM masks on its volume.

1. Mount a volume at **`/data`** on **field-generate**.
2. Set on field-generate:
   ```bash
   FIELD_COORDINATE_DATA_DIR=/data
   FETCH_OSM_COORDINATE_MASKS=true
   OSM_SIMPLIFY_TOLERANCE=0.001
   ```
3. Bump worker memory to **4 GB** (Settings → Resources).
4. Redeploy and watch logs (~10 min first boot). Later restarts reuse `/data/osm/`.

The API (`mesozoica`) does not need OSM on a volume — it only queues jobs.

#### Upload OSM masks (optional)

Railway **SSH upload only works on web/exposed services** (e.g. `mesozoica`). It usually **fails on workers** (`field-generate`) even when deployment shows Active.

Prefer **in-container fetch** on field-generate (steps above). If you already have local files and SSH to the API works:

```bash
make upload-coordinate-masks-railway RAILWAY_SERVICE=mesozoica
```

That only fills the **API** volume; the worker still needs its own fetch.

#### Troubleshooting

If logs show fetch failing or crash-looping:

1. Set `OSM_SIMPLIFY_TOLERANCE=0.001` (coarser, less RAM).
2. Bump field-generate memory to **4 GB**.
3. Do **not** use SSH upload to field-generate — use in-container fetch instead.
4. After masks exist on `/data/osm/`, set `FETCH_OSM_COORDINATE_MASKS=false` to skip future boot checks.

Logs should show `Loaded OSM land filter`, not Natural Earth fallback.

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
