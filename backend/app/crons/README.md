# Cron jobs

Scheduled background jobs for Mesozoica. Config lives in [`crons.yaml`](crons.yaml); the runner is [`runner.py`](runner.py).

Cron jobs **always use the Railway Postgres database** — not a local DB. Run them via `make` (which wraps `railway run`) or from the Railway cron service.

Image **generation** writes local PNGs to repo folders; **image sync** (`make sync-*-images`) uploads those files to Railway and updates `main_image_url`.

## Jobs

| ID | Schedule (UTC) | Description |
|----|----------------|-------------|
| `dinosaur_wiki_sync` | `0 3 * * 0` (Sun 03:00) | Sync dinosaur records from Wikipedia |
| `dinosaur_llm_enrich` | `0 4 * * 0` (Sun 04:00) | LLM enrichment (Gemini) for dinosaurs |
| `fossil_pbdb_sync` | `0 5 * * 0` (Sun 05:00) | Sync fossil occurrences from PBDB |
| `fossil_llm_enrich` | `0 6 * * 0` (Sun 06:00) | LLM enrichment (Gemini) for fossil occurrences |
| `dinosaur_image_generate` | `0 6 * * 0` (Sun 06:00) | Generate dinosaur card images via Gemini Imagen |
| `fossil_image_generate` | `0 7 * * 0` (Sun 07:00) | Generate fossil card images via Gemini Imagen |
| `site_type_image_generate` | `0 8 * * 0` (Sun 08:00) | Generate site-type card images via Gemini Imagen |
| `site_sync` | `0 9 * * 0` (Sun 09:00) | Rebuild `site` derived table and link `fossil.site_id` |
| `site_type_sync` | `30 9 * * 0` (Sun 09:30) | Rebuild `site_type` rows and assign `site.site_type_id` |
| `tool_sync` | `0 10 * * 0` (Sun 10:00) | Upsert tool catalog from [`backend/data/tools.json`](../data/tools.json) |
| `tool_image_generate` | `30 10 * * 0` (Sun 10:30) | Generate tool card images via Gemini Imagen |

All jobs are `enabled: false` in `crons.yaml` by default — enable individually in YAML, via `CRON_<JOB_ID>_ENABLED`, or run manually with `--job`.

Railway `cronSchedule` must fire at least as often as the finest job granularity (use `0 * * * *` for weekly jobs).

## Make targets (recommended)

Make target names mirror job module names (`dinosaur_wiki_sync.py` → `run-dinosaur-wiki-sync`).

From the repo root:

