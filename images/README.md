# Images

Local source and (for user uploads) runtime image storage for Mesozoica.

| Subfolder | Contents | Public URL |
|-----------|----------|------------|
| `dinosaurs/` | Named version folders (`Original/`, `Summer 26/`, …) | `/media/dinosaurs/<version>/` |
| `fossils/` | Named version folders (`Original/`, …) | `/media/fossils/<version>/` |
| `site-types/` | Named version folders (`Original/`, `Summer 26/`, …) | `/media/site-types/<version>/` |
| `tools/` | Named version folders (`Original/`, `Summer 26/`, …) | `/media/tools/<version>/` |
| `users/` | User profile photos | `/media/users/` |

Each version folder has a `meta.yaml` with `prompt` and `run_date`. Image binaries are gitignored; READMEs, `.gitkeep`, and version `meta.yaml` files are tracked. Sync curated cards to Railway with `make sync-dinosaur-images`, `make sync-fossil-images`, `make sync-site-type-images`, and `make sync-tool-images` (uploads local files, then deletes remote files that are not present locally).

Album-grid thumbs live beside full art as `{version}/album/{stem}.webp` (max 384×512). Sync writes them locally from the full card file when missing/stale, then uploads both the full image and the album thumb.

Catalog cards (dinosaur/tool types) always resolve the `Original` folder. Occurrences store a `version` string and resolve that folder. New occurrences get the newest version by `meta.yaml` `run_date`.

`run_date` is also copied into `backend/app/data/curated_version_meta/` (Docker image) so workers without the curated-image volume still stamp the correct version. After editing a version `meta.yaml`, run `make sync-bundled-version-meta`.

On Railway, mount one volume at `/data` and set `CURATED_IMAGES_DATA_ROOT=/data`. Storage then resolves to `/data/images/...`.
