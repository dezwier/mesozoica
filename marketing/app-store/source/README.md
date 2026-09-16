Seven portrait captures used by `scripts/generate_app_store_screenshots.py`, in App Store order:

1. `01-map-discovery.jpg` — Map tab with nearby sites
2. `02-dinosaur-triceratops.jpg` — Dinosaur catalog card
3. `03-site-cretaceous-marl.jpg` — Opened site card
4. `04-fossil-iguanodon.jpg` — Fossil catalog card
5. `05-tool-aerial-scout.jpg` — Tool catalog card
6. `06-cladogram-tree.jpg` — Cladogram tree
7. `07-profile-career.png` — Profile / career

From the repository root:

```bash
python3 scripts/generate_app_store_screenshots.py
```

Outputs: `iphone-6.9/`, `iphone-6.5/`, and `ipad-13/` (2064×2752 for App Store Connect’s 12.9"/13" slot).
