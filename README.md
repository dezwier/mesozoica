# Mesozoica

Location-based paleontology game — FastAPI backend + Flutter client monorepo.

## Repository layout

```
mesozoica/
├── backend/                 # FastAPI + SQLModel + PostgreSQL (Railway)
│   ├── app/
│   │   ├── api/v1/          # HTTP routers (thin; call services)
│   │   ├── schemas/         # Pydantic request/response DTOs
│   │   ├── services/        # Domain logic
│   │   │   ├── site_service/      # Site catalog / discover / status
│   │   │   ├── field_service/     # Field generation, ensure queue, purge
│   │   │   ├── site_common/       # Shared geo / labels / discovery params
│   │   │   ├── tool_service/      # Tool catalog
│   │   │   ├── tool_action_service/  # Aerial, guidance, formation actions
│   │   │   └── …                # Enrichment, images, auth, etc.
│   │   ├── models/          # SQLModel tables
│   │   ├── crons/           # Scheduled jobs (Railway cron service)
│   │   ├── workers/         # Long-running field-ensure worker
│   │   └── game_config/     # Shared YAML game mechanics
│   ├── alembic/             # DB migrations
│   └── tests/
├── flutter/                 # Flutter app (iOS, Android, web/desktop targets)
│   └── lib/
│       ├── config/          # AppConfig, ApiEndpoints, GameConfig
│       ├── controllers/     # Provider ChangeNotifiers
│       ├── services/        # HTTP + device services
│       ├── models/          # Client DTOs
│       ├── screens/         # Feature screens
│       ├── shell/           # App chrome / overlays
│       └── widgets/         # UI (map, cards, tools, tree, …)
├── images/                  # Curated card / user images (v1/v2 dirs)
├── prd.md                   # Product requirements
├── Makefile                 # Dev / test / cron entrypoints
└── railway.toml             # Monorepo deploy (backend root)
```

**Shared game config:** YAML under [`backend/app/game_config/`](backend/app/game_config/) is the game-mechanics control board. The backend serves it at `GET /api/v1/game-config`, and the Flutter client fetches it at startup (falling back to an on-device cache, then the bundled YAML) so tuning ships without an app release. Typed loaders live on both sides (`core/game_config.py` and `lib/config/game_config.dart`). See [`docs/game-config.md`](docs/game-config.md) for the delivery architecture and the roadmap toward a DB-backed, live-editable single source of truth.

## Architecture notes

- **Endpoints stay thin** — parse HTTP, call a service, return a schema. Domain SQL lives in services.
- **Prefer service packages** with `__init__.py` facades (`site_service`, `field_service`, `tool_service`, …). Import public entry points from the package when possible; deep submodule imports are for internal use.
- **Field vs site:** playable field generation/ensure lives in `field_service`; catalog list/nearby/related stays in `site_service`; shared helpers in `site_common`.
- **Flutter layering:** `widget → controller → service`. Controllers should not import widgets for pure helpers (see `lib/utils/`).

## Local development

There is **no local database**. The API can run on your machine for debugging, but **cron jobs always run on Railway** (scheduled service or `make run-*` via `railway run`).

### Backend API (optional local)

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
make flutter-test
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
