# Scripts

One-off maintenance scripts for Mesozoica. Unlike [cron jobs](../app/crons/README.md), these are run manually when needed.

Scripts that touch production data use the **Railway Postgres database** and Railway API — run via `make` (wraps `railway run`) from the repo root.

## Scripts

| Module | Description |
|--------|-------------|
| [`sync_dinosaur_images.py`](sync_dinosaur_images.py) | Upload curated card images from `dinosaur-images/` to Railway volume and set `main_image_url` |

Image filenames must match `dinosaur.name` (case-insensitive stem). Supported formats: `.png`, `.jpg`, `.jpeg`, `.webp`.

## Make targets (recommended)

From the repo root:

```bash
# Upload images and update DB
make sync-dinosaur-images

# Preview matches without uploading or DB writes
make sync-dinosaur-images CRON_EXTRA='--dry-run'

# Target a specific Railway service
make sync-dinosaur-images RAILWAY_SERVICE=my-service
```

## Direct commands

From `backend/`:

```bash
cd backend

# Upload images and update DB
RAILWAY_RUN=1 railway run python -m scripts.sync_dinosaur_images

# Dry run (no Railway DB guard; no uploads)
python -m scripts.sync_dinosaur_images --dry-run

# Via make equivalent
RAILWAY_RUN=1 railway run python -m scripts.sync_dinosaur_images --dry-run
```

### CLI flags

| Flag | Effect |
|------|--------|
| `--dry-run` | Log what would sync; skip uploads and database updates |

## Environment

| Variable | Purpose |
|----------|---------|
| `DINOSAUR_IMAGES_SOURCE_DIR` | Local folder to scan (default: repo `dinosaur-images/`) |
| `DINOSAUR_IMAGE_SYNC_SECRET` | Required for uploads; sent as `X-Dinosaur-Image-Sync-Key` |
| `PUBLIC_BASE_URL` | API base for curated image URLs (non-localhost) |
| `RAILWAY_PUBLIC_DOMAIN` | Fallback API host when `PUBLIC_BASE_URL` is unset |
| `RAILWAY_RUN=1` | Set by `make` so `railway run` is allowed |
| `ALLOW_LOCAL_CRON=1` | Bypass Railway guard (same as cron jobs; tests only) |

`DINOSAUR_IMAGES_DIR` is the **server-side** storage path on Railway — not used as the local sync source.

## Typical workflow

```bash
# 1. Add or update images in dinosaur-images/ (e.g. tyrannosaurus.png)
ls dinosaur-images/

# 2. Preview matches
make sync-dinosaur-images CRON_EXTRA='--dry-run'

# 3. Upload to production
make sync-dinosaur-images
```

After upload, curated images are served at:

```
https://<api-host>/media/dinosaurs/<DinosaurName>.<ext>
```

## Adding a script

1. Add `backend/scripts/<name>.py` with a `main()` entrypoint.
2. Add a `make` target in the repo root `Makefile` if it should run on Railway.
3. Document it in this README.
