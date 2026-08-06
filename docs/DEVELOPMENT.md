# Development guide

## Prerequisites

- Python 3.10 or newer. The production image currently uses Python 3.11; local `backend/.venv` may use a newer supported interpreter.
- Flutter with a Dart SDK compatible with `^3.10.4` from `flutter/pubspec.yaml`.
- A platform toolchain for the Flutter target you run.
- Railway CLI only for explicitly authorized remote jobs, worker diagnosis, or production data workflows.
- Mapbox public token for map runtime; see [`../flutter/README.md`](../flutter/README.md).

There is intentionally no repository-managed local PostgreSQL stack. Normal backend tests are hermetic. Running the API against real data requires a `DATABASE_URL`, typically Railway's public proxy URL.

## First setup

From the repository root:

```bash
make backend-install
cp backend/.env.example backend/.env
cd flutter && flutter pub get
```

Set at least `DATABASE_URL` in `backend/.env` before importing backend settings or starting the API. For local development, set `ENVIRONMENT=development`. If `SECRET_KEY` is absent locally, tokens become invalid after restart.

If `make backend-runtime-check` reports an unsupported existing virtual environment, recreate `backend/.venv` with Python 3.10+. Do not alter the runtime guard to accommodate Python 3.9 syntax failures.

## Running locally

Backend:

```bash
make run-backend
```

- API: `http://127.0.0.1:8000`
- Swagger: `http://127.0.0.1:8000/docs`
- ReDoc: `http://127.0.0.1:8000/redoc`
- Liveness: `GET /health`
- Database readiness: `GET /ready`

Flutter against deployed API:

```bash
make run-flutter
```

Flutter against a local API:

```bash
cd flutter
flutter run --dart-define=USE_LOCAL_API=true
```

Android emulators normally need:

```bash
flutter run --dart-define=USE_LOCAL_API=true --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

An explicit `API_BASE_URL` takes precedence over `USE_LOCAL_API`. Without either, the app uses the production Railway URL declared in `flutter/lib/config/app_config.dart`.

## Where a change belongs

### Backend

- HTTP validation, auth dependency resolution, and response mapping: `features/<name>/api.py` or `api/`.
- Transaction/use-case orchestration: `features/<name>/application/`.
- Deterministic rules and value types: `features/<name>/domain/`.
- SQL/external clients/provider implementations: `features/<name>/infrastructure/`.
- Persistence types: feature `models.py` or `models/`; register new types in `app/model_registry.py`.
- Cross-feature API: the smallest intentional export in `features/<name>/public.py`.
- Shared geographic/actor/pagination-like value primitive: `app/shared/`, only if genuinely cross-feature and stable.
- Framework/security/database/settings plumbing: `app/core/`.

### Flutter

- API decoding, cache/device adapters, repository implementation: `features/<name>/data/`.
- UI-independent models, contracts, calculations: `features/<name>/domain/`.
- controllers, screens, widgets, formatting: `features/<name>/presentation/`.
- feature provider composition: `features/<name>/providers.dart`.
- intentionally exported feature surface: `features/<name>/<name>.dart`.
- HTTP/auth/token/persistence/routing/design-system plumbing: `lib/core/`.
- root navigation and overlay hosting: `lib/shell/`.

Some global Flutter directories and backend compatibility modules remain. Treat them as migration surfaces. Extend the owning feature and keep a forwarding export only when an existing import contract requires it.

## Safe change recipes

### Add or modify an endpoint

1. Locate its feature router and response schema.
2. Add/modify an application use case; keep the router thin.
3. Keep SQL and provider details out of the router.
4. Add API tests for auth, validation, success, and expected failures.
5. If the public contract intentionally changes, update the OpenAPI snapshot and `docs/CONTRACTS.md`; otherwise the snapshot must remain unchanged.
6. Update the Flutter repository contract/fixture if the client consumes it.

### Add persistence

1. Put the SQLModel type in the owning feature.
2. Add it to `backend/app/model_registry.py`.
3. Generate a new Alembic revision and inspect it manually.
4. Test upgrades and metadata registration. Never edit an old migration to make the current model fit.

Pure refactors should not generate migrations. Run the model registry/fingerprint tests and `alembic check` in an appropriately configured environment.

### Add a Flutter API call

1. Define the repository-facing operation in the owning feature.
2. Use the injected shared `ApiTransport`; do not construct an independent client or read global auth state.
3. Preserve URI encoding, headers, timeout, error text, defaults, and cache semantics.
4. Add a transport/repository contract test that captures the request and fixture decoding.
5. Inject the repository through the feature provider builder.

### Change the map

Read [`../flutter/docs/map_site_markers.md`](../flutter/docs/map_site_markers.md). Test mode switching, show-all, linked-only, filters, viewport changes, scan/polling, selection, camera behavior, marker batches/diffs, and optional overlay failures. Native Mapbox identifiers and rendering order are contracts.

### Change game configuration

Read [`../backend/app/game_config/README.md`](../backend/app/game_config/README.md). Update the canonical backend YAML and confirm Flutter's linked asset. Keep both typed parsers and defaults aligned, then test server rules and client display/prediction. Seed/publish is a production mutation.

### Change ingestion, media, cron, or worker code

Keep `app/crons`, `app/workers`, and script entrypoints thin. Put orchestration under the owning feature and external clients in infrastructure. Use fake providers in tests. Do not execute a live job as a unit-test substitute.

## Debugging by symptom

### `403` on authenticated Flutter calls

Verify startup reloaded the cached token, the repository uses shared transport, the transport merged `Authorization: Bearer ...`, retry/refresh did not erase headers, and the endpoint's auth dependency expects the same identity type. A successful static image load does not validate authenticated image-version metadata calls.

### Site count/cards exist but markers do not

Check, in order: API dataset and mode, user-specific visibility, controller cache, show-all/linked/filter selection, annotation bundle publication, Mapbox source/layer readiness, and optional overlay exceptions. Do not equate persistence with rendering.

### Backend imports fail during tests

Check `DATABASE_URL` setup in test fixtures, Python version, working directory (`backend/` for direct pytest), and whether a new model import caused metadata side effects. Prefer root Make targets.

### Config differs between client and server

Inspect `X-Game-Config-Version`, active DB snapshot, bundled YAML, Flutter asset link, and typed parser defaults. The server remains authoritative for outcomes.

## Before handing off

Run focused tests, then proportionate full checks. Always run:

```bash
make architecture-check
make docs-check
git diff --check
git status --short
```

For broad or cross-stack work, run `make quality`. Report exact checks and any skipped environment-dependent verification.