```bash
# Run all due jobs (schedule-aware)
make run-cron

# Run a single job
make run-dinosaur-wiki-sync
make run-dinosaur-llm-enrich
make run-fossil-pbdb-sync
make run-fossil-llm-enrich
make run-site-sync
make run-site-type-sync
make run-tool-sync
make run-dinosaur-image-generate
make run-fossil-image-generate
make run-site-type-image-generate
make run-tool-image-generate

# Pass extra runner flags via CRON_EXTRA
make run-dinosaur-wiki-sync CRON_EXTRA='--overwrite'
make run-dinosaur-wiki-sync CRON_EXTRA='--dinos Tyrannosaurus Giganotosaurus'
make run-dinosaur-wiki-sync CRON_EXTRA='--category "Category:Feathered dinosaurs"'

make run-dinosaur-llm-enrich CRON_EXTRA='--overwrite'
make run-dinosaur-llm-enrich CRON_EXTRA='--dinos Tyrannosaurus --overwrite'

make run-fossil-pbdb-sync CRON_EXTRA='--dinos Tyrannosaurus'
make run-fossil-pbdb-sync CRON_EXTRA='--overwrite'
make run-fossil-pbdb-sync CRON_EXTRA='--stale-days 7'
make run-fossil-pbdb-sync CRON_EXTRA='--dinos Tyrannosaurus --overwrite'

make run-fossil-llm-enrich CRON_EXTRA='--dinos Tyrannosaurus'
make run-fossil-llm-enrich CRON_EXTRA='--overwrite'
make run-fossil-llm-enrich CRON_EXTRA='--dinos Tyrannosaurus --overwrite'

make run-site-sync
make run-site-sync CRON_EXTRA='--dry-run'
make run-site-sync CRON_EXTRA='--dinos Tyrannosaurus'

make run-site-type-sync
make run-site-type-sync CRON_EXTRA='--dry-run'
make run-site-type-sync CRON_EXTRA='--dinos Tyrannosaurus'

make run-tool-sync
make run-tool-sync CRON_EXTRA='--dry-run'
make run-tool-sync CRON_EXTRA='--tools "Geo Hammer" "Field Codex"'
make run-tool-sync CRON_EXTRA='--prune'   # remove DB rows missing from tools.json

make run-dinosaur-image-generate CRON_EXTRA='--max-items 5'
make run-dinosaur-image-generate CRON_EXTRA='--dinos Tyrannosaurus --dry-run'
make run-fossil-image-generate CRON_EXTRA='--max-items 10'
make run-fossil-image-generate CRON_EXTRA='--dinos Tyrannosaurus --dry-run'
make run-site-type-image-generate CRON_EXTRA='--max-items 3 --dry-run'
make run-site-type-image-generate CRON_EXTRA='--site-types 5 18 20'
make run-tool-image-generate CRON_EXTRA='--max-items 5'
make run-tool-image-generate CRON_EXTRA='--tools "Geo Hammer" "Field Codex" --dry-run'

# Local tool image generation (no railway run wrapper; uses backend/.env)
make run-tool-image-generate-local CRON_EXTRA='--max-items 1 --tools "Geo Hammer"'

# Upload curated images to Railway volume + DB (separate from generation)
make sync-dinosaur-images
make sync-fossil-images
make sync-site-type-images
make sync-tool-images
make sync-tool-images CRON_EXTRA='--dry-run'

# Target a specific Railway service
make run-fossil-pbdb-sync RAILWAY_SERVICE=my-service CRON_EXTRA='--dinos Herrerasaurus'
```

## Direct commands

Equivalent `railway run` invocations from `backend/`:

```bash
cd backend

# All due jobs
RAILWAY_RUN=1 railway run python -m app.crons.runner

# Single job
RAILWAY_RUN=1 railway run python -m app.crons.runner --job dinosaur_wiki_sync
RAILWAY_RUN=1 railway run python -m app.crons.runner --job dinosaur_llm_enrich
RAILWAY_RUN=1 railway run python -m app.crons.runner --job fossil_pbdb_sync
RAILWAY_RUN=1 railway run python -m app.crons.runner --job fossil_llm_enrich
RAILWAY_RUN=1 railway run python -m app.crons.runner --job dinosaur_image_generate
RAILWAY_RUN=1 railway run python -m app.crons.runner --job fossil_image_generate
RAILWAY_RUN=1 railway run python -m app.crons.runner --job site_type_image_generate
RAILWAY_RUN=1 railway run python -m app.crons.runner --job site_sync
RAILWAY_RUN=1 railway run python -m app.crons.runner --job site_type_sync
RAILWAY_RUN=1 railway run python -m app.crons.runner --job tool_sync
RAILWAY_RUN=1 railway run python -m app.crons.runner --job tool_image_generate

# Flags
RAILWAY_RUN=1 railway run python -m app.crons.runner --job dinosaur_wiki_sync --overwrite
RAILWAY_RUN=1 railway run python -m app.crons.runner --job fossil_pbdb_sync --dinos Tyrannosaurus
RAILWAY_RUN=1 railway run python -m app.crons.runner --job tool_sync --tools "Geo Hammer"
RAILWAY_RUN=1 railway run python -m app.crons.runner --job tool_image_generate --max-items 3 --tools "Geo Hammer"
```

### CLI flags

