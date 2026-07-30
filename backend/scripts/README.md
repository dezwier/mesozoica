# Scripts

One-off maintenance scripts for Mesozoica. Unlike [cron jobs](../app/crons/README.md), these are run manually when needed.

Scripts that touch production data use the **Railway Postgres database** and Railway API — run via `make` (wraps `railway run`) from the repo root.

## Scripts

| Module | Description |
|--------|-------------|
| [`sync_dinosaur_images.py`](sync_dinosaur_images.py) | Upload curated dinosaur card images from `images/dinosaurs/<version>/` to Railway volume and set `main_image_url` |
| [`sync_fossil_images.py`](sync_fossil_images.py) | Upload curated fossil card images from `images/fossils/<version>/` to Railway volume and set `main_image_url` |
| [`sync_site_type_images.py`](sync_site_type_images.py) | Upload curated site-type card images from `images/site-types/<version>/` to Railway volume and set `main_image_url` |
| [`sync_tool_images.py`](sync_tool_images.py) | Upload curated tool card images from `images/tools/<version>/` to Railway volume and set `main_image_url` |
| [`migrate_image_versions_to_v1.py`](migrate_image_versions_to_v1.py) | Move flat site-type/tool/dinosaur images into `Original/` and write retroactive `meta.yaml` |
| [`migrate_named_image_versions.py`](migrate_named_image_versions.py) | Rename `v1`→`Original`, `v2`→`Summer 26`; migrate flat fossils into `Original/` |
| [`backfill_user_levels.py`](backfill_user_levels.py) | Recompute user exploration/career XP from discoveries + distance using `leveling.yaml` rewards |

All sync scripts support `.png`, `.jpg`, `.jpeg`, and `.webp`.

### Dinosaur images

- **Source folder:** repo `images/dinosaurs/<version>/` (e.g. `Original/`, `Summer 26/`)
- **Filename rule:** stem must match `dinosaur_type.name` (case-insensitive), e.g. `Original/tyrannosaurus.png` → `Tyrannosaurus`
- **Served at:** `https://<api-host>/media/dinosaurs/<version>/<DinosaurName>.<ext>`
- **Cache busting:** `main_image_url` includes a `?v=<content-hash>` query param so the app fetches updated files after re-sync
- **Card resolution:** catalog always uses `Original`; inventory occurrences use `dinosaur.version`

### Fossil images

- **Source folder:** repo `images/fossils/<version>/` (e.g. `Original/`)
- **Filename rule:** `<occurrence_no>.<ext>` — stem is the PBDB occurrence number (stored as `fossil.id`), e.g. `Original/139292.png`
- **Served at:** `https://<api-host>/media/fossils/<version>/<occurrence_no>.<ext>`
- **Cache busting:** `main_image_url` includes a `?v=<content-hash>` query param so the app fetches updated files after re-sync
- **Card resolution:** uses `fossil.version`
- **Re-sync:** Local files are re-uploaded when missing remotely, or when the local file’s mtime is newer than the remote `Last-Modified` (use `--overwrite` to force every file)
- **Prune:** Fossils with a curated `main_image_url` but no matching file under version folders get `main_image_url` cleared on sync (app shows placeholder)

## Make targets (recommended)

From the repo root:

```bash
# Dinosaur images — upload and update DB
make sync-dinosaur-images
make sync-dinosaur-images CRON_EXTRA='--dry-run'
make sync-dinosaur-images CRON_EXTRA='--overwrite'

# Fossil images — upload and update DB
make sync-fossil-images
make sync-fossil-images CRON_EXTRA='--dry-run'
make sync-fossil-images CRON_EXTRA='--overwrite'

# User skill XP — recompute from history using current leveling.yaml
make backfill-user-levels
make backfill-user-levels CRON_EXTRA='--dry-run'

# Target a specific Railway service
make sync-dinosaur-images RAILWAY_SERVICE=my-service
make sync-fossil-images RAILWAY_SERVICE=my-service
```

## Direct commands

From `backend/`:

```bash
cd backend

# Dinosaur images
RAILWAY_RUN=1 railway run python -m scripts.sync_dinosaur_images
python -m scripts.sync_dinosaur_images --dry-run
python -m scripts.sync_dinosaur_images --overwrite

# Fossil images
RAILWAY_RUN=1 railway run python -m scripts.sync_fossil_images
python -m scripts.sync_fossil_images --dry-run
```

### CLI flags

| Flag | Effect |
|------|--------|
| `--dry-run` | Log what would sync/prune; skip uploads, remote deletes, and database updates |
| `--overwrite` | Force re-upload every matched image, even when remote is newer or equal |

