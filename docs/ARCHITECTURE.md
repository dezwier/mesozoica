# Mesozoica architecture

Mesozoica is a feature-first modular monolith with two application processes: a FastAPI backend and a Flutter client. Scheduled jobs and a long-running field worker reuse backend feature code as separate entrypoints. PostgreSQL, shared gameplay configuration, and HTTP contracts connect the system.

This document explains structure and dependency direction. For game meaning, read [`DOMAIN.md`](DOMAIN.md); for compatibility rules, read [`CONTRACTS.md`](CONTRACTS.md).

## System context

```text
                        Wikipedia / PBDB / Gemini
                                  |
                                  v
Flutter app  <----HTTP---->  FastAPI API  <----> PostgreSQL
    |                          |   ^                 ^
 Mapbox / Firebase            |   |                 |
                               v   |                 |
                         mounted media          cron + worker
                         and OSM masks          processes
```

The server is authoritative for game outcomes, ownership, permissions, budgets, and progression. Flutter owns interaction state, presentation, platform adapters, local caches, and predictions based on the same versioned configuration.

## Architectural principles

1. Organize by stable business capability, then by layer where the layer has a real responsibility.
2. Depend inward toward domain concepts; keep frameworks and providers at the edges.
3. Make cross-feature dependencies explicit through small public surfaces.
4. Keep process entrypoints and HTTP adapters thin.
5. Centralize platform-wide policy once: authentication, transport, settings, sessions, errors, time/random seams, and composition.
6. Preserve externally observable contracts while structure changes beneath compatibility facades.
7. Use tests and automated import checks to make boundaries executable rather than aspirational.

## Backend

### Composition and request lifecycle

`backend/app/main.py` exports the app built by `app/core/app_factory.py`. The factory registers exception mapping, CORS, game-config version middleware, health routes, the `/api/v1` router, and static media mounts.

```text
FastAPI router
  -> input/schema validation and actor resolution
  -> one feature application use case
  -> domain rule + repository/provider coordination
  -> SQLModel session or infrastructure provider
  -> established response schema
```

Routers should not contain SQL enrichment, permission algorithms, progression calculations, random generation, or multi-feature orchestration.

### Feature packages

`backend/app/features/<feature>/` may contain:

- `api.py` or `api/`: HTTP adapters and route grouping;
- `schemas.py` or `schemas/`: request/response wire DTOs;
- `models.py` or `models/`: SQLModel persistence types;
- `application/`: use cases, orchestration, and transaction boundaries;
- `domain/`: deterministic rules, policies, and value types;
- `infrastructure/`: SQL queries and external provider implementations;
- `jobs/`: feature-owned scheduled/background use cases;
- `public.py`: the supported cross-feature import surface.

Not every feature needs every directory. Empty ceremonial layers are discouraged.

| Feature | Primary responsibility |
| --- | --- |
| `accounts` | identity, profiles, relationships, notifications, devices, distance |
| `field` | procedural generation, survey/ensure queues, field fossils, coordinate policy |
| `game_config` | typed documents, immutable snapshots, releases and revisions |
| `ingestion` | scientific source synchronization and enrichment workflows |
| `media` | curated media versions, sync, generation, and URL resolution |
| `progression` | skills, XP, levels, titles, main parameters |
| `sites` | sites/site types, discovery, identification, exploration, status |
| `specimens` | dinosaur/fossil catalogs and user ownership |
| `tools` | tool catalog, ownership, action budgets, sessions/events |
| `weather` | persisted cell weather, provider access, solar periods |

### Backend dependency direction

```text
api / cron / worker / script entrypoint
                   |
                   v
              application  -----> another feature's public.py
               /      \
              v        v
          domain     ports/contracts
                         ^
                         |
                  infrastructure
```

- Feature code must not import the transitional `app.services` layer.
- A feature may import another feature only through `app.features.<name>.public`.
- Domain code does not depend on FastAPI, a live SQLModel session, or concrete external clients.
- Infrastructure is replaceable at tests/use-case boundaries.
- `app/core` is framework-wide plumbing, not gameplay ownership.
- `app/shared` contains narrow, named cross-feature primitives such as geography—not a generic utility dump.

`backend/scripts/check_architecture.py` enforces the most important import rules.

### Persistence and transactions

SQLModel persistence types are owned by features. Importing a SQLModel class registers table metadata, so `backend/app/model_registry.py` deliberately imports every persistent model once. Alembic uses that registry rather than scanning feature internals or compatibility packages.

`app/core/database.py` owns the engine and FastAPI session dependency. Application use cases define transaction intent; infrastructure helpers perform feature-owned queries. Existing Alembic revisions remain immutable. Structural moves must leave metadata unchanged.

The connection pool uses pre-ping, bounded pool/overflow, recycling, and timeout. Readiness performs `SELECT 1` with an application timeout. Session close errors caused by stale sockets are contained and invalidated.

### Authentication and errors

Core security resolves bearer credentials into actor context; feature application code makes business authorization decisions. External Firebase verification and push delivery belong behind account infrastructure.

Validation, not-found, database timeout/operational, and unhandled errors are mapped centrally. Production hides tracebacks; development includes details for diagnosis. Endpoint extraction must retain status codes and response bodies.

### Game configuration

