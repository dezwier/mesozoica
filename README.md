# Mesozoica

Location-based paleontology game — FastAPI backend + Flutter client monorepo.

## Repository layout

```
mesozoica/
├── backend/                 # FastAPI + SQLModel + PostgreSQL (Railway)
│   ├── app/
│   │   ├── features/        # Feature-owned API/application/domain/infrastructure
│   │   ├── core/            # App, DB/session, security, settings, errors
│   │   ├── shared/          # Deliberate cross-feature value primitives
│   │   ├── api/v1/          # Transitional route compatibility exports
│   │   ├── services/        # Transitional import compatibility exports
│   │   ├── crons/           # Thin scheduled-job entrypoints
│   │   ├── workers/         # Thin worker entrypoints
│   │   └── game_config/     # Shared YAML game mechanics
│   ├── alembic/             # DB migrations
│   └── tests/
├── flutter/                 # Flutter app (iOS, Android, web/desktop targets)
│   └── lib/
│       ├── features/        # Feature data/domain/presentation packages
│       ├── core/            # Networking, persistence, DI, routing primitives
│       ├── shell/           # Root navigation and overlay hosting
│       └── controllers|services|models|widgets/ # Transitional exports/UI
├── images/                  # Curated card / user images (v1/v2 dirs)
├── prd.md                   # Product requirements
├── Makefile                 # Dev / test / cron entrypoints
└── railway.toml             # Monorepo deploy (backend root)
```

**Shared game config:** YAML under [`backend/app/game_config/`](backend/app/game_config/) is linked into Flutter assets. Typed document parsers live in each side's `features/game_config` package; compatibility facades preserve the old access API.

## Architecture notes

The enforceable dependency rules and compatibility contracts live in
[`ARCHITECTURE.md`](ARCHITECTURE.md). Run `make architecture-check` when moving
code between features.

- Backend features expose cross-feature capabilities only through `public.py`.
- Backend dependency direction is `api/entrypoint → application → domain`; providers and SQL adapters live under infrastructure.
- Flutter dependency direction is `presentation → domain`; data repositories implement domain-facing contracts and share one injected API transport.
- Compatibility modules preserve internal import paths for scripts and tests, but new consumers must use feature surfaces.

## Local development

There is **no local database**. The API can run on your machine for debugging, but **cron jobs always run on Railway** (scheduled service or `make run-*` via `railway run`).

### Backend API (optional local)

Python 3.10 or newer is required. The Make targets reject an existing
`backend/.venv` created with an older interpreter instead of silently reusing
it; recreate that environment with a supported Python when prompted.

```bash
make backend-install
cp backend/.env.example backend/.env
# Set DATABASE_URL to Railway Postgres public URL (*.proxy.rlwy.net) if testing API locally
make run-backend
```

API docs: http://localhost:8000/docs  
Health: http://localhost:8000/health

### Cron jobs (Railway only)

Install the [Railway CLI](https://docs.railway.app/develop/cli) and link your project:

```bash
cd backend && railway link
```

Run jobs against **Railway Postgres** (uses the linked service's `DATABASE_URL` and secrets):

```bash
make run-dinosaur-wiki-sync                        # weekly Wikipedia ingest
make run-dinosaur-wiki-sync CRON_EXTRA='--overwrite' # force re-fetch all
make run-dinosaur-llm-enrich                         # LLM enrichment
make run-dinosaur-llm-enrich CRON_EXTRA='--overwrite'
```

Do **not** run `python -m app.crons.runner` directly — it is blocked unless executed on Railway or via `make run-*`.

**Scheduled runs:** deploy a Railway **cron service** with config [`backend/railway.cron.toml`](backend/railway.cron.toml) (`cronSchedule = "0 * * * *"`). Jobs in [`backend/app/crons/crons.yaml`](backend/app/crons/crons.yaml) fire weekly (UTC).

**Field ensure worker:** long-running process via [`backend/railway.worker.toml`](backend/railway.worker.toml) (`app.workers.field_ensure_worker`).

Set on Railway (**backend**, **cron**, and **worker** services): `DATABASE_URL`, `SECRET_KEY`, `WIKIPEDIA_USER_AGENT`, `GOOGLE_GEMINI_API_KEY`, etc.

### Flutter

```bash
cd flutter && flutter pub get
make run-flutter
```

By default the app uses the deployed Railway API (`https://mesozoica-production.up.railway.app`). For local backend dev:

```bash
# iOS Simulator / macOS
flutter run --dart-define=USE_LOCAL_API=true

# Android Emulator
flutter run --dart-define=USE_LOCAL_API=true --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

### Tests

```bash
make test-all
# or separately:
make backend-test
make flutter-analyze
make flutter-test

# Full structural quality gate:
make quality
```

## Railway deployment

1. Create a Railway project and add a **PostgreSQL** database.
2. Add a **backend** service with root directory `backend`.
3. Link `DATABASE_URL` from the Postgres service to the backend service.
4. Set service variables:
   - `SECRET_KEY` — random secret for signing tokens
   - `ENVIRONMENT=production`
   - `CORS_ORIGINS` — comma-separated allowed origins (no `*` in production)
5. Optionally add **cron** and **worker** services using `backend/railway.cron.toml` and `backend/railway.worker.toml`.
6. Deploy. Railway runs migrations then starts uvicorn via the Dockerfile.

The root [`railway.toml`](railway.toml) declares the backend service root for monorepo deploys.

## Status

Full domain app: SQLModel models + Alembic migrations, field generation, tool actions (aerial / guidance / formation), catalogs, auth, and Flutter map/game screens. See [`prd.md`](prd.md) for product vision and checklist.
