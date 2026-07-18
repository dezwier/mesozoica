# Field coordinate filter and enrich

Procedural field sites pick random coordinates in two stages:

1. **Filter** — fast offline checks while sampling (may run hundreds of times).
2. **Enrich** — slower metadata lookup after a coordinate is accepted (once per site).

## Filter (offline, in-memory)

While generating sites the API/worker asks: “Is this point allowed?”

Current rules:

| Filter | Source | Status |
|--------|--------|--------|
| On land | `backend/app/data/natural_earth_land_10m.geojson` | Active |

Future rules (same pipeline, still offline):

- Exclude military areas
- Exclude protected areas
- Admin blocklist from Postgres

Filters use **preloaded polygon maps** (or rasters later), not live HTTP APIs.

### Loading and RAM

Land polygons load **once per process** via `@lru_cache` on `load_land_polygon_filter`.
The API server and field-ensure worker each keep one in-memory copy after the first use.

Startup preload (optional but recommended):

- API: `warm_coordinate_filter_cache()` in app lifespan
- Worker: same call in `field_ensure_worker.main()`

Approximate footprint for Natural Earth 10m land (~6.8k polygons, ~10 MB on disk):

- **~150 MB RSS** per Python process after load (geometry + spatial index)
- **~0.4 s** one-time load on a typical dev machine
- Point lookup: **~0.003 ms** with Shapely `STRtree` + `predicate="contains"`

Override the dataset path with `land_mask_path` in field-site config or by changing
`DEFAULT_LAND_MASK_PATH`.

## Enrich (after accept)

After filtering succeeds, enrichment runs **once** for the accepted coordinate.

Current fields:

| Field | Source |
|-------|--------|
| `country_code` | `reverse_geocoder` (offline GeoNames DB) |
| `state` | `reverse_geocoder` |

Future enrich fields (elevation, land cover, nearest road, etc.) belong here — not in
the rejection loop.

## Code map

| Module | Role |
|--------|------|
| `field_coordinate_filter.py` | Filter protocol, land polygons, sampler |
| `field_coordinate_enrich.py` | Post-accept metadata |
| `field_generate.py` | Orchestrates filter → geology → enrich → `Site` row |
