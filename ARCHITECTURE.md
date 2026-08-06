# Mesozoica architecture

Mesozoica is a feature-first modular monolith. HTTP and database contracts are
shared between a FastAPI backend and a Flutter client; feature internals are
not shared across boundaries.

## Dependency rules

- Backend entrypoints call feature application APIs. A feature may consume
  another feature only through `app.features.<feature>.public`.
- Backend domain code contains deterministic game rules and does not depend on
  FastAPI, SQLModel sessions, or external clients. Infrastructure implements
  the ports required by application code.
- Flutter presentation depends on feature domain APIs. Data code implements
  repository contracts and does not import widgets, screens, or `BuildContext`.
- `backend/app/core` and `flutter/lib/core` contain platform-wide plumbing, not
  gameplay rules.
- Existing compatibility facades remain valid only while code is being moved;
  new cross-feature imports must use feature public surfaces.

Run `make architecture-check` before committing. The check is intentionally
fast and complements, rather than replaces, backend tests, `flutter test`, and
`flutter analyze`.

## Compatibility contracts

Structural changes must preserve API paths and schemas, SQLModel table
metadata and Alembic history, shared YAML documents, navigation, rendering,
game outcomes, caching, and retry behavior. A structural change that alters
one of these is treated as a functional change and must be reviewed separately.

