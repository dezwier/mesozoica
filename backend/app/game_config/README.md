# Game config control board

Single source of truth for Mesozoica game-mechanics knobs.

- **Backend** loads these YAML files via `app.core.game_config`.
- **Flutter** loads the same files via the symlink
  `flutter/assets/game_config` → `backend/app/game_config`.

## Domains

| File | Purpose |
|------|---------|
| `site_generation.yaml` | Field site density, spacing, geology blend, client ensure triggers (not a skill) |
| `01_site_discovery.yaml` … `12_academic_publishing.yaml` | Numbered skill domains (order matches `leveling.yaml`) |
| `tool_actions.yaml` | Per-tool action knobs + `modifies_main_params` |
| `leveling.yaml` | Skill XP rewards + 99 career title words (thresholds in code) |
| `period_colors.yaml` / `rock_type_colors.yaml` | Overlay / marker palettes |

Skill YAML files use the `NN_skill_id.yaml` convention so they sort in skill order.

## Skill `main_params`

Each skill domain YAML has:

```yaml
skill_id: site_discovery
main_params: { ... }          # global defaults (player-facing)
level_modifiers:              # identity in v1; tune later
  discovery_chance: []        # entries: { level, op: add|multiply|replace, value }
client: { ... }               # non-main implementation knobs (optional)
```

Effective values resolve as:

```text
base main_params
  → level_modifiers(skill level)
  → owning tool modifies_main_params (when: owning)
  → active/using tool modifies_main_params (when: using)
```

Ops (same for `level_modifiers` and tool `modifies_main_params`):

| op | Meaning | Example |
|----|---------|---------|
| `replace` | Set absolute value | `{ op: replace, value: 0.9 }` → chance = 90% |
| `multiply` | Scale the base | `{ op: multiply, value: 1.1 }` → +10% |
| `add` | Offset the base | `{ op: add, value: 50 }` → +50 m |

Chance params are clamped to 0..1 after modifiers.

### Site Discovery (`01_site_discovery.yaml`)

| main_param | Meaning |
|------------|---------|
| `visibility_distance_m` | Walk-in discover radius (was `max_distance_m`) |
| `discovery_chance` | P(success) on enter |
| `max_discovery_speed_kmh` | GPS odometer speed cap for walk XP |

### Site Survey (`02_site_survey.yaml`)

Field fossils on survey (once per site). `main_params`:

| Key | Meaning |
|-----|---------|
| `dino_count` | Thresholds → distinct dinosaurs |
| `fossil_count` | Cards-per-dino CDF masses |
| `depth_weights` | Burial depth buckets |
| `completeness_weights` | Completeness tier CDF (YAML; not archive) |
| `quality_weights` | Preservation quality tier CDF (YAML; not archive) |

Subcategory is still archive-weighted. `odd_noise` / `defaults` sit beside `main_params`.

### Tool modifiers (`tool_actions.yaml`)

One tool can affect multiple skills, with different params for owning vs using:

```yaml
some_tool:
  modifies_main_params:
    owning:
      site_discovery:
        discovery_chance: { op: add, value: 0.05 }
      site_survey:
        fossil_count: { op: multiply, value: 1.1 }
    using:
      site_discovery:
        discovery_chance: { op: replace, value: 0.9 }
      fossil_detection:
        visibility_distance_m: { op: add, value: 5 }
```

Either bucket / skill may be omitted. Guidance tools today only set
`using.site_discovery.discovery_chance`.

Aerial tools use **flight-only** keys (`flight_discovery_chance`,
`flight_discovery_distance_m`) so they are not confused with site_discovery
main params.

## Field fossil generation (`02_site_survey.yaml`)

When a **field** site is created it gets five independent Uniform(0,1) scores
stored on the site row (also shown on the site card back):

| Site field | Biases |
|------------|--------|
| `odd_dino_count` | How many distinct dinosaurs spawn |
| `odd_fossil_count` | How many fossil cards per dinosaur |
| `odd_completeness` | Fossil completeness tier |
| `odd_quality` | Preservation quality tier |
| `odd_depth` | Burial depth bucket |

On survey (once per site), each attribute uses:

```text
score = clamp(odd + Uniform(-noise, +noise), 0, 1)
```

then picks the tier that `score` falls into (inverse-CDF of the YAML weights /
thresholds). Subcategory remains a pure archive weighted sample.

## Adding a new domain

1. Add `<domain>.yaml` here (skill domains: `NN_skill_id.yaml`).
2. Add a pydantic section in `app/core/game_config.py`.
3. Add a matching Dart section in `flutter/lib/config/game_config.dart`.
4. Point the service/coordinator at the new section.
5. List the asset in `flutter/pubspec.yaml`.
