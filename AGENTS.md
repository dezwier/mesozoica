# AGENTS.md

## Cursor Cloud specific instructions

This repo is a monorepo with two services: a **FastAPI backend** (`backend/`) and a
**Flutter client** (`flutter/`). Standard build/test/run commands live in `README.md`
and the root `Makefile` — prefer those. The notes below only cover cloud‑VM‑specific,
non‑obvious setup that differs from the README.

### Startup each session (not handled by the update script)
- **Start PostgreSQL** (it is not auto‑started on boot):
  `sudo pg_ctlcluster 16 main start` (verify with `sudo pg_lsclusters`).
- The update script only refreshes dependencies (`backend/.venv` + `flutter pub get`).
  It does **not** start services or the DB.

### Database (differs from README)
- README says "no local database" and points `DATABASE_URL` at Railway. In Cursor Cloud
  we run a **local PostgreSQL 16** instead so the backend is self‑contained.
- Database `mesozoica` and role `mesozoica` (password `mesozoica`) already exist in the VM
  snapshot, and `backend/.env` (gitignored) sets
  `DATABASE_URL=postgresql://mesozoica:mesozoica@127.0.0.1:5432/mesozoica`.
  If `backend/.env` is ever missing, recreate it from `backend/.env.example` with that URL,
  a `SECRET_KEY`, and `ENVIRONMENT=development`.
- Schema is auto‑created on backend startup via `init_db()` (SQLModel `create_all`);
  Alembic migrations are only needed on Railway, not locally.

### Backend (Python)
- Deps live in a venv at `backend/.venv` (the Makefile's `.venv/bin/python` targets expect
  this). Activate it (`source backend/.venv/bin/activate`) before `make run-backend` /
  `make backend-test`, or call `backend/.venv/bin/...` directly. `make backend-install`
  installs into the active pip, so activate the venv first.
- Run the API: activate venv, then `make run-backend` (uvicorn on `:8000`, `/docs` for Swagger).
- Tests use in‑memory SQLite by default (`backend/tests/conftest.py`) and do **not** need
  Postgres: `cd backend && .venv/bin/pytest tests/ -q`. ~9 tests currently fail on `main`
  from game‑config/data drift (e.g. tool count, discovery distance/chance, URL encoding),
  unrelated to environment setup.

### Flutter client
- The SDK is installed at `~/flutter` and is on `PATH` via `~/.bashrc`. Standard commands
  (`flutter analyze`, `flutter test`) are in the README. `flutter test` on `main` has ~1
  pre‑existing failure (`period_marker_color_test`) from a hardcoded color vs
  `period_colors.yaml` drift.
- **Running the GUI in the cloud VM:** the app targets iOS/Android; there is no
  device/emulator here, and **web is not supported** (it crashes during init on
  `path_provider` / `MapTileCache.initialize`). Use the **Linux desktop** target instead:
  `export DISPLAY=:1 && flutter run -d linux --dart-define=USE_LOCAL_API=true`.
  A native window appears on X display `:1` (visible to screen capture). `USE_LOCAL_API=true`
  points the app at `http://127.0.0.1:8000`.
- Benign on Linux desktop: "Mapbox token missing" (no `MAPBOX_ACCESS_TOKEN` → map tab
  disabled), "Could not get your location" and geolocator `MissingPluginException`
  (no GPS on desktop).
- **In‑app auth is Firebase‑gated:** the Flutter client's Sign in / Sign up and item
  collection go through `firebase_auth`, which has no Linux config, so they cannot complete
  in the cloud VM. The backend itself exposes working password endpoints
  (`POST /api/v1/auth/register`, `/auth/login`) that can be exercised directly via the API
  (e.g. `curl`) for end‑to‑end backend testing.

### Seeding catalog data locally (no network / no Railway)
- Cron/sync jobs are Railway‑gated; bypass the guard with `ALLOW_LOCAL_CRON=1`.
- Tools load from a bundled JSON (no external calls):
  `cd backend && ALLOW_LOCAL_CRON=1 .venv/bin/python -m app.crons.runner --job tool_sync`.
  Dinosaurs/fossils/sites need external APIs (Wikipedia/PBDB) or Railway and aren't required
  for local UI work.
- The Tools **catalog** view only lists tools whose `main_image_url` is set (a curated image),
  and cards render as silhouettes until a tool is owned.
