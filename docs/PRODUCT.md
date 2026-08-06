# 🦖 Project Codex: DinoGo PRD

> Product vision and historical milestone record. Some implementation-status
> sections below describe an earlier phase and are not an authoritative
> inventory of the current application. Agents should use
> [`../AGENTS.md`](../AGENTS.md), [`DOMAIN.md`](DOMAIN.md), and the
> code/tests for current behavior.

## 1. Overview & Vision
 * **Elevator Pitch:** A highly realistic, scientifically accurate, location-based AR/Map game (think *Pokémon GO* meets *Museum of Natural History*) where users discover, excavate, and assemble prehistoric life based on real-world paleontological data.
 * **Target Audience:** Adults, science enthusiasts, and history nerds. The tone is sophisticated, academic, and gritty—not cartoonish.
 * **Core Loop:** Travel to real excavation sites \rightarrow Use specialized tools to extract fossils \rightarrow Clean and assemble fossils in the Lab \rightarrow Display completed skeletons in a personal Museum \rightarrow Explore evolutionary links in the Tree of Life.
## 2. Core Mechanics & The 4 Card Types
Every major element in the game exists as a collectible, flippable "Card" or Item with detailed back-end metadata.
 * **Excavation Sites (Card 1):** Real-world geographical locations known for fossil discoveries. Contains data on geological formations, rock layers, and age.
 * **Tools (Card 2):** Wearable, upgradeable equipment used in the Lab (e.g., rock chisels, air scribes, dental picks, sonic cleaners).
 * **Fossils (Card 3):** Unassembled fragments (e.g., "Left Femur of *Tyrannosaurus rex*", "Partial Cranium of *Triceratops*"). Includes completeness percentages and matrix/rock type.
 * **Dinosaurs (Card 4):** The ultimate reward. Fully assembled, historically accurate species populated entirely via automated live data snapshots.
## 3. Data Pipeline & Wikipedia Engine
To maintain absolute scientific realism, the database relies on an automated scraping engine rather than manual data entry.
 * **The Wikipedia API Script:** A Python cron job (`app/crons/jobs/dinosaur_wiki_sync.py`) that weekly queries `Category:Dinosaur_genera` on English Wikipedia.
 * **Data Extraction:** Parses full Parsoid HTML articles, infobox quick-facts (temporal range, taxonomy, diet), and lead paragraphs. Short descriptions are **not** set here — they are produced by the LLM enrichment cron.
 * **Cladogram Parsing:** Extracts phylogenetic data from the infobox biota table (Kingdom → Genus, plus Species when present) into JSON for the Tree of Life.
 * **Lead Image:** Wikipedia sync fetches the page lead image via MediaWiki `pageimages` and stores it in `main_image_url` on insert; existing non-null URLs are preserved on update. Card fronts use **curated** images only (see below); Wikipedia URLs are not shown on the card front.
 * **Curated Card Images:** Source files live in repo `images/dinosaurs/` (filename stem = `dinosaur.name`, e.g. `Tyrannosaurus.webp`). `make sync-dinosaur-images` uploads files to a Railway volume via `railway volume files upload` and sets `main_image_url` to `{PUBLIC_BASE_URL}/media/dinosaurs/{filename}`. The FastAPI backend serves files from the mounted volume at `/media/dinosaurs/`.
 * **Snapshot Schema:** The sync can be rerun safely — it skips up-to-date records, refreshes stale ones by Wikipedia revision date, preserves `insert_date` and `main_image_url` on updates, and resets `llm_enriched=false` when article content is refreshed.
 * **Manual run:** `make run-dinosaur-wiki-sync` or `python -m app.crons.runner --job dinosaur_wiki_sync`
 * **Curated image sync:** `make sync-dinosaur-images` or `python -m scripts.sync_dinosaur_images` (supports `--dry-run`)
 * **The LLM Enrichment Engine:** A second Python cron (`app/crons/jobs/dinosaur_llm_enrich.py`) runs after the Wikipedia sync. For each dinosaur with `llm_enriched=false`, it sends the full record (including article text) to Google Gemini and fills `length`, `mass`, `location`, `diet_type`, and a catchy one-sentence `short_description`. Sets `llm_enriched=true` on success. Re-runs automatically when Wikipedia sync refreshes a stale article.
 * **LLM manual run:** `make run-dinosaur-llm-enrich` or `python -m app.crons.runner --job dinosaur_llm_enrich`