| Flag | Effect |
|------|--------|
| `--job ID` | Run one job immediately (ignores schedule) |
| `--overwrite` | Re-fetch / re-enrich even when already up to date. For `fossil_pbdb_sync`, also clears `fossils_insert_time` first so an interrupted run can resume without `--overwrite`. For `dinosaur_llm_enrich` and `fossil_llm_enrich`, clears `llm_enriched` first so an interrupted overwrite can resume without `--overwrite`. |
| `--dinos NAME …` | Limit to specific Wikipedia titles (space- or comma-separated) |
| `--category NAME` | `dinosaur_wiki_sync`: limit to one Wikipedia category |
| `--stale-days N` | `fossil_pbdb_sync`: only genera with `fossils_insert_time` null or older than N days (ignored with `--overwrite`) |
| `--since ISO8601` | `fossil_pbdb_sync`: only genera with `fossils_insert_time` null or before this UTC time (ignored with `--overwrite`) |
| `--max-items N` | Image generation jobs: cap successful generations per run |
| `--site-types ID …` | `site_type_image_generate`: limit to specific `site_type.id` values |
| `--version NAME` | **Required** for all four image generate jobs: named folder (e.g. `Original`, `Summer 26`) |
| `--tools NAME …` | `tool_sync` / `tool_image_generate`: limit to specific branded tool names |
| `--prune` | `tool_sync`: delete DB tool rows whose `name` is no longer in `tools.json` |
| `--dry-run` | Image generation: list candidates without calling Imagen or writing files; `site_sync` / `site_type_sync` / `tool_sync`: compute without DB writes |

### Procedural field sites (lazy, not a cron)

Field sites (`data_source=field`) are **global** `Site` rows (shared density pool). Players only see sites they have a `user_site` link to on the default map; undiscovered sites stay hidden until personal proximity discovery (50 m). Admins can use `show_all=true` (and the map “Show all” control, which loads the current viewport only) plus “Scan” to inspect field sites.

- **`GET /api/v1/sites?data_source=field`** — linked-only field sites for the current user (empty when anonymous). Pass `show_all=true` as an **admin** to list all field sites.
- **`GET /api/v1/sites?data_source=field&site_id_min=N&sort=name`** — incremental poll for sites written since the last id (Flutter polls every ~60 s while the map tab is open).
- **`GET /api/v1/sites/nearby-discoverable`** — field sites in radius that the current user can still discover (`hidden`, or discovered by someone else and not yet linked to them).
- **`POST /api/v1/sites/{id}/discover`** — create this user’s discoverer link when within 50 m (also sends inbox + FCM push).
- **`POST /api/v1/sites/field/ensure`** — returns `202` immediately and enqueues a row in `field_ensure_job`. Optional JSON field `reason`: `resume`, `move_500m`, `scan`, or `field_mode_on` (logged on enqueue/skip/noop). A dedicated Railway worker service (`python -m app.workers.field_ensure_worker`, see [`app/workers/README.md`](../workers/README.md)) claims jobs with `FOR UPDATE SKIP LOCKED`, re-counts density, and generates only the still-missing count within 1 km (land-only coordinates, geology sampled from archive sites). Jobs dedupe by `cell_key` (`round(lat,2):round(lon,2):radius_km`).
- **`GET /api/v1/sites/nearby`** — read-only listing within a radius (no generation); same linked-only / admin `show_all` rules as list.

The Flutter app calls `POST /field/ensure` on app open/resume and every 500 m move while the app process is alive (foreground or background). Map polling is map-tab-only. Auto-discovery runs on every GPS fix within 50 m.

### `fossil_pbdb_sync` resume behavior

- **Normal run** (no flags): only genera with `fossils_insert_time IS NULL` (first-time or interrupted).
- **`--stale-days N`** (cron default: 7): also re-sync genera last synced more than N days ago.
- **`--overwrite`**: clears `fossils_insert_time` for the target genera (or all), re-fetches and updates existing fossil rows, and stamps each genus only after it finishes. If interrupted, resume with a normal run — completed genera are skipped, pending ones are picked up.

### `dinosaur_llm_enrich` / `fossil_llm_enrich` resume behavior

- **`--overwrite`**: clears `llm_enriched` for the target scope first, then re-enriches and sets `llm_enriched=true` per successful record. If interrupted, resume with a normal run (no `--overwrite`) — completed rows are skipped, pending rows are picked up.

### `tool_sync` behavior

- Source of truth: [`backend/data/tools.json`](../data/tools.json).
- Upserts by branded `name`; updates `category`, `scientific_tool`, `description`, `rarity`.
- Preserves existing `main_image_url` on update.
- **`--prune`**: removes DB rows not present in JSON (off by default).

## Image generation

All `*_image_generate` jobs write PNGs locally under repo folders:

