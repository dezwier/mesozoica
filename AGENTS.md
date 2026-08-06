# Agent guide

This is the fastest reliable entry point for coding agents working in Mesozoica. Read this file before editing. Follow the linked guides only as deeply as the task requires.

## What this repository is

Mesozoica is a location-based paleontology game: a FastAPI/SQLModel/PostgreSQL backend and a Flutter client. Players discover archive and procedurally generated field sites, use tools, collect fossils and dinosaurs, progress skills, and browse scientific catalogs.

The repository is a feature-first modular monolith. The backend and client are deployed separately but share HTTP, game-configuration, and behavioral contracts.

## Read in this order

1. [`README.md`](README.md) for the repository and command overview.
2. [`docs/DOMAIN.md`](docs/DOMAIN.md) for game terminology and end-to-end flows.
3. [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for boundaries, composition, and data flow.
4. [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) before changing code.
5. [`docs/CONTRACTS.md`](docs/CONTRACTS.md) before changing APIs, persistence, config, auth, caching, map behavior, or navigation.
6. [`docs/TESTING.md`](docs/TESTING.md) to select the right verification.
7. [`docs/OPERATIONS.md`](docs/OPERATIONS.md) for Railway, jobs, workers, migrations, media, and production diagnosis.

The complete documentation index is [`docs/README.md`](docs/README.md). Product direction lives in [`docs/PRODUCT.md`](docs/PRODUCT.md); code and contract tests are authoritative when the product document describes an older milestone.

## Non-negotiable rules

- Preserve public API paths, methods, parameters, status codes, JSON shapes, and authentication behavior unless the task explicitly changes a contract.
- Do not edit existing Alembic revisions. New persistence changes require a new migration. Pure refactors must leave SQLModel metadata unchanged.
- Backend cross-feature imports go through `app.features.<feature>.public` only.
- Flutter cross-feature imports go through `features/<feature>/<feature>.dart` where that feature exports a public barrel.
- Backend dependency direction is `api or entrypoint -> application -> domain`. Infrastructure implements external and persistence details.
- Flutter dependency direction is `presentation -> domain`; data implements repository contracts. Domain/data code must not import widgets, screens, or `BuildContext`.
- Keep gameplay logic out of `backend/app/core` and `flutter/lib/core`. Core is platform-wide plumbing.
- Preserve the YAML documents under `backend/app/game_config/`. Flutter consumes linked copies under `flutter/assets/game_config/`; do not let the two drift.
- Preserve map source/layer identifiers, marker diff semantics, rendering order, camera behavior, cache switching, polling, and retry timing unless the task explicitly changes them.
- Do not add new imports from transitional backend `app.services` or global Flutter layers. Existing compatibility modules may remain until their consumers move.
- Never assume a clean worktree. Inspect `git status`, preserve unrelated user changes, and review the final diff.
- Never run production-mutating jobs just to validate code. Cron, sync, prune, backfill, migration, and image upload commands require explicit task scope.

## Repository map

```text
backend/
  app/main.py                 Minimal ASGI export
  app/core/                   App factory, settings, DB/session, auth primitives, errors
  app/features/               Feature-owned backend code
  app/shared/                 Small deliberate cross-feature value primitives
  app/api/v1/                 Route aggregation and compatibility endpoints
  app/crons/                  Thin scheduled-job entrypoints and schedule
  app/workers/                Thin long-running worker entrypoints
  app/game_config/            Canonical YAML gameplay documents
  app/model_registry.py       Explicit SQLModel/Alembic model registration
  alembic/                    Immutable migration history plus future revisions
  tests/                      API, contract, domain, job, and integration tests
flutter/
  lib/main.dart               Process startup
  lib/core/                   Networking, token storage, DI, platform plumbing
  lib/features/               Feature data/domain/presentation packages
  lib/shell/                  Root navigation and overlays
  lib/controllers|services|models|widgets|screens/
                              Transitional surfaces and shared presentation code
  test/                       Unit, repository, controller, and widget tests
images/                       Versioned curated media source files
docs/                         Cross-cutting engineering and operations guides
```

Backend feature ownership:

| Feature | Owns |
| --- | --- |
| `accounts` | auth identities, users, profiles, relationships, notifications, devices, walking distance |
| `field` | procedural field sites, ensure/survey queues, field fossil generation, coordinate filtering |
| `game_config` | typed YAML parsing, immutable snapshots, releases/revisions, active config |
| `ingestion` | Wikipedia, PBDB, Gemini enrichment, and catalog synchronization workflows |
| `media` | curated image versions, serving metadata, sync, and generation |
| `progression` | skills, XP, levels, titles, and main parameters |
| `sites` | archive/field site APIs, discovery, identification, exploration, status, site types |
| `specimens` | dinosaur and fossil catalogs plus user ownership |
| `tools` | tool catalog, ownership, actions, budgets, and sessions |
| `weather` | weather persistence/provider and solar period rules |

Flutter feature ownership:

| Feature | Owns |
| --- | --- |
| `collection` | dinosaur, fossil, and tool repositories/catalog composition |
| `discovery` | sites, discovery map, marker reconciliation, viewport, filters, selection, polling |
| `expeditions` | tool action/session composition |
| `game_config` | bundled YAML loading and typed immutable config sections |
| `notifications` | notification repository and providers |
| `phylogeny` | tree layout and presentation |
| `profile` | auth/profile repositories and providers |
| `progression` | progression provider composition |
| `social` | relationship repository |

## Standard workflow

1. Run `git status --short` and locate the feature on both sides of the API boundary.
2. Read the nearest tests and the feature's `public.py`, barrel, provider builder, or router.
3. For regressions, trace the full path: UI/controller -> repository/transport -> endpoint -> use case -> persistence/provider.
4. Make the smallest coherent feature-owned change. Add a characterization test before risky extraction or behavior-preserving refactoring.
5. Run focused tests while iterating, then the relevant full suite.
6. Run `make architecture-check`, `make docs-check`, and review `git diff --check` plus `git diff --stat`.
7. For broad changes, finish with `make quality`.

## Commands agents should know

Run root Make targets from the repository root.

```bash
make backend-install          # create/install backend/.venv; Python 3.10+
make run-backend              # local FastAPI server, using backend/.env
make backend-test             # complete backend suite
make flutter-test             # complete Flutter suite
make flutter-analyze          # analyzer; infos are currently non-fatal
make architecture-check       # enforce feature import boundaries
make architecture-report      # advisory file-size/structure report
make docs-check               # validate required docs and local Markdown links
make quality                  # structural checks, both suites, analyzer
```

Focused examples:

```bash
cd backend && .venv/bin/python -m pytest tests/test_sites_api.py -q
cd backend && .venv/bin/python -m pytest tests/test_openapi_contract.py tests/test_model_registry.py -q
cd flutter && flutter test test/api_client_auth_retry_test.dart
cd flutter && flutter test test/map_controller_test.dart
```

## High-risk areas and common traps

- Authentication: Flutter requests must use the shared transport/token store. Direct `http` calls can omit bearer tokens, config headers, timeout behavior, and typed errors.
- Startup auth: the cached token is loaded before providers make authenticated requests. Changing initialization order can produce first-request `403` failures.
- Map markers: archive, field, linked, and show-all datasets have separate cache/reconciliation semantics. Optional overlays must not prevent primary site annotations from publishing.
- Game config: the server is authoritative. API responses include `X-Game-Config-Version`; Flutter sends its loaded version. Parsers on both sides must retain defaults and document semantics.
- Field generation: site counts can represent queued or cached data that is not currently rendered. Trace ensure queues, viewport mode, filters, and annotation publication separately.
- SQLModel: importing a model registers metadata. Alembic imports only `app/model_registry.py`; keep it explicit and test the fingerprint.
- Jobs: `make run-*` commands generally execute with Railway credentials and may mutate production data. Read the relevant operations guide first.
- Media: catalog records and image-version APIs are authenticated independently of static file serving. A visible card does not prove version metadata calls are authorized.
- Compatibility code: global Flutter folders and backend compatibility packages are not an invitation for new ownership. Put new logic in the owning feature.
- Tests: backend tests use isolated fixtures and dependency overrides. Do not point a test at production PostgreSQL.

## Definition of done

A change is done when its behavior is covered, the relevant tests pass, architecture and documentation checks pass, local links are valid, unrelated changes remain untouched, and the final summary states what changed, what was verified, and any remaining risk. Structural work is not complete merely because forwarding files or package skeletons exist.