Canonical YAML documents live at `backend/app/game_config/`. Feature parsers produce typed immutable `GameConfigSnapshot` values. Releases/revisions support an active database-backed version; startup seeds bundled config when necessary and falls back to bundled YAML if seeding fails.

Every API response under `/api/v1` is stamped with `X-Game-Config-Version`. The client sends its loaded version; drift is rate-limited in logs and does not reject the request.

### Background entrypoints

`app/crons/runner.py` and `app/workers/field_ensure_worker.py` are process adapters. Cron schedule/CLI parsing belongs at the edge; scientific sync, media, weather, config, and field logic belongs to feature application/jobs code. External integrations live under infrastructure so tests can replace them.

## Flutter

### Startup and composition

`flutter/lib/main.dart` initializes Flutter binding, splash state, bundled game configuration, cached authentication, Mapbox/platform services, Firebase/push where available, theme/catalog mode, and map tile cache before rendering. Initialization order is behavioral: cached credentials must be available before feature providers issue protected requests.

`lib/core/di/app_providers.dart` is the composition root. It combines feature-level provider builders rather than constructing the full dependency graph in `AppShell`. `AppShell` hosts root navigation and overlays while feature coordinators own feature state/lifecycle.

### Feature packages

`flutter/lib/features/<feature>/` uses layers only when needed:

- `data/`: HTTP DTO decoding, repositories, caches, persistence/device adapters;
- `domain/`: UI-independent models, repository contracts, deterministic calculations;
- `presentation/`: controllers, screens, widgets, and view formatting;
- `providers.dart`: feature dependency composition;
- `<feature>.dart`: intentional cross-feature exports where present.

Some global `controllers`, `services`, `models`, `widgets`, and `screens` remain as compatibility or shared presentation surfaces. New feature logic should not accumulate there.

### Flutter dependency direction

```text
widget / screen
      |
      v
presentation controller ---> another feature's public barrel
      |
      v
domain contract/model
      ^
      |
data repository ---> shared ApiTransport / device adapter
```

- Presentation may depend on domain.
- Data implements domain-facing repository contracts.
- Domain and data may not depend on widgets, screens, or `BuildContext`.
- Cross-feature imports use the target feature's public barrel rather than its internals.
- Core owns common networking, auth/session plumbing, persistence adapters, routing primitives, design system, and DI—not game rules.

### Networking and authentication

One shared API transport owns base URL resolution, authorization headers, game-config version headers, timeouts, decoding, retry/auth refresh behavior, and typed failures. Feature repositories receive it by constructor injection. Token storage has an in-memory view backed by platform persistence; startup reloads the cached token before authenticated repositories are used.

### Discovery map

The map is decomposed into a controller compatibility facade, mode-specific caches, viewport/show-all logic, polling, selection/filters, Mapbox lifecycle/camera, source/layer and annotation reconciliation, gestures, and optional session overlays.

Primary site annotations publish independently of optional overlays. Rendering order, identifier strings, batch/diff rules, and mode/cache behavior are contractual; see [`../flutter/docs/map_site_markers.md`](../flutter/docs/map_site_markers.md).

### Configuration and state

Flutter's typed config facade preserves existing access semantics while document-specific parsers and immutable sections own interpretation. Provider/ChangeNotifier remains the state-management approach. Compatibility controller types allow internal decomposition without rewriting all widget consumers at once.

## Cross-stack data flows

### Catalog read

```text
catalog widget -> controller -> feature repository -> ApiTransport
  -> feature router -> list use case -> SQLModel query
  -> response schema -> DTO/model -> cache -> widget notification
```

### Field discovery

```text
location/viewport -> site repository -> nearby endpoint
  -> site use case -> field public surface -> ensure queue
  -> worker generates filtered sites -> PostgreSQL
  -> polling/query updates mode cache -> annotation reconciliation
```

### Tool session

```text
expedition UI -> session controller -> tool repository
  -> authenticated tool endpoint -> budget/rule validation
  -> session + events persisted -> progression/site effects
  -> response restores/updates HUD and map overlay
```

### Ingestion to card image

```text
cron schedule -> ingestion job -> Wikipedia/PBDB -> catalog snapshot
  -> Gemini enrichment (optional)
  -> curated image generation/review -> sync script
  -> Railway volume + DB URL/version -> API metadata + static media
```

## Compatibility and transitional code

Compatibility facades keep existing imports/types stable while ownership moves. They may re-export feature implementations but must not gain new logic or consumers. Removal requires proving no scripts, migrations, tests, or UI consumers use the old path.

Known transitional surfaces include backend `app/api/v1/endpoints`, `app/services`, and some core config aliases, plus Flutter global controllers/services/models/widgets/screens. Their presence is tracked structural debt, not a contradiction of feature-first ownership.

## Enforcement

```bash
make architecture-check
make architecture-report
make docs-check
```

The boundary check parses Python/Dart imports. The structure report is advisory. Tests guard OpenAPI, model registration, repository requests, controllers, and behavior. Documentation checks validate required guides and local links.

## Decision guide

When unsure where code belongs, ask:

1. Which business capability changes if this code changes?
2. Is it deterministic policy, orchestration, an edge adapter, or presentation?
3. Does another feature need it, or just this feature's public result?
4. Can it be tested without FastAPI, Flutter widgets, plugins, network, or a live database?
5. Is a compatibility facade preserving a consumer, or becoming permanent hidden ownership?

Choose the narrowest owning feature and expose the smallest stable surface.
