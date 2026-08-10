SHELL := /bin/bash

# Optional override: make run-dinosaur-wiki-sync RAILWAY_SERVICE=my-service
# Default: uses the service from `cd backend && railway link`
RAILWAY_SERVICE ?=
RAILWAY_SERVICE_FLAG = $(if $(RAILWAY_SERVICE),--service $(RAILWAY_SERVICE),)
CRON_EXTRA ?=
PYTHON ?= python3

.PHONY: help architecture-check architecture-report docs-check backend-runtime-check backend-install backend-test run-backend flutter-analyze flutter-test run-flutter test-all quality run-cron run-game-config-seed run-field-ensure-worker fetch-coordinate-masks upload-coordinate-masks-railway run-field-site-coordinate-prune run-weather-sync run-dinosaur-wiki-sync run-dinosaur-llm-enrich run-dinosaur-knowledge-acquire run-dinosaur-knowledge-index run-dinosaur-knowledge-status run-dinosaur-knowledge-evaluate run-dinosaur-quiz-preview run-fossil-pbdb-sync run-fossil-llm-enrich run-site-sync run-site-type-sync run-tool-sync run-dinosaur-image-generate run-fossil-image-generate run-site-type-image-generate run-tool-image-generate run-tool-image-generate-local sync-dinosaur-images sync-fossil-images sync-site-type-images sync-tool-images sync-bundled-version-meta rename-site-type-images migrate-image-versions-to-v1 migrate-named-image-versions backfill-user-levels

