# Fossil card images

Curated card-front images for the Mesozoica fossil catalog. Files here are synced to Railway and served at `/media/fossils/{filename}`.

## Naming

- Filename stem must match `fossil.id` in the database (PBDB `occurrence_no`), e.g. `100001.webp`.
- Allowed extensions: `.webp`, `.jpg`, `.jpeg`, `.png`

## Sync to Railway

1. Add or update image files in this folder (`mesozoica/fossil-images/` in your repo).
2. On the **backend** Railway service: mount a volume at `/data` (recommended) or `/data/fossil-images`, set `CURATED_IMAGES_DATA_ROOT=/data` and/or `FOSSIL_IMAGES_DIR=/data/fossil-images`, and set `FOSSIL_IMAGE_SYNC_SECRET`.
3. Run from the repo root — reads **local** files here, uploads to the **deployed** Railway API:

```bash
make sync-fossil-images
```

Dry run (preview matches, no upload or DB changes):

```bash
make sync-fossil-images CRON_EXTRA='--dry-run'
```

Replace images already on Railway (required after regenerating local PNGs):

```bash
make sync-fossil-images CRON_EXTRA='--overwrite'
```

Set `PUBLIC_BASE_URL` on Railway and the same `FOSSIL_IMAGE_SYNC_SECRET` locally via `railway run` so `main_image_url` is stored correctly and uploads are authorized.

Image binaries are gitignored; only this README and `.gitkeep` are tracked.
