# Operations guide

This is the cross-cutting production overview. Detailed flags and job semantics remain in the linked subsystem guides.

## Runtime topology

```text
Flutter clients
  -> Railway API service (FastAPI/uvicorn)
       -> Railway PostgreSQL
       -> mounted /data volume (curated media and coordinate masks)

Railway cron service (hourly scheduler trigger)
  -> feature-owned ingestion, weather, config, media, and maintenance jobs
  -> same PostgreSQL and volume/provider credentials

Railway field worker (long-running)
  -> claims persisted field ensure jobs
  -> coordinate masks/providers
  -> same PostgreSQL
```

The API, cron, and worker are separate process roles. Sharing code and storage does not make their lifecycle or required settings identical.

## API startup

`backend/Dockerfile` uses Python 3.11. The container entrypoint prepares required filesystem data, then the command applies `alembic upgrade head` and starts uvicorn. FastAPI lifespan configures field logging, creates registered tables for fresh environments, and ensures a bundled game-config seed exists. Config seed failure is non-fatal because bundled YAML is the fallback.

Endpoints:

- `/health`: process liveness; does not prove database health.
- `/ready`: checks database connectivity with a bounded timeout.
- `/docs` and `/redoc`: live generated API documentation.
- `/media/...`: static curated/user media mounts.

Production settings reject missing `SECRET_KEY`, wildcard/missing `CORS_ORIGINS`, and missing `WIKIPEDIA_USER_AGENT` for non-minimal processes.

## Railway service configuration

Root [`../railway.toml`](../railway.toml) points the monorepo service at `backend/`. Backend [`../backend/railway.toml`](../backend/railway.toml) selects the Dockerfile. Separate configs define cron and worker processes:

- [`../backend/railway.cron.toml`](../backend/railway.cron.toml)
- [`../backend/railway.worker.toml`](../backend/railway.worker.toml)

Typical shared variables:

- `DATABASE_URL`
- `ENVIRONMENT=production`
- `SECRET_KEY`
- explicit `CORS_ORIGINS`
- `PUBLIC_BASE_URL`
- `CURATED_IMAGES_DATA_ROOT=/data`
- `FIELD_COORDINATE_DATA_DIR=/data`
- provider credentials/user agents appropriate to the process

Mount a persistent volume at `/data` wherever the process must read/write curated media or coordinate masks. Use service-scoped variables when a credential is not needed by every role.

## Database and migrations

Alembic history is authoritative. Deploy startup upgrades to `head` before serving. Never rewrite an applied revision. Before a schema deployment:

1. inspect the generated revision and downgrade path;
2. check locks/runtime for data transformations;
3. test upgrade against a representative non-production database or snapshot;
4. ensure old/new application compatibility when rollout is not atomic;
5. back up or confirm restore capability for destructive transformations.

Pure structural changes should yield no migration. `app/model_registry.py` is the explicit metadata registration point.

## Scheduled jobs

The Railway cron service wakes hourly; `backend/app/crons/crons.yaml` determines which named jobs are due in UTC. Entry points dispatch into feature-owned application/jobs code. Major families include:

- game-config seed/publish support;
- Wikipedia dinosaur sync and Gemini enrichment;
- disabled/manual Wikipedia and OpenAlex RAG acquisition, Azure indexing, status, and quiz preview;
- PBDB fossil sync and Gemini enrichment;
- site, site-type, and tool catalog synchronization;
- weather synchronization;
- curated image generation;
- field coordinate pruning and maintenance.

Use root `make run-*` targets because they apply the Railway execution guard and service environment. Read [`../backend/app/crons/README.md`](../backend/app/crons/README.md) for exact schedules, flags, resume/overwrite behavior, and examples.

Safety rules:

- Assume a job mutates production unless its documented dry-run proves otherwise.
- Prefer scoped entity/max-item flags for diagnosis.
- Understand `--overwrite`, pruning, and resume semantics before running.
- Do not bypass the local-run guard as convenience.
- Capture job name, service/environment, flags, start/end time, and summary output.

## Field ensure worker

The worker is long-running and uses minimal settings mode. It claims persisted jobs, handles deterministic cell generation and coordinate filtering, records state/retries, and writes generated field sites. API requests can enqueue work without performing generation inline.

Operational checks include queue depth/status, oldest pending age, repeated failure reason, worker heartbeat/log activity, database connectivity, coordinate-mask presence, and site counts per affected cell. See [`../backend/app/workers/README.md`](../backend/app/workers/README.md).

