# Fossil card images

Curated card-front images for the Mesozoica fossil catalog. Files live in named version folders and are synced to Railway at `/media/fossils/<version>/{filename}`.

## Layout

```
images/fossils/Original/meta.yaml
images/fossils/Original/139292.png
```

`meta.yaml` fields:

- `prompt` — Imagen instruction template used for this version
- `run_date` — UTC timestamp used when assigning the newest version to new fossil occurrences

## Naming

- Filename stem must match `fossil.id` in the database (PBDB `occurrence_no`), e.g. `100001.webp`.
- Allowed extensions: `.webp`, `.jpg`, `.jpeg`, `.png`

## Generate

`--version` is required:

```bash
make run-fossil-image-generate CRON_EXTRA='--version Original --max-items 10'
```

## Sync to Railway

1. Add or update image files under `images/fossils/<version>/`.
2. On the **backend** Railway service: mount a volume at `/data` (recommended) or `/data/images/fossils`, set `CURATED_IMAGES_DATA_ROOT=/data` and/or `FOSSIL_IMAGES_DIR=/data/images/fossils`, and set `FOSSIL_IMAGE_SYNC_SECRET`.
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

Image binaries are gitignored; only this README and `.gitkeep` are tracked. Version `meta.yaml` files should be committed when present.