## 4. App Architecture & Screens
### Primary navigation (v0)
Four bottom tabs using an `IndexedStack` shell (mesosoica-style brown/sandstone Material 3 theme):

| Tab | Screen | v0 status |
|-----|--------|-----------|
| **Map** | Discovery map | Live Mapbox map (archive / field); marker UX contract in [`../flutter/docs/map_site_markers.md`](../flutter/docs/map_site_markers.md) |
| **Tree** | Tree of Life | Skeleton placeholder |
| **Dino** | Dinosaur catalog | Scrollable turnable cards for every row in `dinosaur` table |
| **Profile** | Account & settings | Skeleton placeholder |

### Dino catalog & turnable cards
The **Dino** tab lists every dinosaur from `GET /api/v1/dinosaurs` as museum-style flippable cards (Y-axis 3D rotation — tap left/right half or horizontal drag, ported from archipelago `TurnableYAxisCard` mechanics).

**Front face**
 * Curated card image from Railway (`/media/dinosaurs/{name}`) full-bleed with gradient overlay; bundled placeholder when no curated image is synced
 * Species name in caps; optional one-line `short_description`

**Back face**
 * **Facts:** location, period (with Ma range when available), diet, length, mass
 * **Cladogram strip:** lineage from *Dinosauria* through genus (from `cladogram` JSON)
 * **Geologic timeline:** fixed deep-time scale **250 Ma (top) → 66 Ma (bottom)** with an orange band/dot for `[birth, death]`

Card chrome uses a separate dark museum palette (charcoal background, bronze/gold border) distinct from the app shell theme.

**Filtering**
 * Floating filter FAB (archipelago-style, bottom-right) opens a draggable bottom drawer.
 * **Name search** — case-insensitive substring match on species name (`q` query param).
 * **Time range slider** — dual-handle Mesozoic window **66 Ma → 252 Ma**; filters dinosaurs whose `[death, birth]` interval overlaps the selected range (`ma_younger`, `ma_older` query params). Rows missing dates are excluded only when the window is narrowed from the full range.
 * Server-side filtered pagination via `GET /api/v1/dinosaurs?q&ma_younger&ma_older`; random sort with seed is preserved within the filtered result set.

### Future game screens (not in v0 nav)
These remain part of the long-term vision but are deferred until core catalog + map/tree are built:

 * **The Lab (Preparation & Assembly):** Industrial workbench — clean fossils with tools, puzzle assembly to unlock dinosaur cards.
 * **The Museum (Exhibition):** Personal dimly lit hall showcasing *user-owned* completed skeletons (distinct from the global Dino catalog browse tab).

#### Map (current + future)
 * Live Mapbox discovery map with archive and field site markers. Paint rules: wipe only on Archive/Field or linked/show-all (or filter) toggles, then batches of 500 from cache; pan/zoom/scan keep markers and diff. Full contract: [`../flutter/docs/map_site_markers.md`](../flutter/docs/map_site_markers.md).
 * Dark tactical satellite map with real-world geological boundaries and dig sites (future polish).
 * Proximity-based excavation nodes; check-in to begin a dig.

#### Tree of Life (future mechanics)
 * Interactive fern-fractal phylogeny with deep time on Y-axis and clades on branches.
 * Infinite zoom; completed dinosaurs light up, missing ones remain silhouettes.

