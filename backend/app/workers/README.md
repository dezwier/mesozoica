# Field ensure worker

Always-on Railway service that drains `field_ensure_job` rows and runs `ensure_field_sites_nearby` for each claimed cell.

## Run locally (Railway Postgres)

```bash
make run-field-ensure-worker
```

## Environment

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | — | **Required.** Same Postgres URL as the API service |
| `MESOZOICA_MINIMAL_SETTINGS` | `1` (in start command) | Skips API-only production checks (`SECRET_KEY`, `CORS_ORIGINS`, …) |
| `FIELD_ENSURE_MAX_CONCURRENT` | `2` | Max jobs with `status=running` globally |
| `FIELD_ENSURE_POLL_INTERVAL_S` | `5` | Sleep when no job is available |

The worker start command in [`railway.worker.toml`](../railway.worker.toml) sets `MESOZOICA_MINIMAL_SETTINGS=1` so you only need `DATABASE_URL` in the Railway dashboard.

**Workaround without redeploying:** reference `SECRET_KEY`, `CORS_ORIGINS`, and `WIKIPEDIA_USER_AGENT` from the `backend` service (same as API) until the minimal-settings start command is deployed.

## Deploy

1. Add a Railway service pointing at [`railway.worker.toml`](../railway.worker.toml).
2. Share the same `DATABASE_URL` as the API service.
3. Run Alembic migrations before starting the worker.

Jobs are deduped by `cell_key` (`round(lat,2):round(lon,2):radius_km`). Many players posting the same area enqueue one row; the worker re-counts density before generating.
