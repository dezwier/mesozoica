# Cron jobs

Scheduled background jobs for Mesozoica. Config lives in [`crons.yaml`](crons.yaml); the runner is [`runner.py`](runner.py).

Cron jobs **always use the Railway Postgres database** — not a local DB. Run them via `make` (which wraps `railway run`) or from the Railway cron service.

## Jobs

| ID | Schedule (UTC) | Description |
|----|----------------|-------------|
| `wikipedia_dinosaur_sync` | `0 3 * * 0` (Sun 03:00) | Sync dinosaur records from Wikipedia |
| `dinosaur_llm_enrich` | `0 4 * * 0` (Sun 04:00) | LLM enrichment (Gemini) for dinosaurs |
| `pbdb_fossil_sync` | `0 5 * * 0` (Sun 05:00) | Sync fossil occurrences from PBDB |
| `dinosaur_image_generate` | `0 6 * * 0` (disabled) | Generate dinosaur card images via Gemini Imagen |
| `fossil_image_generate` | `0 7 * * 0` (disabled) | Generate fossil card images via Gemini Imagen |
| `fossil_clean_sync` | `0 8 * * 0` (disabled) | Rebuild `site_clean` and `fossil_clean` derived tables |

Railway `cronSchedule` must fire at least as often as the finest job granularity (use `0 * * * *` for weekly jobs).

## Make targets (recommended)

From the repo root:

```bash
# Run all due jobs (schedule-aware)
make run-cron

# Run a single job
make run-wikipedia-sync
make run-dinosaur-enrich
make run-fossil-sync
make run-fossil-clean-sync
make run-dinosaur-image-gen
make run-fossil-image-gen

# Pass extra runner flags via CRON_EXTRA
make run-wikipedia-sync CRON_EXTRA='--overwrite'
make run-wikipedia-sync CRON_EXTRA='--dinos Tyrannosaurus Giganotosaurus'

make run-dinosaur-enrich CRON_EXTRA='--overwrite'
make run-dinosaur-enrich CRON_EXTRA='--dinos Tyrannosaurus --overwrite'

make run-fossil-sync CRON_EXTRA='--dinos Tyrannosaurus'
make run-fossil-sync CRON_EXTRA='--overwrite'
make run-fossil-sync CRON_EXTRA='--stale-days 7'
make run-fossil-sync CRON_EXTRA='--dinos Tyrannosaurus --overwrite'

make run-fossil-clean-sync
make run-fossil-clean-sync CRON_EXTRA='--dry-run'
make run-fossil-clean-sync CRON_EXTRA='--dinos Tyrannosaurus'

make run-dinosaur-image-gen CRON_EXTRA='--max-items 5'
make run-dinosaur-image-gen CRON_EXTRA='--dinos Tyrannosaurus --dry-run'
make run-fossil-image-gen CRON_EXTRA='--max-items 10'
make run-fossil-image-gen CRON_EXTRA='--dinos Tyrannosaurus --dry-run'

# Target a specific Railway service
make run-fossil-sync RAILWAY_SERVICE=my-service CRON_EXTRA='--dinos Herrerasaurus'
```

## Direct commands

Equivalent `railway run` invocations from `backend/`:

```bash
cd backend

# All due jobs
RAILWAY_RUN=1 railway run python -m app.crons.runner

# Single job
RAILWAY_RUN=1 railway run python -m app.crons.runner --job wikipedia_dinosaur_sync
RAILWAY_RUN=1 railway run python -m app.crons.runner --job dinosaur_llm_enrich
RAILWAY_RUN=1 railway run python -m app.crons.runner --job pbdb_fossil_sync
RAILWAY_RUN=1 railway run python -m app.crons.runner --job dinosaur_image_generate
RAILWAY_RUN=1 railway run python -m app.crons.runner --job fossil_image_generate
RAILWAY_RUN=1 railway run python -m app.crons.runner --job fossil_clean_sync

# Flags
RAILWAY_RUN=1 railway run python -m app.crons.runner --job wikipedia_dinosaur_sync --overwrite
RAILWAY_RUN=1 railway run python -m app.crons.runner --job pbdb_fossil_sync --dinos Tyrannosaurus
RAILWAY_RUN=1 railway run python -m app.crons.runner --job dinosaur_llm_enrich --dinos Tyrannosaurus --overwrite
```

### CLI flags

| Flag | Effect |
|------|--------|
| `--job ID` | Run one job immediately (ignores schedule) |
| `--overwrite` | Re-fetch / re-enrich even when already up to date |
| `--dinos NAME …` | Limit to specific Wikipedia titles (space- or comma-separated) |
| `--stale-days N` | PBDB sync: only genera not synced in the last N days (ignored with `--overwrite`) |
| `--since ISO8601` | PBDB sync: only genera with `fossils_insert_time` null or before this UTC time |
| `--max-items N` | Image generation: cap successful generations per run |
| `--dry-run` | Image generation: list candidates without calling Imagen or writing files; fossil clean sync: compute without DB writes |

## Config overrides

**Overlay file** — merge extra YAML on top of `crons.yaml`:

```bash
export CRON_CONFIG_PATH=/path/to/crons.local.yaml
RAILWAY_RUN=1 railway run python -m app.crons.runner --job wikipedia_dinosaur_sync
```

**Per-job enable/disable** via environment (job id uppercased, `-` → `_`):

```bash
export CRON_WIKIPEDIA_DINOSAUR_SYNC_ENABLED=false
export CRON_PBDB_FOSSIL_SYNC_ENABLED=1
```

**Emergency local run** (tests only — still requires non-local `DATABASE_URL`):

```bash
ALLOW_LOCAL_CRON=1 python -m app.crons.runner --job wikipedia_dinosaur_sync
```

## Typical workflows

```bash
# Full weekly pipeline for one dinosaur (dev/debug)
make run-wikipedia-sync CRON_EXTRA='--dinos Tyrannosaurus --overwrite'
make run-dinosaur-enrich  CRON_EXTRA='--dinos Tyrannosaurus --overwrite'
make run-fossil-sync     CRON_EXTRA='--dinos Tyrannosaurus --overwrite'
make run-fossil-clean-sync CRON_EXTRA='--dinos Tyrannosaurus'

# Dry-run is configured in crons.yaml params (dry_run: true), or via a local overlay
```
