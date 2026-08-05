# Game config control board

Single source of truth for Mesozoica game-mechanics knobs.

- **Backend** loads these YAML files via `app.core.game_config`.
- **Flutter** loads the same files via the symlink
  `flutter/assets/game_config` → `backend/app/game_config`.

## Domains

| File | Purpose |
|------|---------|
| `site_generation.yaml` | Field site density, spacing, geology blend, client ensure triggers (not a skill) |
| `01_field_survey.yaml` | Field Survey — discovery, stewardship, clearing + field fossil spawn tables |
| `02_bone_quarry.yaml` | Bone Quarry — fossil localization / excavation / transport / curation |
| `03_science_hall.yaml` | Science Hall — prep, analysis, modelling, mounting, publishing (stub) |
| `tool_actions.yaml` | Per-tool action knobs + `modifies_main_params` |
| `leveling.yaml` | Skill list + 99 career titles (XP amounts live on skill `main_params`) |
| `period_colors.yaml` / `rock_type_colors.yaml` | Overlay / marker palettes |

## XP presentation (Flutter)

Every announced skill XP gain is shown in **exactly one** of two ways:

| Presentation | When | Breakdown keys (examples) |
|--------------|------|---------------------------|
| **Celebration plaque** | Big events — XP embedded under the celebration title (all XP for that event) | `sites`, `discover_site_as_first`, `fossils`, `document_site`, `document_site_as_first`, `identify_site` |
| **Floating XP badge** | Small / ongoing events | `explore_100m_actively`, `explore_100m_passively`, `disguise_of_site`, `document_progress` |

Client routing lives in `flutter/lib/utils/xp_source_labels.dart` and
`XpAwardController.announceAwards`. Backend award amounts are unchanged by
this split — only the UI path differs.

Skill YAML files use the `NN_skill_id.yaml` convention so they sort in skill order.

## Skill `main_params`

Each skill domain YAML has:

```yaml
skill_id: site_discovery
main_params: { ... }          # global defaults (player-facing)
level_modifiers:              # keyframes; values lerp between levels
  discovery_chance: []        # entries: { level, op: add|multiply|replace, value }
  rival_discovery_chance:     # endpoints alone → linear ramp L1→L99
    - { level: 1, op: multiply, value: 1 }
    - { level: 99, op: multiply, value: 0.5 }
weather_time_modifiers:       # keyed by solar period; identity if omitted/empty
  discovery_distance_m:
    day: [{ op: multiply, value: 1.1 }]
weather_type_modifiers:       # keyed by weather type; identity if omitted/empty
  discovery_distance_m:
    clear: [{ op: multiply, value: 1.1 }]
client: { ... }               # non-main implementation knobs (optional)
```

`level_modifiers` are keyframes: `value` is linearly interpolated between
adjacent entries (same `op`). Below the first keyframe is identity; at/above
the last uses that entry. Two endpoints are enough for a straight L1→L99 ramp;
add midpoints only for non-linear curves.

Ops (same for `level_modifiers`, ambient weather modifiers, and tool
`modifies_main_params`):

| op | Meaning | Example |
|----|---------|---------|
| `replace` | Set absolute value | `{ op: replace, value: 0.9 }` → chance = 90% |
| `multiply` | Scale the base | `{ op: multiply, value: 1.1 }` → +10% |
| `add` | Offset the base | `{ op: add, value: 50 }` → +50 m |

Chance params are clamped to 0..1 after modifiers.

### Ambient weather

Three status dimensions drive HUD + gameplay knobs:

| Dimension | Source | Values |
|-----------|--------|--------|
| `weather_time` | Local solar math (lat/lon/UTC; no API) | `dawn`, `day`, `dusk`, `golden_hour`, `night` |
| `weather_type` | Open-Meteo via backend, 5 km grid cache | `clear` (WMO 0–1), `cloudy` (WMO 2; UI: Partly cloudy), `overcast` (WMO 3), … (time-agnostic; UI picks day/night art from `weather_time`) |
| `temperature_c` | Same Open-Meteo fetch | degrees Celsius |

Solar elevation bands: `day` ≥ 6°, `golden_hour` 0–6°, `dawn`/`dusk` −6–0°
(civil twilight; morning vs afternoon), `night` < −6°.

Effective values resolve as:

```text
base main_params
  → level_modifiers(skill level)
  → weather_time_modifiers(solar period)
  → weather_type_modifiers(weather type)
  → owning tool modifies_main_params (when: owning)
  → active/using tool modifies_main_params (when: using)
```

`weather_time_modifiers` / `weather_type_modifiers` are keyed by period or type
name under each main_param. All list entries for the current key apply in order
(empty / missing = identity).

### Site Discovery (`01_site_discovery.yaml`)

| main_param | Meaning |
|------------|---------|
| `discovery_distance_m` | Discovery distance — walk-in discover radius (was `max_distance_m`) |
| `discovery_chance` | P(success) per attempt (enter or dwell re-roll) |
| `discovery_max_speed_kmh` | Discovery max speed — GPS speed cap for walk XP credit and discovery dice rolls |
| `discover_site_xp` | XP awarded when a site is discovered |
| `discover_site_as_first_xp` | Bonus XP when you are the first user to discover a site |
| `explore_100m_actively_xp` | XP per whole 100 m of active walking |
| `explore_100m_passively_xp` | Passive rate: XP per 100 m (pro-rata per 10 m) |

`discover_site_xp` solar-period multipliers: day +0%, golden hour +10%, dawn/dusk +20%, night +50%.
`discover_site_as_first_xp`, `explore_100m_actively_xp`, and `explore_100m_passively_xp` are not affected by time of day.
Visibility / discovery chance: day +10%, golden hour +30%, dawn/dusk +0%, night −40%.

