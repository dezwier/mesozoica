# Field ensure worker

Always-on Railway service that drains `field_ensure_job` rows and runs `ensure_field_sites_nearby` for each claimed cell.

## Run locally (Railway Postgres)

```bash
make run-field-ensure-worker
```

## Environment

| Variable | Default | Description |
|----------|---------|-------------|
| `FIELD_ENSURE_MAX_CONCURRENT` | `2` | Max jobs with `status=running` globally |
| `FIELD_ENSURE_POLL_INTERVAL_S` | `5` | Sleep when no job is available |

## Deploy

1. Add a Railway service pointing at [`railway.worker.toml`](../railway.worker.toml).
2. Share the same `DATABASE_URL` as the API service.
3. Run Alembic migrations before starting the worker.

Jobs are deduped by `cell_key` (`round(lat,2):round(lon,2):radius_km`). Many players posting the same area enqueue one row; the worker re-counts density before generating.