## 5. System Architecture & Tech Stack
### Repository layout
```
mesozoica/
├── backend/          # FastAPI + PostgreSQL (deployed on Railway)
│   ├── app/          # core/, api/v1/, models/, schemas/, services/, crons/
│   ├── scripts/      # sync_dinosaur_images.py (curated card image upload)
│   ├── alembic/      # DB migrations
│   ├── tests/
│   ├── Dockerfile
│   ├── railway.toml          # API service
│   └── railway.cron.toml     # Cron service (Wikipedia sync)
├── images/           # Curated + user images (dinosaurs/, fossils/, site-types/, tools/, users/)
├── flutter/          # Flutter mobile app (iOS & Android)
│   └── lib/          # config/, controllers/, models/, screens/, services/, shell/, theme/, widgets/
├── Makefile          # make run-backend, run-dinosaur-wiki-sync, test-all
├── railway.toml      # Monorepo Railway service roots
└── docs/PRODUCT.md
```
### Backend
 * **Language/Framework:** FastAPI (Python) for rapid, high-performance asynchronous API endpoints and data parsing.
 * **Location:** `backend/` — layered structure: thin routers in `api/v1/endpoints/`, business logic in `services/`, SQLModel tables in `models/`.
 * **Database:** PostgreSQL on Railway. PostGIS extensions planned for spatial mapping/location querying (not enabled in scaffold).
 * **Deployment:** Railway Dockerfile build; `alembic upgrade head` runs on startup; health at `/health`, readiness at `/ready`. Attach a Railway volume mounted at `/data` on the backend service; curated images live under `/data/images/{dinosaurs,fossils,site-types,tools}/` when `CURATED_IMAGES_DATA_ROOT=/data`.
 * **Static media:** `GET /media/dinosaurs/{filename}` serves curated card images from `DINOSAUR_IMAGES_DIR` (volume mount in production, repo `images/dinosaurs/` in local dev).
 * **Data Sync:** Cron runner at `app/crons/runner.py` loads schedules from `app/crons/crons.yaml`. Deploy as a separate Railway cron service via `backend/railway.cron.toml` (hourly trigger; jobs define their own UTC schedules).
 * **Dinosaur table:** `dinosaur` — name, birth/death (Ma), period, cladogram (JSON), diet_type, length, mass, location, short_description (LLM-only), long_description, full article HTML, article_date, insert_date, main_image_url (curated Railway URL after sync; Wikipedia URL as metadata fallback), llm_enriched (bool).
 * **Dinosaur read API:** `GET /api/v1/dinosaurs` (paginated list, optional `q`, `ma_younger`, `ma_older` filters, card summary fields), `GET /api/v1/dinosaurs/{id}` (single summary).
### Frontend
 * **Framework:** Flutter (Dart) for high-performance, cross-platform fluid UI rendering (iOS and Android).
 * **Location:** `flutter/` — domain folders mirror tabs (`screens/map`, `screens/tree`, `screens/dino`, `screens/profile`), shared `shell/app_shell.dart`, card widgets under `widgets/cards/`.
 * **State:** `provider` + `ChangeNotifier` controllers (e.g. `DinosaurCatalogController`).
 * **Config:** `lib/config/app_config.dart` — API base URL (localhost dev, Railway prod).
 * **Map Integration:** Custom styled Mapbox or Google Maps SDK with custom geological layers (future).
 * **Fractal Engine:** Custom canvas painting or CustomPainter in Flutter to handle the smooth, mathematical scaling of the Fern Fractal Tree of Life (future).
## 6. Future Expansion Ideas (Keep Adding Below)
 * [ ] **PostGIS spatial queries:** Enable PostGIS on Railway Postgres for excavation-site proximity search.
 * [x] **Wikipedia snapshot cron (dinosaur slice):** Weekly sync of `Category:Dinosaur_genera` into the `dinosaur` table.
 * [x] **LLM enrichment cron (dinosaur slice):** Weekly Gemini enrichment of length, mass, location, diet_type, and short_description.
 * [x] **Dinosaur read API:** Paginated list + detail endpoints for Flutter catalog.
 * [x] **Dino catalog filtering:** Floating filter FAB with name search and Mesozoic Ma range slider.
 * [x] **Wikipedia lead image auto-fill:** Populate `main_image_url` during sync (metadata; card front uses curated images).
 * [x] **Curated card images:** Repo folder + Railway volume sync + static serving on card front.
 * [ ] **Authentication:** User accounts and inventory persistence.
 * [ ] **Carbon Dating System:** Introduce a decay mechanic where users must balance isotopes to verify fossil age.
 * [ ] **Continental Drift Simulator:** A toggle on the map screen to view what the current dig site looked like 100 million years ago via Pangea/Laurasia tectonic tracking.
 * [ ] **Museum Trading / Loaning:** Allow players to loan out rare skeletons to other players' museums for passive in-game research grants.
