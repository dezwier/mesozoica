# Testing and quality guide

## Quality gate

From the repository root:

```bash
make quality
```

This runs architecture boundaries, the full backend suite, Flutter analysis, and the full Flutter suite. `flutter analyze --no-fatal-infos` means warnings/errors fail while the existing informational baseline remains non-fatal. Documentation integrity is also checked by the quality target.

For a fast structural pass:

```bash
make architecture-check
make architecture-report
make docs-check
git diff --check
```

The structure report is advisory; large-file output is a prompt for judgment, not an automatic failure.

## Backend tests

Run all:

```bash
make backend-test
```

Run focused tests:

```bash
cd backend
.venv/bin/python -m pytest tests/test_sites_api.py -q
.venv/bin/python -m pytest tests/test_openapi_contract.py tests/test_model_registry.py -q
.venv/bin/python -m pytest -k 'field and not slow' -q
```

The suite covers:

- API authentication, validation, pagination, and response behavior;
- site discovery, identification, exploration, dimensions, field generation, and coordinate filtering;
- specimen catalogs, ownership, discard, and curated images;
- tool budgets and individual session types;
- XP, levels, skills, titles, walking distance, and main parameters;
- config parsing/provider/version/seed behavior;
- ingestion parsing, validation, resume, and sync behavior;
- cron Railway guards, weather, notifications, and provider logic;
- OpenAPI compatibility and explicit model registration.

Backend tests should replace database dependencies with isolated fixtures. Tests for external services must use fakes/recorded fixtures; they must not require network access or production credentials.

## Flutter tests

Run all:

```bash
make flutter-test
```

Run focused:

```bash
cd flutter
flutter test test/api_client_auth_retry_test.dart
flutter test test/map_controller_test.dart
flutter test test/mapbox_site_annotation_manager_test.dart
flutter test test/dinosaur_catalog_controller_test.dart
```

The Flutter suite includes model/DTO decoding, transport auth and retry behavior, repositories, controller state machines, caches, map/marker collaborators, session restoration and tool HUD logic, catalog/card widgets, navigation/shell behavior, config parsing, and formatting/layout calculations.

Tests must initialize or fake platform plugins instead of leaking real plugin calls. They must not depend on network, a signed-in user, Mapbox runtime, Firebase, or persistent device state unless the test supplies a controlled adapter.

## Verification by change type

| Change | Minimum focused verification | Broader verification |
| --- | --- | --- |
| Backend domain rule | direct domain/use-case tests | backend suite |
| Router/schema/API | endpoint tests, OpenAPI contract | backend suite |
| SQLModel move | model registry/fingerprint, API tests | backend suite and Alembic check |
| Cron/provider | job tests, Railway guard, fake provider | backend suite |
| Flutter repository/transport | captured request/fixture/error tests | Flutter suite and analyzer |
| Controller/cache | controller state-transition tests | Flutter suite |
| Map rendering | annotation/manager/controller tests | Flutter suite, analyzer, manual device smoke |
| Widget/navigation | widget tests; golden if appearance is the contract | Flutter suite and manual smoke |
| Game config | parsers on both sides and affected rules | both suites |
| Cross-feature refactor | architecture check plus characterization tests | `make quality` |
| Documentation | `make docs-check` | quality gate |

## Contract tests

`backend/tests/test_openapi_contract.py` detects changes in paths, methods, parameters, security, and response schemas. `backend/tests/test_model_registry.py` guards persistence registration/metadata. Flutter repository and transport tests capture URI, headers, body, timeout/error mapping, and JSON defaults.

When a contract test fails during a refactor, assume the code changed behavior. Compare the generated/actual structure before considering a fixture update.

## Determinism

Gameplay code involving time or randomness should accept controlled providers or use existing deterministic seams. Tests should fix seeds/clocks and assert outcomes, not merely ranges, when compatibility is required. Polling/backoff tests should use fake time where possible rather than real sleeps.

## Manual smoke testing

For cross-stack or release-bound changes, verify on a supported device against the intended API environment:

1. cold launch and cached login;
2. archive/field switching and location permission handling;
3. scan, site markers, show-all, linked, filters, selection, and camera;
4. site discovery/identification/exploration;
5. tool action and active-session restoration;
6. dinosaur/fossil/tool/site catalogs and image-version selection;
7. Tree and Profile navigation/state retention;
8. weather and notifications;
9. logout/login and first authenticated request.

Record the platform, API base URL, build mode, and exact scenarios when reporting a manual pass.

## Reporting verification

State exact commands and results. Distinguish automated tests from manual smoke tests, and identify anything skipped because it requires credentials, a device, Railway, or production data. Never report a suite as passing based on a focused subset.
