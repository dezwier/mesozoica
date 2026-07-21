# Game config control board

Single source of truth for Mesozoica game-mechanics knobs.

- **Backend** loads these YAML files via `app.core.game_config`.
- **Flutter** loads the same files via the symlink
  `flutter/assets/game_config` → `backend/app/game_config`.

## Domains

| File | Purpose |
|------|---------|
| `site_generation.yaml` | Field site density, spacing, geology blend, client ensure triggers |
| `site_discovery.yaml` | Proximity + discovery_chance to discover a site (server + client) |
| `fossil_generation.yaml` | Dino/card spawn weights on survey |
| `fossil_discovery.yaml` | Stub — fossil proximity discovery (future) |
| `fossil_excavation.yaml` | Stub — excavation timing/loot (future) |

## Adding a new domain

1. Add `<domain>.yaml` here.
2. Add a pydantic section in `app/core/game_config.py`.
3. Add a matching Dart section in `flutter/lib/config/game_config.dart`.
4. Point the service/coordinator at the new section.
