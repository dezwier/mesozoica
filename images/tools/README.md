# Tool card images

Curated card-front images for the Mesozoica tool catalog. Files live in named version folders and are synced to Railway at `/media/tools/<version>/{filename}`.

## Layout

```
images/tools/Original/meta.yaml
images/tools/Original/Orbit Survey.png
images/tools/Summer 26/...
```

`meta.yaml` fields:

- `prompt` — Imagen instruction template used for this version (placeholders filled per tool)
- `run_date` — UTC timestamp used when assigning the newest version to new tool occurrences

## Naming

- Filename stem must match `tool.name` in the database (case-insensitive; canonical branded name casing is used on upload, e.g. `geo hammer.png` → `Geo Hammer.png`).
- Examples: `Orbit Survey.webp`, `Geo Hammer.jpg`, `Field Codex.png`
- Allowed extensions: `.webp`, `.jpg`, `.jpeg`, `.png`

## Generate

`--version` is required (named folder):

```bash
make run-tool-image-generate-local CRON_EXTRA='--version Original'
make run-tool-image-generate-local CRON_EXTRA='--version "Summer 26" --max-items 5'
```

If `meta.yaml` already has a `prompt`, that template is reused. Missing prompt/`run_date` are written from the current code template / now (existing `run_date` is preserved).

## Sync to Railway

1. Add or update image files under `images/tools/<version>/`.
2. On the **backend** Railway service (not Postgres): mount a volume at `/data` (recommended) or `/data/images/tools`, set `CURATED_IMAGES_DATA_ROOT=/data` and/or `TOOL_IMAGES_DIR=/data/images/tools`, and set `TOOL_IMAGE_SYNC_SECRET`.
3. Run from the repo root — reads **local** files here, uploads to the **deployed** Railway API:

```bash
make sync-tool-images
```

Sync also uploads each version’s `meta.yaml` and deletes remote files that are not present locally (for example old `v1/` folders after a rename).

Dry run (preview matches, meta, and prune — no upload, delete, or DB changes):

```bash
make sync-tool-images CRON_EXTRA='--dry-run'
```

Set `PUBLIC_BASE_URL` on Railway (e.g. `https://mesozoica-production.up.railway.app`) and the same `TOOL_IMAGE_SYNC_SECRET` locally via `railway run` so `main_image_url` is stored correctly and uploads are authorized.

Image binaries are gitignored; only this README and `.gitkeep` are tracked. Version `meta.yaml` files should be committed when present.