| Entity | Output folder | Filename key |
|--------|---------------|--------------|
| Dinosaur | `images/dinosaurs/<version>/` | `{dinosaur.name}.png` |
| Fossil | `images/fossils/<version>/` | `{fossil.id}.png` |
| Site type | `images/site-types/<version>/` | `{period}_{rock_type}.png` |
| Tool | `images/tools/<version>/` | `{tool.name}.png` |

All four kinds use named version folders (`Original`, `Summer 26`, …). Each folder has a `meta.yaml` with the prompt template and `run_date`. **`--version` is mandatory** (no auto-increment):

```bash
make run-tool-image-generate CRON_EXTRA='--version "Summer 26"'
make run-site-type-image-generate CRON_EXTRA='--version Original --max-items 5'
make run-tool-image-generate-local CRON_EXTRA='--version "Summer 26"'
make run-dinosaur-image-generate CRON_EXTRA='--version "Summer 26" --max-items 5'
make run-fossil-image-generate CRON_EXTRA='--version Original --max-items 10'
```

Catalog dinosaur/tool cards always use `Original`. Occurrences store a `version` string and resolve that folder. New occurrences are assigned the newest folder by `meta.yaml` `run_date`.

Requires `GOOGLE_GEMINI_API_KEY`. Default model: `imagen-4.0-ultra-generate-001` (`GEMINI_IMAGE_MODEL`).

The client retries transient failures (503, capacity, timeouts) with exponential backoff, then falls back to **`imagen-4.0-fast-generate-001`** when Ultra cannot complete. Override the primary model:

```bash
GEMINI_IMAGE_MODEL=imagen-4.0-fast-generate-001 \
  make run-tool-image-generate-local CRON_EXTRA='--version Original --max-items 5'
```

**Local tool generation** skips the `railway run` wrapper but still reads tools from Railway Postgres via `backend/.env`:

```bash
make run-tool-image-generate-local CRON_EXTRA='--max-items 1 --tools "Geo Hammer"'
```

During API capacity spikes, prefer `--max-items 1` and one tool at a time. Each successful image typically takes ~15–20s.

After generating locally, upload to Railway:

```bash
make sync-tool-images
```

See also [`images/tools/README.md`](../../../images/tools/README.md) and sibling folders for sync env vars.

## Config overrides

**Overlay file** — merge extra YAML on top of `crons.yaml`:

```bash
export CRON_CONFIG_PATH=/path/to/crons.local.yaml
RAILWAY_RUN=1 railway run python -m app.crons.runner --job dinosaur_wiki_sync
```

**Per-job enable/disable** via environment (job id uppercased, `-` → `_`):

```bash
export CRON_DINOSAUR_WIKI_SYNC_ENABLED=false
export CRON_FOSSIL_PBDB_SYNC_ENABLED=1
export CRON_TOOL_SYNC_ENABLED=1
```

**Emergency local run** (tests or local image generation — still requires non-local `DATABASE_URL` in `backend/.env`):

```bash
ALLOW_LOCAL_CRON=1 python -m app.crons.runner --job tool_image_generate --max-items 1
```

## Typical workflows

```bash
# Full weekly pipeline for one dinosaur (dev/debug)
make run-dinosaur-wiki-sync CRON_EXTRA='--dinos Tyrannosaurus --overwrite'
make run-dinosaur-llm-enrich  CRON_EXTRA='--dinos Tyrannosaurus --overwrite'
make run-fossil-pbdb-sync     CRON_EXTRA='--dinos Tyrannosaurus --overwrite'
make run-fossil-llm-enrich    CRON_EXTRA='--dinos Tyrannosaurus --overwrite'
make run-site-sync CRON_EXTRA='--dinos Tyrannosaurus'
make run-site-type-sync CRON_EXTRA='--dinos Tyrannosaurus'

# Tool catalog: JSON → DB → images → upload
make run-tool-sync
make run-tool-image-generate-local CRON_EXTRA='--max-items 10'
make sync-tool-images

# Interrupted full PBDB overwrite — resume without --overwrite
make run-fossil-pbdb-sync CRON_EXTRA='--overwrite'   # start (or restart) full refresh
make run-fossil-pbdb-sync                            # resume where it left off

# Dry-run is configured in crons.yaml params (dry_run: true), or via a local overlay
```
