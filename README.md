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

### Backend

```bash
make backend-install
cp backend/.env.example backend/.env
# Edit backend/.env — set DATABASE_URL (Railway Postgres or any PostgreSQL instance)
make run-backend
```

API docs: http://localhost:8000/docs  
Health: http://localhost:8000/health

### Flutter

```bash
cd flutter && flutter pub get
make run-flutter
```

Point `flutter/lib/config/app_config.dart` at your backend URL (localhost by default).

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
