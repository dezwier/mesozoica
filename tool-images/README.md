# Tool card images

Curated card-front images for the Mesozoica tool catalog. Files here are synced to Railway and served at `/media/tools/{filename}`.

## Naming

- Filename stem must match `tool.name` in the database (case-insensitive; canonical branded name casing is used on upload, e.g. `geo hammer.png` → `Geo Hammer.png`).
- Examples: `Orbit Survey.webp`, `Geo Hammer.jpg`, `Field Codex.png`
- Allowed extensions: `.webp`, `.jpg`, `.jpeg`, `.png`

## Sync to Railway

1. Add or update image files in this folder (`mesozoica/tool-images/` in your repo).
2. On the **backend** Railway service (not Postgres): mount a volume at `/data` (recommended) or `/data/tool-images`, set `CURATED_IMAGES_DATA_ROOT=/data` and/or `TOOL_IMAGES_DIR=/data/tool-images`, and set `TOOL_IMAGE_SYNC_SECRET`.
3. Run from the repo root — reads **local** files here, uploads to the **deployed** Railway API:

```bash
make sync-tool-images
```

Dry run (preview matches, no upload or DB changes):

```bash
make sync-tool-images CRON_EXTRA='--dry-run'
```

Set `PUBLIC_BASE_URL` on Railway (e.g. `https://mesozoica-production.up.railway.app`) and the same `TOOL_IMAGE_SYNC_SECRET` locally via `railway run` so `main_image_url` is stored correctly and uploads are authorized.

Image binaries are gitignored; only this README and `.gitkeep` are tracked.
