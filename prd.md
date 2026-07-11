# 🦖 Project Codex: DinoGo PRD
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
 * **The Wikipedia API Script:** A Python cron job (`app/crons/jobs/wikipedia_dinosaur_sync.py`) that weekly queries `Category:Dinosaur_genera` on English Wikipedia.
 * **Data Extraction:** Parses full Parsoid HTML articles, infobox quick-facts (temporal range, taxonomy, diet), short descriptions, and lead paragraphs.
 * **Cladogram Parsing:** Extracts phylogenetic data from the infobox biota table (Kingdom → Genus, plus Species when present) into JSON for the Tree of Life.
 * **Snapshot Schema:** The sync can be rerun safely — it skips up-to-date records, refreshes stale ones by Wikipedia revision date, and preserves `insert_date` and `main_image_url` on updates.
 * **Manual run:** `make run-wikipedia-sync` or `python -m app.crons.runner --job wikipedia_dinosaur_sync`
## 4. App Architecture & Screens
### 🏛️ Screen 1: The Map (Discovery)
 * **Visuals:** Dark, tactical, modern satellite map interface highlighting real-world geological boundaries and known dig sites.
 * **Mechanics:**
   * Displays proximity-based excavation nodes.
   * Tapping a site opens its "Excavation Card," showing geological epoch (e.g., Late Cretaceous) and potential fossil yields.
   * Users "check-in" to a site to begin a dig.
### 🥽 Screen 2: The Lab (Preparation & Assembly)
 * **Visuals:** Clean, industrial laboratory workbench interface.
 * **Mechanics:**
   * **Inventory:** Displays collected, uncleaned fossils.
   * **The Mini-Game:** Users select a tool (e.g., brush for soft sediment, chisel for hard rock) to carefully remove matrix rock from the fossil. Incorrect tool usage lowers fossil integrity.
   * **Assembly:** Once all required fossil cards for a specimen are prepped, users puzzle them together to unlock the final Dinosaur Card.
### 🖼️ Screen 3: The Museum (Exhibition)
 * **Visuals:** High-end, dimly lit digital exhibition hall.
 * **Mechanics:**
   * Showcases the user's completed, fully reconstructed dinosaurs.
   * Tapping a dinosaur flips its card to show extensive scientific data pulled from the wiki database: size comparison charts, diet, discovery year, and full historical articles.
### 🌿 Screen 4: The Tree of Life (Phylogeny)
 * **Visuals:** An interactive, mathematically generated **Fern Fractal** visualization.
 * **Mechanics:**
   * **Y-Axis:** Represents Deep Time (Millions of Years Ago - Ma), transitioning from the Triassic through the Cretaceous.
   * **X-Axis/Branches:** Evolutionary clades (Theropoda, Sauropodomorpha, Ornithischia).
   * **Interaction:** Smooth, infinite zoom-in capabilities. Users can trace a direct evolutionary path from a single-celled organism down into specific dinosaur families. Completed dinosaurs light up on the tree; missing ones remain as shadowed silhouettes.
## 5. System Architecture & Tech Stack
### Repository layout
```
mesozoica/
├── backend/          # FastAPI + PostgreSQL (deployed on Railway)
│   ├── app/          # core/, api/v1/, models/, schemas/, services/, crons/
│   ├── alembic/      # DB migrations
│   ├── tests/
│   ├── Dockerfile
│   ├── railway.toml          # API service
│   └── railway.cron.toml     # Cron service (Wikipedia sync)
├── flutter/          # Flutter mobile app (iOS & Android)
│   └── lib/          # config/, models/, screens/, services/, widgets/
├── Makefile          # make run-backend, run-wikipedia-sync, test-all
├── railway.toml      # Monorepo Railway service roots
└── prd.md
```
### Backend
 * **Language/Framework:** FastAPI (Python) for rapid, high-performance asynchronous API endpoints and data parsing.
 * **Location:** `backend/` — layered structure: thin routers in `api/v1/endpoints/`, business logic in `services/`, SQLModel tables in `models/`.
 * **Database:** PostgreSQL on Railway. PostGIS extensions planned for spatial mapping/location querying (not enabled in scaffold).
 * **Deployment:** Railway Dockerfile build; `alembic upgrade head` runs on startup; health at `/health`, readiness at `/ready`.
 * **Data Sync:** Cron runner at `app/crons/runner.py` loads schedules from `app/crons/crons.yaml`. Deploy as a separate Railway cron service via `backend/railway.cron.toml` (hourly trigger; jobs define their own UTC schedules).
 * **Dinosaur table:** `dinosaur` — name, birth/death (Ma), period, cladogram (JSON), diet_type, short/long descriptions, full article HTML, article_date, insert_date, main_image_url (manual fill).
### Frontend
 * **Framework:** Flutter (Dart) for high-performance, cross-platform fluid UI rendering (iOS and Android).
 * **Location:** `flutter/` — domain folders mirror PRD screens (`screens/`, `services/`, `widgets/`).
 * **Config:** `lib/config/app_config.dart` — API base URL (localhost dev, Railway prod).
 * **Map Integration:** Custom styled Mapbox or Google Maps SDK with custom geological layers (future).
 * **Fractal Engine:** Custom canvas painting or CustomPainter in Flutter to handle the smooth, mathematical scaling of the Fern Fractal Tree of Life (future).
## 6. Future Expansion Ideas (Keep Adding Below)
 * [ ] **PostGIS spatial queries:** Enable PostGIS on Railway Postgres for excavation-site proximity search.
 * [x] **Wikipedia snapshot cron (dinosaur slice):** Weekly sync of `Category:Dinosaur_genera` into the `dinosaur` table.
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
make run-wikipedia-sync                # one-off Wikipedia dinosaur ingest

cd flutter && flutter pub get
make run-flutter
make test-all                          # backend pytest + flutter test
```
No docker-compose — point `backend/.env` at a managed Postgres instance (Railway plugin or other).

Wikipedia sync env vars (see `backend/.env.example`): `WIKIPEDIA_USER_AGENT` (required in production), `WIKIPEDIA_DINOSAUR_CATEGORY`, `WIKIPEDIA_REQUEST_DELAY_MS`, optional `WIKIPEDIA_SYNC_MAX_PAGES` for dev caps.
### Railway deployment
1. Create a Railway project and add a **PostgreSQL** database.
2. Add a **backend** service with root directory `backend` (declared in root `railway.toml`).
3. Link `DATABASE_URL` from Postgres to the backend service.
4. Set variables: `SECRET_KEY`, `ENVIRONMENT=production`, `CORS_ORIGINS` (explicit origins, no `*`), `WIKIPEDIA_USER_AGENT`.
5. Deploy — Dockerfile runs migrations then starts uvicorn on `$PORT`.
6. Add a **cron** service with config file path `backend/railway.cron.toml`; link the same `DATABASE_URL`.
### Implementation status
| Area | Status |
|------|--------|
| Backend scaffold (FastAPI, health, Alembic wired) | Done |
| Flutter scaffold (MaterialApp shell, app config) | Done |
| Domain models & DB migrations | Partial (dinosaur table) |
| Map / Lab / Museum / Tree of Life screens | Not started |
| Wikipedia data pipeline | Partial (dinosaur sync cron) |
| PostGIS / spatial queries | Not started |
| Auth & user inventory | Not started |
