# Dinosaur card images

Curated card-front images for the Mesozoica catalog. Files here are synced to Railway and served at `/media/dinosaurs/{filename}`.

## Naming

- Filename stem must match `dinosaur.name` in the database (case-insensitive; canonical Wikipedia title casing is used on upload, e.g. `triceratops.png` → `Triceratops.png`).
- Examples: `Tyrannosaurus.webp`, `Brachiosaurus.jpg`, `Velociraptor.png`
- Allowed extensions: `.webp`, `.jpg`, `.jpeg`, `.png`

## Sync to Railway

1. Add or update image files in this folder (`mesozoica/dinosaur-images/` in your repo).
2. On the **backend** Railway service (not Postgres): mount a volume at `/data/dinosaur-images`, set `DINOSAUR_IMAGES_DIR=/data/dinosaur-images`, and set `DINOSAUR_IMAGE_SYNC_SECRET`.
3. Run from the repo root — reads **local** files here, uploads to the **deployed** Railway API:

```bash
make sync-dinosaur-images
```

Dry run (preview matches, no upload or DB changes):

```bash
make sync-dinosaur-images CRON_EXTRA='--dry-run'
```

Set `PUBLIC_BASE_URL` on Railway (e.g. `https://mesozoica-production.up.railway.app`) and the same `DINOSAUR_IMAGE_SYNC_SECRET` locally via `railway run` so `main_image_url` is stored correctly and uploads are authorized.

Image binaries are gitignored; only this README and `.gitkeep` are tracked.