help:
	@echo "Available targets:"
	@echo "  backend-install              Install backend Python dependencies"
	@echo "  backend-runtime-check        Require Python 3.10+ (including backend/.venv)"
	@echo "  backend-test                 Run backend pytest suite"
	@echo "  run-backend                  Start FastAPI dev server (reads backend/.env)"
	@echo "  run-cron                     Run due cron jobs on Railway"
	@echo "  run-field-ensure-worker      Run field ensure worker on Railway"
	@echo "  fetch-coordinate-masks       Download OSM land/water polygon shapefiles (local dev)"
	@echo "  upload-coordinate-masks-railway  Upload local OSM masks to Railway /data volume"
	@echo "  run-field-site-coordinate-prune  Delete field sites failing coordinate filters (needs local OSM masks; make fetch-coordinate-masks)"
	@echo "  run-weather-sync             weather_sync on Railway (hourly past+forecast per active cell)"
	@echo "  run-dinosaur-wiki-sync       dinosaur_wiki_sync on Railway"
	@echo "  run-dinosaur-llm-enrich      dinosaur_llm_enrich on Railway"
	@echo "  run-dinosaur-knowledge-acquire  resumable Wikipedia/OpenAlex acquisition"
	@echo "  run-dinosaur-knowledge-index    sync acquired snapshots into Azure AI Search"
	@echo "  run-dinosaur-knowledge-status   show acquisition/index checkpoints"
	@echo "  run-dinosaur-knowledge-evaluate run golden retrieval metrics"
	@echo "  run-dinosaur-quiz-preview       generate one structured RAG quiz preview"
	@echo "  run-fossil-pbdb-sync         fossil_pbdb_sync on Railway"
	@echo "  run-fossil-llm-enrich        fossil_llm_enrich on Railway"
	@echo "  run-site-sync                site_sync on Railway"
	@echo "  run-site-type-sync           site_type_sync on Railway"
	@echo "  run-tool-sync                tool_sync on Railway"
	@echo "  run-game-config-seed         Publish backend/app/game_config/*.yaml into the DB"
	@echo "  run-dinosaur-image-generate  dinosaur_image_generate on Railway"
	@echo "  run-fossil-image-generate    fossil_image_generate on Railway"
	@echo "  run-site-type-image-generate site_type_image_generate on Railway"
	@echo "  run-tool-image-generate      tool_image_generate on Railway"
	@echo "  run-tool-image-generate-local tool_image_generate via backend/.env (faster for local PNGs)"
	@echo "  sync-dinosaur-images         Upload curated card images to Railway volume + DB"
	@echo "  sync-fossil-images           Upload curated fossil card images to Railway volume + DB"
	@echo "  sync-site-type-images        Upload curated site-type card images to Railway volume + DB"
	@echo "  sync-tool-images             Upload curated tool card images to Railway volume + DB"
	@echo "  sync-bundled-version-meta    Copy images/*/meta.yaml run_dates into backend Docker bundle"
	@echo "  backfill-user-levels         Recompute skill XP from discoveries + distance (leveling.yaml)"
	@echo "  rename-site-type-images      Rename legacy numeric site-type image files to period_rocktype"
	@echo "  migrate-image-versions-to-v1 Move flat images into Original/ + write meta.yaml"
	@echo "  migrate-named-image-versions Rename v1/v2 -> Original/Summer 26; migrate flat fossils"
	@echo "  flutter-test                 Run Flutter tests"
	@echo "  flutter-analyze              Analyze; informational baseline is non-fatal"
	@echo "  docs-check                   Validate required guides and local Markdown links"
	@echo "  quality                      Run architecture, analysis, and all tests"
	@echo "  run-flutter                  Start Flutter app"
	@echo "  test-all                     Run backend and Flutter tests"
	@echo ""
	@echo "Cron jobs always run via Railway (never a local DB). Examples:"
	@echo "  make run-dinosaur-wiki-sync CRON_EXTRA='--overwrite'"
	@echo "  make run-dinosaur-wiki-sync CRON_EXTRA='--category \"Category:Feathered dinosaurs\"'"
	@echo "  make run-dinosaur-wiki-sync CRON_EXTRA='--dinos Tyrannosaurus Giganotosaurus'"
	@echo "  make run-dinosaur-llm-enrich CRON_EXTRA='--overwrite'"
	@echo "  make run-dinosaur-llm-enrich CRON_EXTRA='--dinos Tyrannosaurus --overwrite'"
	@echo "  make run-dinosaur-knowledge-acquire CRON_EXTRA='--dinos Tyrannosaurus --sources wikipedia openalex'"
	@echo "  make run-dinosaur-knowledge-index CRON_EXTRA='--dinos Tyrannosaurus'"
	@echo "  make run-dinosaur-quiz-preview CRON_EXTRA='--dinos Tyrannosaurus'"
	@echo "  make run-fossil-pbdb-sync CRON_EXTRA='--dinos Tyrannosaurus'"
	@echo "  make run-fossil-pbdb-sync CRON_EXTRA='--overwrite'"
	@echo "  make run-fossil-pbdb-sync CRON_EXTRA='--dinos Tyrannosaurus --overwrite'"
	@echo "  make run-fossil-llm-enrich CRON_EXTRA='--dinos Tyrannosaurus'"
	@echo "  make run-fossil-llm-enrich CRON_EXTRA='--overwrite'"
	@echo "  make run-dinosaur-image-generate CRON_EXTRA='--version Original --max-items 5'"
	@echo "  make run-dinosaur-image-generate CRON_EXTRA='--version \"Summer 26\" --dinos Tyrannosaurus --dry-run'"
	@echo "  make run-fossil-image-generate CRON_EXTRA='--version Original --max-items 10'"
	@echo "  make run-site-type-image-generate CRON_EXTRA='--version Original --max-items 3 --dry-run'"
	@echo "  make run-site-type-image-generate CRON_EXTRA='--version \"Summer 26\" --site-types 5 18 20'"
	@echo "  make run-tool-image-generate-local CRON_EXTRA='--version \"Summer 26\" --max-items 3'"
	@echo "  make migrate-named-image-versions"
	@echo "  make sync-bundled-version-meta"

backend-runtime-check:
	@if [ -x backend/.venv/bin/python ]; then backend/.venv/bin/python -c 'import sys; assert sys.version_info >= (3, 10), "backend/.venv uses Python %s; recreate it with Python 3.10+" % sys.version.split()[0]'; else $(PYTHON) -c 'import sys; assert sys.version_info >= (3, 10), "Python 3.10+ required; current interpreter is %s" % sys.version.split()[0]'; fi

backend-install: backend-runtime-check
	@if [ ! -x backend/.venv/bin/python ]; then $(PYTHON) -m venv backend/.venv; fi
	backend/.venv/bin/python -m pip install --upgrade pip
	backend/.venv/bin/python -m pip install -r backend/requirements.txt -r backend/requirements-dev.txt
	backend/.venv/bin/python -m pip install -e 'backend/rag[test]'

backend-test: backend-runtime-check
	cd backend && .venv/bin/python -m pytest tests/ rag/tests/ -v

architecture-check:
	python3 backend/scripts/check_architecture.py

