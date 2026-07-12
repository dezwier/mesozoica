# Scripts

One-off maintenance scripts for Mesozoica. Unlike [cron jobs](../app/crons/README.md), these are run manually when needed.

Scripts that touch production data use the **Railway Postgres database** and Railway API — run via `make` (wraps `railway run`) from the repo root.

## Scripts

| Module | Description |
|--------|-------------|
| [`sync_dinosaur_images.py`](sync_dinosaur_images.py) | Upload curated dinosaur card images from `dinosaur-images/` to Railway volume and set `main_image_url` |
| [`sync_fossil_images.py`](sync_fossil_images.py) | Upload curated fossil card images from `fossil-images/` to Railway volume and set `main_image_url` |

Both scripts support `.png`, `.jpg`, `.jpeg`, and `.webp`.

### Dinosaur images

- **Source folder:** repo `dinosaur-images/`
- **Filename rule:** stem must match `dinosaur.name` (case-insensitive), e.g. `tyrannosaurus.png` → `Tyrannosaurus`
- **Served at:** `https://<api-host>/media/dinosaurs/<DinosaurName>.<ext>`
- **Cache busting:** `main_image_url` includes a `?v=<content-hash>` query param so the app fetches updated files after re-sync

### Fossil images

- **Source folder:** repo `fossil-images/`
- **Filename rule:** `<occurrence_no>.<ext>` — stem is the PBDB occurrence number (stored as `fossil.id`), e.g. `139292.png`
- **Served at:** `https://<api-host>/media/fossils/<occurrence_no>.<ext>`

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
| `--dry-run` | Log what would sync; skip uploads and database updates |
| `--overwrite` | Replace images already on Railway. Default: upload only missing images |

## Environment

| Variable | Purpose |
|----------|---------|
| `DINOSAUR_IMAGES_SOURCE_DIR` | Local dinosaur image folder (default: repo `dinosaur-images/`) |
| `FOSSIL_IMAGES_SOURCE_DIR` | Local fossil image folder (default: repo `fossil-images/`) |
| `DINOSAUR_IMAGE_SYNC_SECRET` | Required for dinosaur uploads; sent as `X-Dinosaur-Image-Sync-Key` |
| `FOSSIL_IMAGE_SYNC_SECRET` | Required for fossil uploads; sent as `X-Fossil-Image-Sync-Key` |
| `CURATED_IMAGES_DATA_ROOT` | Shared Railway volume root (e.g. `/data`); defaults fossil storage to `/data/fossil-images` when `FOSSIL_IMAGES_DIR` is unset |
| `PUBLIC_BASE_URL` | API base for curated image URLs (non-localhost) |
| `RAILWAY_PUBLIC_DOMAIN` | Fallback API host when `PUBLIC_BASE_URL` is unset |
| `RAILWAY_RUN=1` | Set by `make` so `railway run` is allowed |
| `ALLOW_LOCAL_CRON=1` | Bypass Railway guard (same as cron jobs; tests only) |

`DINOSAUR_IMAGES_DIR` and `FOSSIL_IMAGES_DIR` are **server-side** storage paths on Railway — not used as the local sync source.

### Railway volume layout (recommended)

Mount **one** volume at `/data` and set:

```bash
CURATED_IMAGES_DATA_ROOT=/data
DINOSAUR_IMAGES_DIR=/data/dinosaur-images   # optional if root is set
FOSSIL_IMAGES_DIR=/data/fossil-images      # optional if root is set
```

Served URLs stay separate: `/media/dinosaurs/...` and `/media/fossils/...`.

## Typical workflow

### Dinosaur card images

```bash
# 1. Add or update images in dinosaur-images/ (e.g. tyrannosaurus.png)
ls dinosaur-images/

# 2. Preview matches
make sync-dinosaur-images CRON_EXTRA='--dry-run'

# 3. Upload to production
make sync-dinosaur-images

# Re-upload changed images
make sync-dinosaur-images CRON_EXTRA='--overwrite'
```

### Fossil card images

```bash
# 1. Add or update images in fossil-images/ (filename = occurrence no, e.g. 139292.png)
ls fossil-images/

# 2. Preview matches
make sync-fossil-images CRON_EXTRA='--dry-run'

# 3. Upload to production
make sync-fossil-images
```

If the app still shows a stale image after re-sync, pull to refresh the catalog. Dinosaur URLs include a content hash (`?v=...`) that changes when the file changes; a full app restart clears any remaining client-side cache.

## Adding a script

1. Add `backend/scripts/<name>.py` with a `main()` entrypoint.
2. Add a `make` target in the repo root `Makefile` if it should run on Railway.
3. Document it in this README.