## Curated media

Local source assets live under `images/{dinosaurs,fossils,site-types,tools,users}` with version metadata. Production files live on the mounted volume and are served by FastAPI static mounts. Sync scripts match files to entities, upload data, update URLs/versions, and may prune or migrate names depending on the command.

Use the documented Make targets and preview/dry-run modes in [`../backend/scripts/README.md`](../backend/scripts/README.md). Verify both:

1. authenticated version/metadata endpoint behavior; and
2. unauthenticated/static file URL reachability as designed.

A working static URL does not prove the catalog/version API can authenticate.

## External providers

| Provider | Purpose | Failure posture |
| --- | --- | --- |
| Wikipedia/MediaWiki | dinosaur source snapshots and revisions | job logs/thresholds; resumable sync |
| OpenAlex | abstract-bearing paper metadata for RAG snapshots | per-dinosaur/source checkpoint and retry |
| Azure OpenAI | RAG embeddings and structured quiz generation | changed-only embedding; validated output |
| Azure AI Search | generic hybrid/semantic knowledge retrieval | explicit schema validation; no automatic recreation |
| Microsoft Foundry | optional cloud RAG evaluation | Entra ID/RBAC; evaluation/run IDs retained by caller |
| PBDB | fossil occurrence data | resumable batches and validation |
| Gemini | enrichment and image generation | bounded batches, failure thresholds, dry-run where supported |
| Firebase | identity verification and push delivery | auth failures block protected calls; push is best effort |
| Weather provider | cell weather/forecast | persisted data and scheduled refresh |
| Reverse geocoding | site geographic labels | application fallback behavior |
| OSM masks/filesystem | land/water coordinate filtering | worker/prune requires correct volume data |

Provider clients belong in feature infrastructure and must expose enough structured logging to distinguish upstream, validation, persistence, and retry failures.

The RAG package configuration and usage are documented in [`../backend/rag/README.md`](../backend/rag/README.md) and [`../backend/rag/docs/USAGE.md`](../backend/rag/docs/USAGE.md), with detailed recovery in [`../backend/rag/docs/OPERATIONS.md`](../backend/rag/docs/OPERATIONS.md). The app runs a single `dinosaur_knowledge` cron that acquires and indexes each dinosaur/source independently in `dinosaur_knowledge`; failed or interrupted rows remain visible and resume on the next run. Content and pipeline fingerprints both gate currency. Index deletion is never implicit. Use `--recreate-index` only after verifying the configured Azure Search service/index because it causes downtime, deletes and rebuilds that exact index, then marks acquired rows pending.

## Incident triage

### API unavailable

Check process/deploy logs, `/health`, then `/ready`, migration status, required variables, database pool/connection errors, and volume initialization. A healthy process with failed readiness is usually database/configuration, not routing.

### Authenticated calls return `403`

Check client token restoration and authorization header, token expiry/identity provider, backend verification settings, endpoint permission state, and whether only static media succeeds. Reproduce with a known authenticated request before changing authorization rules.

### Field scan reports sites but map is empty

Check API response/count and mode, ensure queue/worker, controller cache/filter/show-all state, then Mapbox annotation publication. Inspect optional overlay errors separately so they cannot mask primary marker updates.

### Job is stuck or repeatedly failing

Confirm exact job/entity/batch, last successful revision/cursor, provider response, failure threshold, database transaction state, and whether overwrite/resume flags match intent. Do not launch a second overlapping destructive run without understanding locking/idempotency.

### Images or versions fail

Separate metadata endpoint status/auth from static file status, validate `PUBLIC_BASE_URL`, configured directory resolution, volume mount/content, DB version record, and `meta.yaml`. A `403` generally points to transport/auth; a `404` static URL generally points to path/sync/version mismatch.

## Release checklist

- Quality gate passes and contract changes are explicitly reviewed.
- Required variables and volume mounts exist for each process role.
- Migration plan is reviewed; backup/restore is understood for risky data changes.
- Game-config version and bundled/active documents are intentional.
- Cron/worker compatibility is considered with the deployed API version.
- Cold-start login, map discovery/show-all, tool sessions, catalogs/media, profile, weather, and notifications receive a smoke test proportional to the release.
- Logs and readiness are monitored after deploy; rollback criteria are known.
