# Images

Local source and (for user uploads) runtime image storage for Mesozoica.

| Subfolder | Contents | Public URL |
|-----------|----------|------------|
| `dinosaurs/` | Dinosaur card images | `/media/dinosaurs/` |
| `fossils/` | Fossil card images | `/media/fossils/` |
| `site-types/` | Fossil site-type card images | `/media/site-types/` |
| `tools/` | Tool card images | `/media/tools/` |
| `users/` | User profile photos | `/media/users/` |

Image binaries are gitignored; only READMEs and `.gitkeep` files are tracked. Sync curated cards to Railway with `make sync-dinosaur-images`, `make sync-fossil-images`, `make sync-site-type-images`, and `make sync-tool-images`.

On Railway, mount one volume at `/data` and set `CURATED_IMAGES_DATA_ROOT=/data`. Storage then resolves to `/data/images/...`.
