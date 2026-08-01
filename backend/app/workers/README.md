# Field ensure worker

Always-on Railway service that drains `field_ensure_job` rows and runs `ensure_field_sites_nearby` for each claimed cell.

## Run locally (Railway Postgres)

```bash
make fetch-coordinate-masks   # required once — OSM masks must exist locally
make run-field-ensure-worker
```

## Environment

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | — | **Required.** Same Postgres URL as the API service |
| `MESOZOICA_MINIMAL_SETTINGS` | `1` (in start command) | Skips API-only production checks (`SECRET_KEY`, `CORS_ORIGINS`, …) |
| `FIELD_COORDINATE_DATA_DIR` | `backend/app/data` | OSM mask storage (`/data` on Railway volume) |
| `FETCH_OSM_COORDINATE_MASKS` | `true` | Download masks on first boot when missing |
| `OSM_SIMPLIFY_TOLERANCE` | `0.0001` | ~10 m Douglas-Peucker tolerance (degrees) |
| `FIELD_ENSURE_MAX_CONCURRENT` | `2` | Max jobs with `status=running` globally |
| `FIELD_ENSURE_POLL_INTERVAL_S` | `5` | Sleep when no job is available |

Log lines use a unified format, e.g. `field_site_generate action=ensure_check service=api enqueued=true`. Worker logs `action=ensure_complete service=worker written=… total_in_radius=… elapsed_s=…`.

The worker **exits on startup** if OSM land/water shapefiles are missing and cannot be fetched. There is no Natural Earth fallback.

The API (`POST /api/v1/sites/field/ensure`) only enqueues jobs — it does not count sites or load OSM masks.

## Performance (local benchmark)

Integration test `test_ensure_generates_100_sites_within_time_budget` (marked `@pytest.mark.slow`) generates 100 sites with a test land polygon and asserts completion within **30 s**. Production timing depends on OSM rejection rate, archive-site count, and DB load; check worker logs for `elapsed_s`.

Sites are committed in batches of **25** (`WRITE_BATCH_SIZE`) *during* generation, so the map can poll progressive chunks. Sampling/geology between commits does not hold a write lock. After an ensure request the Flutter map polls at 3s, 6s, 10s, … up to 2 min, then every 60 s.

## Deploy

1. Add a Railway service pointing at [`railway.worker.toml`](../railway.worker.toml).
2. Share the same `DATABASE_URL` as the API service.
3. Mount a volume at `/data` on **field-generate** and set `FIELD_COORDINATE_DATA_DIR=/data`.
4. Set `OSM_SIMPLIFY_TOLERANCE=0.0001` and allocate **4 GB RAM**.
5. Run Alembic migrations before starting the worker.

Jobs are deduped by `cell_key` (`{ix}:{iy}:{cell_size_m}` on the fixed density grid). The API enqueues without counting; the worker re-counts density in that square before generating.

## Ops verification checklist

After deploy, confirm in field-generate logs:

- `OSM coordinate masks already present` or successful fetch into `/data/osm/`
- `Loaded OSM land filter` and `Loaded OSM water exclusion filter`
- **Never** `falling back to Natural Earth land`
- `field_ensure_worker: coordinate masks ready`
- Jobs move from `pending` → `done` in `field_ensure_job`

If the worker crash-loops, verify the volume is mounted, `FETCH_OSM_COORDINATE_MASKS=true` on first boot, and memory is at least 4 GB.
