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

Override storage location with `FIELD_COORDINATE_DATA_DIR`.

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

1. Deploy backend code
2. `make fetch-coordinate-masks` on Railway API + field-ensure worker
3. Restart API + worker
4. `make run-field-site-coordinate-prune CRON_EXTRA='--dry-run'` — review counts
5. `make run-field-site-coordinate-prune` — delete invalid sites
6. Ship Flutter app with Carto OSM tiles