Client-only (not main params): `discovery_reroll_interval_s` — seconds between
re-rolls while staying inside the discover radius (default 10). Walk-in still
rolls immediately; app-open already inside does not (dwell timer starts).

The location-puck pulse max radius is the effective `discovery_distance_m`
(base → level → weather_time → weather_type → owning/using tool mods), converted
to screen pixels at the current map zoom so the ring matches the real discover
range. Site Discovery visibility and discovery chance share the same ambient
multipliers (see `weather_time_modifiers` / `weather_type_modifiers` in this YAML).

### Fossil Detection (`04_fossil_detection.yaml`)

| main_param | Meaning |
|------------|---------|
| `locate_fossil_in_situ_xp` | XP awarded when a fossil is discovered / granted in situ |

Same solar-period XP multipliers as site discovery (day +0%, golden hour +10%,
dawn/dusk +20%, night +50%).

### Site Stewardship (`02_site_stewardship.yaml`)

Field fossils on discovery (once per site). `main_params` (level / weather / tool
resolvable):

| Key | Meaning |
|-----|---------|
| `documentation_accuracy` | Documentation accuracy — shared skill baseline for all five odd_* axes (base 1% × skill level; depth 0 always exact). Per-axis jitter stays in `accuracy_noise` |
| `rival_discovery_chance` | Rival discovery chance — multiplier on discovery_chance for rivals on sites where you have any status above hidden (×1 at L1 → ×0.5 at L99) |
| `documentation_distance_m` | Documentation distance — radius around a discovered site where walking accrues exploration meters |
| `disguise_of_site_xp` | XP when a rival discovery roll would hit but your active disguise blocks it |
| `document_progress_xp` | XP to field_survey per 20 m walked inside `documentation_distance_m` |
| `document_site_xp` | XP when all five site-dimension accuracies reach 100% (freezes further exploration) |
| `document_site_as_first_xp` | Bonus XP when you are the first user to fully document a site |
| `identify_site_xp` | XP per period/rock identification quiz step (100% / 50% / 0% by attempt). Exploration meters start only after both steps succeed |

`documentation_distance_m` uses the same solar-period multipliers as site discovery
`discovery_distance_m`. `document_progress_xp` uses the same multipliers as
`discover_site_xp`.

After discovery, the site shows as "Excavation Site" until the viewer completes
the identification quiz (period, then rock type). Only then do dimension bands
and exploration meters unlock.

Accuracy is display-only on the site card for now. Stack per axis:
shared skill baseline (`documentation_accuracy`, base 1% × level → L50 ≈ 50%) →
stable per-site / per-dimension noise (`accuracy_noise`) → tool
`modifies_main_params` (none yet) → exploration (+1% per meter walked inside
`documentation_distance_m`, additive, capped at 100%). When all five axes reach 100%,
`document_site_xp` is awarded once and further exploration is frozen.
The first user to complete documentation also receives `document_site_as_first_xp`.

`rival_discovery_chance` is multiplied by skill level (×1.0 at L1 → ×0.5 at L99,
linear) on every site where you have any status above hidden. Site-scoped tools
(Brush Scrim / Blackout Cover) multiply further on the covered site only.

Fixed global distribution tables (beside `main_params`; not subject to
multipliers):

| Key | Meaning |
|-----|---------|
| `dino_count` | Thresholds → distinct dinosaurs |
| `fossil_count` | Cards-per-dino CDF masses |
| `depth_weights` | Burial depth buckets |
| `completeness_weights` | Completeness tier CDF (YAML; not archive) |
| `quality_weights` | Preservation quality tier CDF (YAML; not archive) |

Subcategory is still archive-weighted. `odd_noise`, `accuracy_noise`, and
`defaults` also sit beside `main_params` (fixed; not level/tool resolvable).

`accuracy_noise.max_delta` is absolute ± accuracy points around the skill
baseline on the site card (independent of baseline size; e.g. 0.30 → ±30%).

### Tool modifiers (`tool_actions.yaml`)

One tool can affect multiple skills, with different params for owning vs using:

```yaml
some_tool:
  modifies_main_params:
    owning:
      site_discovery:
        discovery_chance: { op: add, value: 0.05 }
      site_stewardship:
        documentation_accuracy: { op: add, value: 0.1 }
    using:
      site_discovery:
        discovery_chance: { op: replace, value: 0.9 }
      fossil_detection:
        discovery_distance_m: { op: add, value: 5 }
```

Either bucket / skill may be omitted. Guidance tools today only set
`using.site_discovery.discovery_chance`.

Global buff tools (Ridge Glass, Trail Striders, Expedition Drivetrain,
Canyon Throttle, Overland Chassis, Nocturne Lens) set
`using.site_discovery` multipliers while a timed session is active. Optional
`active_weather_times` (e.g. `[night]` on Nocturne Lens) means:

1. Session start is rejected unless the current solar period is in the list.
2. When the period leaves the list, the session auto-stops (battery charges
   for elapsed time like a normal STOP).
3. Resolve paths skip `using` mods if the period is outside the list.

Aerial tools use **flight-only** keys (`flight_discovery_chance`,
`flight_discovery_distance_m`) so they are not confused with site_discovery
main params.

## Field fossil generation (`02_site_stewardship.yaml`)

When a **field** site is created it gets five independent Uniform(0,1) scores
stored on the site row (also shown on the site card back):

| Site field | Biases |
|------------|--------|
| `odd_dino_count` | How many distinct dinosaurs spawn |
| `odd_fossil_count` | How many fossil cards per dinosaur |
| `odd_completeness` | Fossil completeness tier |
| `odd_quality` | Preservation quality tier |
| `odd_depth` | Burial depth bucket |

On discovery (once per site), each attribute uses:

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
