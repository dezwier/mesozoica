# Compatibility contracts

This document defines the surfaces that structural work must preserve. If a task intentionally changes one, treat it as product/API work: name the change, update tests and documentation, and coordinate both sides.

## HTTP API

The following are public behavior:

- route path and API prefix (`/api/v1` by default);
- HTTP method;
- path/query/header/body parameter names, types, requiredness, and defaults;
- authentication and authorization requirements;
- success and failure status codes;
- response JSON field names, types, nullability, defaults, nesting, and pagination;
- error body shape and user-visible error text relied upon by Flutter;
- static media paths under `/media/dinosaurs`, `/media/fossils`, `/media/site-types`, `/media/tools`, and `/media/users`;
- `X-Game-Config-Version` request/response behavior.

FastAPI validation errors use `422` with `{"detail": [...]}`. Application validation/not-found errors map to `400`/`404` with `detail` and `type`. Temporary database failures map to `503`. Development may expose traceback details; production must not.

The generated OpenAPI contract is guarded by `backend/tests/test_openapi_contract.py`. Refactors must not update its expected snapshot just to make a failure disappear.

Site documentation sync uses `PATCH /api/v1/users/me/site-exploration` with
`documentation_progress` in the unit interval for each site. Progress is
monotonic, requires prior identification, and freezes after completion.

## Authentication and session transport

Flutter's shared transport owns bearer-token application, cached-token startup behavior, token retry/refresh behavior, game-config version headers, timeout, decoding, and typed failures. Repositories must not reproduce these policies.

The first authenticated request after launch is part of the contract: startup must restore cached credentials before feature providers initiate requests. Explicit per-request headers must merge predictably with transport-owned headers.

Backend routers resolve authenticated actor context through shared security primitives. Permission algorithms belong in application/domain code and must produce the same status and error semantics after extraction.

## Database and migrations

Table names, columns, types, constraints, defaults, indexes, relationships, and existing data meaning are persistence contracts.

- Existing files under `backend/alembic/versions/` are immutable history.
- `backend/app/model_registry.py` is the only explicit aggregate registration point for feature-owned SQLModel types used by Alembic.
- A structural move must keep metadata fingerprints identical and produce no migration.
- A deliberate schema change needs a new revision, reviewed SQL, upgrade verification, and appropriate compatibility strategy.
- `init_db()` creates registered tables for fresh/test environments; production startup applies Alembic first.

## Game configuration

Canonical documents live under `backend/app/game_config/` and are exposed to Flutter as assets. Contracts include:

- filenames/document IDs and YAML structure;
- active-version and release/revision behavior;
- fallback/default behavior when a value is absent;
- deterministic interpretation of values on both platforms;
- checksum/canonicalization semantics;
- server-authoritative outcomes;
- `X-Game-Config-Version` observability.

See [`../backend/app/game_config/README.md`](../backend/app/game_config/README.md) before editing a document or parser.

## Flutter model and repository behavior

Contracts include request URLs and encoding, headers, payloads, response defaults, error mapping/text, timeouts, retry behavior, pagination, ordering, caching, cache invalidation, polling/backoff, session restoration, and controller notification timing where the UI relies on it.

Constructor injection is the supported seam. A compatibility controller or service may keep its old public type while delegating to feature collaborators; moving code must not require simultaneous visual or navigation changes.

## Navigation and visuals

Route names, bottom-tab identity/order, deep links, overlay ownership, state retention, back behavior, and visible interaction flows are compatibility surfaces.

For map presentation, preserve:

- archive/field/linked/show-all/filter mode semantics;
- mode-specific caches and switching behavior;
- marker diff and batching rules;
- Mapbox source, layer, and annotation identifiers;
- rendering order and visibility;
- camera/viewport behavior and selection;
- polling/backoff and field ensure behavior;
- independence of primary markers from optional overlays.

The detailed marker rules live in [`../flutter/docs/map_site_markers.md`](../flutter/docs/map_site_markers.md).

### Celebration delivery

Site discovery, identification, and documentation celebrations use one
application-wide FIFO. The celebration host is above the root navigator, so it
must remain visible over shell screens, drawers, dialogs, and card routes. A
matching entity card is dismissed before its celebration; unrelated overlays
remain underneath. Haptic feedback and notification mark-read happen when the
celebration becomes visible, not when it is queued.

Every celebration has a durable user notification and a best-effort push.
Foreground response descriptors and FCM payloads identify the notification by
`notification_id`, `type`, and `site_id`. Background/terminated events remain
unread and are replayed oldest-first on resume. Triggering API responses may
add an optional `celebration` descriptor, or `celebrations` when one request can
complete several events; existing response fields and paths remain stable.

## Background processing

Cron and worker contracts include schedule interpretation, job names/CLI flags, idempotency, resume/overwrite semantics, batching, retry behavior, queue states, transaction boundaries, logs used in operations, and protection against accidental local production runs.

External providers—Wikipedia, PBDB, Gemini, Firebase, geocoding, weather, filesystem/volume, and coordinate masks—must remain behind feature-owned interfaces or infrastructure adapters so tests can use deterministic fakes.

## Media

Curated media has three related contracts:

1. repo source files and version metadata under `images/`;
2. authenticated metadata/version endpoints and database URLs;
3. static files served by the API from configured local/Railway directories.

Version folder naming, `meta.yaml`, public URLs, entity matching, pruning behavior, and upload paths must stay synchronized. Read [`../backend/scripts/README.md`](../backend/scripts/README.md) before running sync or migration scripts.

## Structural refactor checklist

- API/OpenAPI comparison is unchanged.
- Existing Alembic history is untouched and model metadata is unchanged.
- YAML documents and linked Flutter assets are unchanged unless explicitly intended.
- Backend features import one another only through `public.py`.
- Flutter cross-feature imports use feature barrels; domain/data remain presentation-independent.
- Shared transport remains the only owner of common request policy.
- Controller, cache, marker, polling, navigation, and session behavior has characterization coverage.
- Cron/worker entrypoints remain thin and preserve job semantics.
- `make architecture-check`, `make docs-check`, relevant tests, and analyzer pass.
