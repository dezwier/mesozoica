# Dinosaur card images

Curated card-front images for the Mesozoica catalog. Files live in named version folders and are synced to Railway at `/media/dinosaurs/<version>/{filename}`.

## Layout

```
images/dinosaurs/Original/meta.yaml
images/dinosaurs/Original/Tyrannosaurus.png
images/dinosaurs/Summer 26/...
```

## Naming

- Filename stem must match `dinosaur.name` in the database (case-insensitive; canonical Wikipedia title casing is used on upload, e.g. `triceratops.png` → `Triceratops.png`).
- Examples: `Tyrannosaurus.webp`, `Brachiosaurus.jpg`, `Velociraptor.png`
- Allowed extensions: `.webp`, `.jpg`, `.jpeg`, `.png`

## Generate

`--version` is required:

```bash
make run-dinosaur-image-generate CRON_EXTRA='--version Original --max-items 5'
make run-dinosaur-image-generate CRON_EXTRA='--version "Summer 26" --dinos Tyrannosaurus'
```

## Sync to Railway

1. Add or update image files under `images/dinosaurs/<version>/`.
2. On the **backend** Railway service (not Postgres): mount a volume at `/data` (recommended) or `/data/images/dinosaurs`, set `CURATED_IMAGES_DATA_ROOT=/data` and/or `DINOSAUR_IMAGES_DIR=/data/images/dinosaurs`, and set `DINOSAUR_IMAGE_SYNC_SECRET`.
3. Run from the repo root — reads **local** files here, uploads to the **deployed** Railway API:

```bash
make sync-dinosaur-images
```

Dry run (preview matches, no upload or DB changes):

```bash
make sync-dinosaur-images CRON_EXTRA='--dry-run'
```

Set `PUBLIC_BASE_URL` on Railway (e.g. `https://mesozoica-production.up.railway.app`) and the same `DINOSAUR_IMAGE_SYNC_SECRET` locally via `railway run` so `main_image_url` is stored correctly and uploads are authorized.

Image binaries are gitignored; only this README and `.gitkeep` are tracked. Version `meta.yaml` files should be committed when present.