architecture-report:
	python3 backend/scripts/report_structure.py

docs-check:
	python3 backend/scripts/check_docs.py

run-backend:
	cd backend && uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# Cron jobs: railway run injects Railway DATABASE_URL and secrets.
run-cron:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner $(CRON_EXTRA)

run-field-ensure-worker:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) env MESOZOICA_MINIMAL_SETTINGS=1 python -m app.workers.field_ensure_worker

fetch-coordinate-masks:
	cd backend && .venv/bin/python -m scripts.fetch_osm_coordinate_masks

# Upload locally prepared OSM shapefiles to the Railway volume (/data/osm).
# Requires: volume mounted at /data, API service running, `make fetch-coordinate-masks` done.
upload-coordinate-masks-railway:
	@chmod +x backend/scripts/upload_osm_coordinate_masks_railway.sh
	RAILWAY_SERVICE="$(RAILWAY_SERVICE)" backend/scripts/upload_osm_coordinate_masks_railway.sh

run-field-site-coordinate-prune:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job field_site_coordinate_prune $(CRON_EXTRA)

run-weather-sync:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job weather_sync $(CRON_EXTRA)

run-dinosaur-wiki-sync:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job dinosaur_wiki_sync $(CRON_EXTRA)

run-dinosaur-llm-enrich:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job dinosaur_llm_enrich $(CRON_EXTRA)

run-dinosaur-knowledge-acquire:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job dinosaur_knowledge_acquire $(CRON_EXTRA)

run-dinosaur-knowledge-index:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job dinosaur_knowledge_index $(CRON_EXTRA)

run-dinosaur-knowledge-status:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job dinosaur_knowledge_status $(CRON_EXTRA)

run-dinosaur-knowledge-evaluate:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job dinosaur_knowledge_evaluate $(CRON_EXTRA)

run-dinosaur-quiz-preview:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job dinosaur_quiz_preview $(CRON_EXTRA)

run-fossil-pbdb-sync:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job fossil_pbdb_sync $(CRON_EXTRA)

run-fossil-llm-enrich:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job fossil_llm_enrich $(CRON_EXTRA)

run-site-sync:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job site_sync $(CRON_EXTRA)

run-site-type-sync:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job site_type_sync $(CRON_EXTRA)

run-tool-sync:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job tool_sync $(CRON_EXTRA)

run-game-config-seed:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job game_config_seed $(CRON_EXTRA)

run-dinosaur-image-generate:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job dinosaur_image_generate $(CRON_EXTRA)

run-fossil-image-generate:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job fossil_image_generate $(CRON_EXTRA)

run-site-type-image-generate:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job site_type_image_generate $(CRON_EXTRA)

run-tool-image-generate:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job tool_image_generate $(CRON_EXTRA)

# Image generation locally: uses backend/.env (Railway DATABASE_URL + GOOGLE_GEMINI_API_KEY).
# Skips `railway run` startup overhead; still writes PNGs to repo images/tools/.
run-tool-image-generate-local:
	cd backend && ALLOW_LOCAL_CRON=1 python -m app.crons.runner --job tool_image_generate $(CRON_EXTRA)

sync-dinosaur-images:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m scripts.sync_dinosaur_images $(CRON_EXTRA)

sync-fossil-images:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m scripts.sync_fossil_images $(CRON_EXTRA)

sync-site-type-images:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m scripts.sync_site_type_images $(CRON_EXTRA)

sync-tool-images:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m scripts.sync_tool_images $(CRON_EXTRA)

sync-bundled-version-meta:
	cd backend && python -m scripts.sync_bundled_version_meta $(CRON_EXTRA)

backfill-user-levels:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m scripts.backfill_user_levels $(CRON_EXTRA)

rename-site-type-images:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m scripts.rename_site_type_images $(CRON_EXTRA)

migrate-image-versions-to-v1:
	cd backend && .venv/bin/python -m scripts.migrate_image_versions_to_v1 $(CRON_EXTRA)

migrate-named-image-versions:
	cd backend && .venv/bin/python -m scripts.migrate_named_image_versions $(CRON_EXTRA)

flutter-test:
	cd flutter && flutter test

flutter-analyze:
	cd flutter && flutter analyze --no-fatal-infos

run-flutter:
	cd flutter && flutter run

test-all: backend-test flutter-test

quality: architecture-check docs-check backend-test flutter-analyze flutter-test
