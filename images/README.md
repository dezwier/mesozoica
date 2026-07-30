# Images

Local source and (for user uploads) runtime image storage for Mesozoica.

| Subfolder | Contents | Public URL |
|-----------|----------|------------|
| `dinosaurs/` | Named version folders (`Original/`, `Summer 26/`, …) | `/media/dinosaurs/<version>/` |
| `fossils/` | Named version folders (`Original/`, …) | `/media/fossils/<version>/` |
| `site-types/` | Named version folders (`Original/`, `Summer 26/`, …) | `/media/site-types/<version>/` |
| `tools/` | Named version folders (`Original/`, `Summer 26/`, …) | `/media/tools/<version>/` |
| `users/` | User profile photos | `/media/users/` |

Each version folder has a `meta.yaml` with `prompt` and `run_date`. Image binaries are gitignored; READMEs, `.gitkeep`, and version `meta.yaml` files are tracked. Sync curated cards to Railway with `make sync-dinosaur-images`, `make sync-fossil-images`, `make sync-site-type-images`, and `make sync-tool-images`.

Catalog cards (dinosaur/tool types) always resolve the `Original` folder. Occurrences store a `version` string and resolve that folder. New occurrences get the newest version by `meta.yaml` `run_date`.

On Railway, mount one volume at `/data` and set `CURATED_IMAGES_DATA_ROOT=/data`. Storage then resolves to `/data/images/...`.