## 7. Repository & Dev Setup
### Local development
```bash
make backend-install
cp backend/.env.example backend/.env   # set DATABASE_URL to Railway Postgres or any PostgreSQL
make run-backend                       # http://localhost:8000/docs
make run-dinosaur-wiki-sync                # one-off Wikipedia dinosaur ingest
make run-dinosaur-llm-enrich               # one-off Gemini dinosaur enrichment
make sync-dinosaur-images              # upload curated card images to Railway volume + DB

cd flutter && flutter pub get
make run-flutter
make test-all                          # backend pytest + flutter test
```
No docker-compose — point `backend/.env` at a managed Postgres instance (Railway plugin or other).

Wikipedia sync env vars (see `backend/.env.example`): `WIKIPEDIA_USER_AGENT` (required in production), `WIKIPEDIA_DINOSAUR_CATEGORY`, `WIKIPEDIA_REQUEST_DELAY_MS`, optional `WIKIPEDIA_SYNC_MAX_PAGES` for dev caps.

Gemini enrichment env vars: `GOOGLE_GEMINI_API_KEY` (required in production for enrich cron), `GEMINI_MODEL`, `GEMINI_TEMPERATURE`, optional `DINOSAUR_ENRICH_MAX_RECORDS`, `DINOSAUR_ENRICH_FAILURE_THRESHOLD`, `DINOSAUR_ENRICH_REQUEST_DELAY_MS`, `DINOSAUR_ENRICH_ARTICLE_MAX_CHARS`.

Curated card image env vars (backend service): `CURATED_IMAGES_DATA_ROOT=/data` (recommended), optional per-type `*_IMAGES_DIR` overrides, `PUBLIC_BASE_URL` (public API base for stored URLs), and `*_IMAGE_SYNC_SECRET` for admin uploads.
### Railway deployment
1. Create a Railway project and add a **PostgreSQL** database.
2. Add a **backend** service with root directory `backend` (declared in root `railway.toml`).
3. Link `DATABASE_URL` from Postgres to the backend service.
4. Set variables: `SECRET_KEY`, `ENVIRONMENT=production`, `CORS_ORIGINS` (explicit origins, no `*`), `WIKIPEDIA_USER_AGENT`, `GOOGLE_GEMINI_API_KEY`, `PUBLIC_BASE_URL`, `CURATED_IMAGES_DATA_ROOT=/data`.
5. Attach a **volume** to the backend service mounted at `/data` (images resolve under `/data/images/...`).
6. Deploy — Dockerfile runs migrations then starts uvicorn on `$PORT`.
7. Add a **cron** service with config file path `backend/railway.cron.toml`; link the same `DATABASE_URL`.
8. Add curated images to local `images/` subfolders and run the matching `make sync-*-images` targets.
### Implementation status
| Area | Status |
|------|--------|
| Backend scaffold (FastAPI, health, Alembic wired) | Done |
| Flutter scaffold (MaterialApp shell, app config) | Done |
| Domain models & DB migrations | Partial (dinosaur table) |
| 4-tab shell (Map, Tree, Dino, Profile) | Done (Map/Tree/Profile placeholders) |
| Dinosaur read API | Done |
| Dino catalog + turnable cards | Done (skeleton UI, full card layout) |
| Dino catalog filtering (search + time range) | Done |
| Curated card images (Railway volume + sync) | Done |
| Wikipedia data pipeline | Partial (dinosaur sync cron + lead image) |
| LLM enrichment pipeline | Partial (dinosaur enrich cron) |
| Map / Tree interactive features | Not started |
| Lab / Museum game loops | Not started |
| PostGIS / spatial queries | Not started |
| Auth & user inventory | Not started |