## Environment

| Variable | Purpose |
|----------|---------|
| `DINOSAUR_IMAGES_SOURCE_DIR` | Local dinosaur image folder (default: repo `images/dinosaurs/`) |
| `FOSSIL_IMAGES_SOURCE_DIR` | Local fossil image folder (default: repo `images/fossils/`) |
| `DINOSAUR_IMAGE_SYNC_SECRET` | Required for dinosaur uploads; sent as `X-Dinosaur-Image-Sync-Key` |
| `FOSSIL_IMAGE_SYNC_SECRET` | Required for fossil uploads; sent as `X-Fossil-Image-Sync-Key` |
| `CURATED_IMAGES_DATA_ROOT` | Shared Railway volume root (e.g. `/data`); defaults fossil storage to `/data/images/fossils` when `FOSSIL_IMAGES_DIR` is unset |
| `PUBLIC_BASE_URL` | API base for curated image URLs (non-localhost) |
| `RAILWAY_PUBLIC_DOMAIN` | Fallback API host when `PUBLIC_BASE_URL` is unset |
| `RAILWAY_RUN=1` | Set by `make` so `railway run` is allowed |
| `ALLOW_LOCAL_CRON=1` | Bypass Railway guard (same as cron jobs; tests only) |

`DINOSAUR_IMAGES_DIR` and `FOSSIL_IMAGES_DIR` are **server-side** storage paths on Railway — not used as the local sync source.

### Railway volume layout (recommended)

Mount **one** volume at `/data` and set:

```bash
CURATED_IMAGES_DATA_ROOT=/data
FIELD_COORDINATE_DATA_DIR=/data
DINOSAUR_IMAGES_DIR=/data/images/dinosaurs   # optional if root is set
FOSSIL_IMAGES_DIR=/data/images/fossils      # optional if root is set
```

OSM coordinate masks are stored at `/data/osm/` (fetched once on first container boot).

Served URLs stay separate: `/media/dinosaurs/...` and `/media/fossils/...`.

## Typical workflow

### Dinosaur card images

```bash
# 1. Add or update images in images/dinosaurs/ (e.g. tyrannosaurus.png)
ls images/dinosaurs/

# 2. Preview matches
make sync-dinosaur-images CRON_EXTRA='--dry-run'

# 3. Upload to production (also syncs meta.yaml and deletes remote orphans)
make sync-dinosaur-images

# Force re-upload every matched file
make sync-dinosaur-images CRON_EXTRA='--overwrite'
```

### Fossil card images

```bash
# 1. Add or update images in images/fossils/ (filename = occurrence no, e.g. 139292.png)
ls images/fossils/

# 2. Preview matches
make sync-fossil-images CRON_EXTRA='--dry-run'

# 3. Upload to production (re-uploads when local is newer than remote)
make sync-fossil-images
```

Local files are uploaded when missing remotely or when local mtime is newer than remote `Last-Modified`. Use `--overwrite` only to force a full re-upload of every matched file.

### Site-type card images

- **Source folder:** repo `images/site-types/<version>/` (e.g. `Original/`, `Summer 26/`)
- **Filename rule:** `<version>/<period>_<rock_type>.<ext>` — e.g. `Original/cretaceous_sandstone.png`
- **meta.yaml:** each version folder stores `prompt` (generation template) and `run_date` (used when assigning version to new site occurrences)
- **Served at:** `https://<api-host>/media/site-types/<version>/<period>_<rock_type>.<ext>`
- **Generate:** `make run-site-type-image-generate CRON_EXTRA='--version "Summer 26"'`

```bash
make sync-site-type-images
make sync-site-type-images CRON_EXTRA='--dry-run'
make sync-site-type-images CRON_EXTRA='--overwrite'
```

### Tool card images

Same named-version layout under `images/tools/<version>/`. Catalog cards always use `Original`; inventory cards use `tool.version`.

```bash
make run-tool-image-generate-local CRON_EXTRA='--version "Summer 26" --max-items 3'
make sync-tool-images
```

### Migrate / rename version folders

```bash
make migrate-image-versions-to-v1          # flat files → Original/
make migrate-named-image-versions         # v1→Original, v2→Summer 26; flat fossils → Original/
make migrate-named-image-versions CRON_EXTRA='--dry-run'
```

## Adding a script

1. Add `backend/scripts/<name>.py` with a `main()` entrypoint.
2. Add a `make` target in the repo root `Makefile` if it should run on Railway.
3. Document it in this README.
