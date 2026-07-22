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
| `fossil_generation.yaml` | Field survey spawn: site odd_* thresholds, card/depth CDFs, noise |
| `fossil_discovery.yaml` | Stub — fossil proximity discovery (future) |
| `fossil_excavation.yaml` | Stub — excavation timing/loot (future) |

## Field fossil generation (`fossil_generation.yaml`)

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

then picks the tier that `score` falls into:

- **Dinos** — ordered `dino_count_thresholds` (`max_odd` exclusive upper bounds → `count` 0–5; final tier includes 1.0). Cap by archive pool size.
- **Cards per dino** — inverse-CDF of `card_count_weights` (keys 1–6 ascending). Distinct subcategories per dino (no repeats).
- **Depth** — inverse-CDF of `depth_buckets` weights (shallow→deep), then uniform cm in `[min_cm, max_cm]`.
- **Completeness / quality** — same score against **archive** frequency CDFs for the site period, ordered worst→best. Subcategory is still a pure archive weighted sample (not odd-biased).
- **`odd_noise`** — per-sampler ±noise map (`dino_count`, `fossil_count`, `completeness`, `quality`, `depth`).

Backfilling `odd_*` on existing field sites does **not** regenerate fossils already written; only new surveys use the odds.

## Adding a new domain

1. Add `<domain>.yaml` here.
2. Add a pydantic section in `app/core/game_config.py`.
3. Add a matching Dart section in `flutter/lib/config/game_config.dart`.
4. Point the service/coordinator at the new section.
