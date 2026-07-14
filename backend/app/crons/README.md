# Cron jobs

Scheduled background jobs for Mesozoica. Config lives in [`crons.yaml`](crons.yaml); the runner is [`runner.py`](runner.py).

Cron jobs **always use the Railway Postgres database** — not a local DB. Run them via `make` (which wraps `railway run`) or from the Railway cron service.

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
make run-dinosaur-image-generate
make run-fossil-image-generate
make run-site-type-image-generate

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

make run-dinosaur-image-generate CRON_EXTRA='--max-items 5'
make run-dinosaur-image-generate CRON_EXTRA='--dinos Tyrannosaurus --dry-run'
make run-fossil-image-generate CRON_EXTRA='--max-items 10'
make run-fossil-image-generate CRON_EXTRA='--dinos Tyrannosaurus --dry-run'
make run-site-type-image-generate CRON_EXTRA='--max-items 3 --dry-run'
make run-site-type-image-generate CRON_EXTRA='--site-types 5 18 20'

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

# Flags
RAILWAY_RUN=1 railway run python -m app.crons.runner --job dinosaur_wiki_sync --overwrite
RAILWAY_RUN=1 railway run python -m app.crons.runner --job fossil_pbdb_sync --dinos Tyrannosaurus
RAILWAY_RUN=1 railway run python -m app.crons.runner --job dinosaur_llm_enrich --dinos Tyrannosaurus --overwrite
RAILWAY_RUN=1 railway run python -m app.crons.runner --job fossil_llm_enrich --dinos Tyrannosaurus --overwrite
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
| `--dry-run` | Image generation: list candidates without calling Imagen or writing files; `site_sync` / `site_type_sync`: compute without DB writes |

### `fossil_pbdb_sync` resume behavior

- **Normal run** (no flags): only genera with `fossils_insert_time IS NULL` (first-time or interrupted).
- **`--stale-days N`** (cron default: 7): also re-sync genera last synced more than N days ago.
- **`--overwrite`**: clears `fossils_insert_time` for the target genera (or all), re-fetches and updates existing fossil rows, and stamps each genus only after it finishes. If interrupted, resume with a normal run — completed genera are skipped, pending ones are picked up.

### `dinosaur_llm_enrich` / `fossil_llm_enrich` resume behavior

- **`--overwrite`**: clears `llm_enriched` for the target scope first, then re-enriches and sets `llm_enriched=true` per successful record. If interrupted, resume with a normal run (no `--overwrite`) — completed rows are skipped, pending rows are picked up.

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
```

**Emergency local run** (tests only — still requires non-local `DATABASE_URL`):

```bash
ALLOW_LOCAL_CRON=1 python -m app.crons.runner --job dinosaur_wiki_sync
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

# Interrupted full PBDB overwrite — resume without --overwrite
make run-fossil-pbdb-sync CRON_EXTRA='--overwrite'   # start (or restart) full refresh
make run-fossil-pbdb-sync                            # resume where it left off

# Dry-run is configured in crons.yaml params (dry_run: true), or via a local overlay
```
