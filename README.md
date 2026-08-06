# Mesozoica

Mesozoica is a location-based paleontology game—Pokémon GO meets a scientifically grounded natural-history collection. The monorepo contains a FastAPI/SQLModel/PostgreSQL backend and a Flutter client, plus ingestion, media, scheduled-job, and field-generation tooling.

## Start here

- Coding agents: [`AGENTS.md`](AGENTS.md)
- Documentation index: [`docs/README.md`](docs/README.md)
- Domain and gameplay vocabulary: [`docs/DOMAIN.md`](docs/DOMAIN.md)
- Architecture and boundaries: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- Development setup: [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)
- Production operations: [`docs/OPERATIONS.md`](docs/OPERATIONS.md)
- Product direction: [`docs/PRODUCT.md`](docs/PRODUCT.md)

## Repository layout

```text
backend/                 FastAPI API, feature modules, Alembic, jobs, workers, tests
  app/features/          Feature-owned API/application/domain/infrastructure code
  app/core/              App, settings, DB/session, security, shared errors
  app/shared/            Deliberate cross-feature value primitives
  app/game_config/       Canonical YAML gameplay control board
flutter/                 Flutter application and tests
  lib/features/          Feature data/domain/presentation packages
  lib/core/              Transport, auth/session, persistence, DI, routing primitives
  lib/shell/             Root navigation and overlays
images/                  Versioned curated media source files
docs/                    Engineering, contract, testing, and operations handbook
Makefile                 Supported development and operational entrypoints
railway.toml             Monorepo Railway service root
```

The system is a feature-first modular monolith. Backend features communicate through `public.py`; Flutter features use explicit public barrels. Import rules are checked automatically.

## Quick setup

Requirements: Python 3.10+, a Flutter toolchain compatible with Dart `^3.10.4`, and a `DATABASE_URL` to start the API. Tests do not require a live database.

```bash
make backend-install
cp backend/.env.example backend/.env
# Configure DATABASE_URL before starting FastAPI.

cd flutter && flutter pub get
cd ..
```

Run the backend:

```bash
make run-backend
```

Run Flutter against the deployed API:

```bash
make run-flutter
```

Run Flutter against the local backend:

```bash
cd flutter
flutter run --dart-define=USE_LOCAL_API=true
```

Use `--dart-define=API_BASE_URL=http://10.0.2.2:8000` for an Android emulator or any explicit API override. Mapbox platform setup is documented in [`flutter/README.md`](flutter/README.md).

## Quality

```bash
make quality                 # architecture, docs, backend, analyzer, Flutter tests
make backend-test
make flutter-test
make flutter-analyze
make architecture-check
make architecture-report
make docs-check
```

See [`docs/TESTING.md`](docs/TESTING.md) for focused commands and the verification matrix.

## Runtime and deployment

Production runs on Railway as separate API, cron, worker, and PostgreSQL services. Curated media and coordinate masks use a mounted `/data` volume. API container startup applies Alembic migrations before uvicorn.

Cron jobs and most maintenance commands act on Railway data. Do not run them casually. Read these first:

- [`docs/OPERATIONS.md`](docs/OPERATIONS.md)
- [`backend/app/crons/README.md`](backend/app/crons/README.md)
- [`backend/app/workers/README.md`](backend/app/workers/README.md)
- [`backend/scripts/README.md`](backend/scripts/README.md)

## Key contracts

Structural work must preserve HTTP/OpenAPI behavior, SQLModel metadata and Alembic history, YAML configuration meaning, Flutter model/repository semantics, navigation, visuals, map rendering rules, caching, polling, retry timing, and user-visible behavior. Read [`docs/CONTRACTS.md`](docs/CONTRACTS.md) before a cross-stack refactor.

## Current capabilities

The application includes authentication and profiles; archive and procedural field discovery; Mapbox site rendering; site identification/exploration; dinosaur, fossil, site, and tool catalogs; curated image versions; tool actions and persistent sessions; progression; relationships and notifications; weather; scientific ingestion; and Railway-operated background processing.

Some compatibility modules and global Flutter presentation surfaces remain after the feature-first migration. New code belongs in the owning feature; [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) documents the intended direction and remaining transitional boundaries.
