# Documentation index

This directory is the engineering handbook for Mesozoica. It is organized for progressive disclosure: agents should start small and open deeper references only when their task crosses that boundary.

## Start here

| Document | Use it for |
| --- | --- |
| [`../AGENTS.md`](../AGENTS.md) | Fast agent onboarding, rules, ownership, workflow, and traps |
| [`../README.md`](../README.md) | Repository overview and first-run commands |
| [`DOMAIN.md`](DOMAIN.md) | Product vocabulary, game state, and end-to-end flows |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | System shape, dependency boundaries, composition, and data flow |
| [`DEVELOPMENT.md`](DEVELOPMENT.md) | Setup, environment, change recipes, and debugging |
| [`CONTRACTS.md`](CONTRACTS.md) | Compatibility surfaces that refactors must preserve |
| [`TESTING.md`](TESTING.md) | Test strategy, commands, fixtures, and verification matrix |
| [`OPERATIONS.md`](OPERATIONS.md) | Deployment, migrations, Railway services, workers, jobs, media, and incidents |

## Specialized references

These are canonical for their narrow subsystem:

| Subsystem | Reference |
| --- | --- |
| Scheduled ingestion and generation jobs | [`../backend/app/crons/README.md`](../backend/app/crons/README.md) |
| Game-config documents and domain meanings | [`../backend/app/game_config/README.md`](../backend/app/game_config/README.md) |
| Field ensure worker | [`../backend/app/workers/README.md`](../backend/app/workers/README.md) |
| Administrative and media scripts | [`../backend/scripts/README.md`](../backend/scripts/README.md) |
| Map site-marker rendering contract | [`../flutter/docs/map_site_markers.md`](../flutter/docs/map_site_markers.md) |
| Flutter Mapbox setup | [`../flutter/README.md`](../flutter/README.md) |
| Product direction and historical milestones | [`PRODUCT.md`](PRODUCT.md) |

## Task-oriented reading paths

For an API or backend domain change, read `AGENTS.md`, `DOMAIN.md`, the backend sections of `ARCHITECTURE.md`, `CONTRACTS.md`, and the closest backend tests.

For a Flutter feature change, read `AGENTS.md`, `DOMAIN.md`, the Flutter sections of `ARCHITECTURE.md`, `CONTRACTS.md`, and the feature's controller/repository tests.

For map or location behavior, additionally read the marker contract and trace discovery mode, cache selection, viewport, polling, filters, annotation reconciliation, and optional overlays as separate stages.

For game-balance or configuration work, additionally read the game-config control-board guide. Changes must be interpreted on both backend and Flutter, even when only one side produces the outcome.

For production or data-pipeline work, read `OPERATIONS.md` plus the cron, worker, or scripts guide. Assume commands are mutating until proven otherwise.

## Documentation ownership

- Update documentation in the same change as the behavior or structure it describes.
- Keep cross-cutting concepts here; keep implementation details beside the owning subsystem.
- Prefer links over duplicated command inventories.
- Code, migrations, tests, and generated OpenAPI are authoritative. If prose disagrees, fix the prose and investigate whether a contract test is missing.
- Run `make docs-check` after moving or renaming Markdown files.
