# Mesozoica

Location-based paleontology game — monorepo scaffold.

## Repository layout

```
mesozoica/
├── backend/   # FastAPI + PostgreSQL (Railway)
├── flutter/   # Flutter mobile app (iOS & Android)
├── prd.md     # Product requirements
└── Makefile   # Dev commands
```

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
make run-wikipedia-sync                        # weekly Wikipedia ingest
make run-wikipedia-sync CRON_EXTRA='--overwrite' # force re-fetch all
make run-dinosaur-enrich                         # LLM enrichment
make run-dinosaur-enrich CRON_EXTRA='--overwrite'
```

Do **not** run `python -m app.crons.runner` directly — it is blocked unless executed on Railway or via `make run-*`.

**Scheduled runs:** deploy a Railway **cron service** with config [`backend/railway.cron.toml`](backend/railway.cron.toml) (`cronSchedule = "0 * * * *"`). Jobs in [`backend/app/crons/crons.yaml`](backend/app/crons/crons.yaml) fire weekly (UTC).

Set on Railway (**backend** and **cron** services): `DATABASE_URL`, `SECRET_KEY`, `WIKIPEDIA_USER_AGENT`, `GOOGLE_GEMINI_API_KEY`, etc.

### Flutter

```bash
cd flutter && flutter pub get
make run-flutter
```

Point `flutter/lib/config/app_config.dart` at your backend URL. By default the app uses the deployed Railway API (`https://mesozoica-production.up.railway.app`). For local backend dev:

```bash
# iOS Simulator / macOS
flutter run --dart-define=USE_LOCAL_API=true

# Android Emulator
flutter run --dart-define=USE_LOCAL_API=true --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

### Tests

```bash
make test-all
```

## Railway deployment

1. Create a Railway project and add a **PostgreSQL** database.
2. Add a **backend** service with root directory `backend`.
3. Link `DATABASE_URL` from the Postgres service to the backend service.
4. Set service variables:
   - `SECRET_KEY` — random secret for signing tokens
   - `ENVIRONMENT=production`
   - `CORS_ORIGINS` — comma-separated allowed origins (no `*` in production)
5. Deploy. Railway runs migrations then starts uvicorn via the Dockerfile.

The root [`railway.toml`](railway.toml) declares the backend service root for monorepo deploys.

## Status

Core scaffold only — no domain models, migrations, or game screens yet. See [`prd.md`](prd.md) for the full product vision and implementation checklist.
