SHELL := /bin/bash

# Optional override: make run-dinosaur-wiki-sync RAILWAY_SERVICE=my-service
# Default: uses the service from `cd backend && railway link`
RAILWAY_SERVICE ?=
RAILWAY_SERVICE_FLAG = $(if $(RAILWAY_SERVICE),--service $(RAILWAY_SERVICE),)
CRON_EXTRA ?=

.PHONY: help backend-install backend-test run-backend flutter-test run-flutter test-all run-cron run-field-ensure-worker run-dinosaur-wiki-sync run-dinosaur-llm-enrich run-fossil-pbdb-sync run-fossil-llm-enrich run-site-sync run-site-type-sync run-tool-sync run-dinosaur-image-generate run-fossil-image-generate run-site-type-image-generate run-tool-image-generate run-tool-image-generate-local sync-dinosaur-images sync-fossil-images sync-site-type-images sync-tool-images rename-site-type-images

help:
	@echo "Available targets:"
	@echo "  backend-install              Install backend Python dependencies"
	@echo "  backend-test                 Run backend pytest suite"
	@echo "  run-backend                  Start FastAPI dev server (reads backend/.env)"
	@echo "  run-cron                     Run due cron jobs on Railway"
	@echo "  run-field-ensure-worker      Run field ensure worker on Railway"
	@echo "  run-dinosaur-wiki-sync       dinosaur_wiki_sync on Railway"
	@echo "  run-dinosaur-llm-enrich      dinosaur_llm_enrich on Railway"
	@echo "  run-fossil-pbdb-sync         fossil_pbdb_sync on Railway"
	@echo "  run-fossil-llm-enrich        fossil_llm_enrich on Railway"
	@echo "  run-site-sync                site_sync on Railway"
	@echo "  run-site-type-sync           site_type_sync on Railway"
	@echo "  run-tool-sync                tool_sync on Railway"
	@echo "  run-dinosaur-image-generate  dinosaur_image_generate on Railway"
	@echo "  run-fossil-image-generate    fossil_image_generate on Railway"
	@echo "  run-site-type-image-generate site_type_image_generate on Railway"
	@echo "  run-tool-image-generate      tool_image_generate on Railway"
	@echo "  run-tool-image-generate-local tool_image_generate via backend/.env (faster for local PNGs)"
	@echo "  sync-dinosaur-images         Upload curated card images to Railway volume + DB"
	@echo "  sync-fossil-images           Upload curated fossil card images to Railway volume + DB"
	@echo "  sync-site-type-images        Upload curated site-type card images to Railway volume + DB"
	@echo "  sync-tool-images             Upload curated tool card images to Railway volume + DB"
	@echo "  rename-site-type-images      Rename legacy numeric site-type image files to period_rocktype"
	@echo "  flutter-test                 Run Flutter tests"
	@echo "  run-flutter                  Start Flutter app"
	@echo "  test-all                     Run backend and Flutter tests"
	@echo ""
	@echo "Cron jobs always run via Railway (never a local DB). Examples:"
	@echo "  make run-dinosaur-wiki-sync CRON_EXTRA='--overwrite'"
	@echo "  make run-dinosaur-wiki-sync CRON_EXTRA='--category \"Category:Feathered dinosaurs\"'"
	@echo "  make run-dinosaur-wiki-sync CRON_EXTRA='--dinos Tyrannosaurus Giganotosaurus'"
	@echo "  make run-dinosaur-llm-enrich CRON_EXTRA='--overwrite'"
	@echo "  make run-dinosaur-llm-enrich CRON_EXTRA='--dinos Tyrannosaurus --overwrite'"
	@echo "  make run-fossil-pbdb-sync CRON_EXTRA='--dinos Tyrannosaurus'"
	@echo "  make run-fossil-pbdb-sync CRON_EXTRA='--overwrite'"
	@echo "  make run-fossil-pbdb-sync CRON_EXTRA='--dinos Tyrannosaurus --overwrite'"
	@echo "  make run-fossil-llm-enrich CRON_EXTRA='--dinos Tyrannosaurus'"
	@echo "  make run-fossil-llm-enrich CRON_EXTRA='--overwrite'"
	@echo "  make run-dinosaur-image-generate CRON_EXTRA='--max-items 5'"
	@echo "  make run-dinosaur-image-generate CRON_EXTRA='--dinos Tyrannosaurus --dry-run'"
	@echo "  make run-fossil-image-generate CRON_EXTRA='--max-items 10'"
	@echo "  make run-site-type-image-generate CRON_EXTRA='--max-items 3 --dry-run'"
	@echo "  make run-site-type-image-generate CRON_EXTRA='--site-types 5 18 20'"

backend-install:
	cd backend && python3 -m pip install --upgrade pip && pip install -r requirements.txt -r requirements-dev.txt

backend-test:
	cd backend && pytest tests/ -v

run-backend:
	cd backend && uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# Cron jobs: railway run injects Railway DATABASE_URL and secrets.
run-cron:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner $(CRON_EXTRA)

run-field-ensure-worker:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.workers.field_ensure_worker

run-dinosaur-wiki-sync:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job dinosaur_wiki_sync $(CRON_EXTRA)

run-dinosaur-llm-enrich:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job dinosaur_llm_enrich $(CRON_EXTRA)

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

run-dinosaur-image-generate:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job dinosaur_image_generate $(CRON_EXTRA)

run-fossil-image-generate:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job fossil_image_generate $(CRON_EXTRA)

run-site-type-image-generate:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job site_type_image_generate $(CRON_EXTRA)

run-tool-image-generate:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job tool_image_generate $(CRON_EXTRA)

# Image generation locally: uses backend/.env (Railway DATABASE_URL + GOOGLE_GEMINI_API_KEY).
# Skips `railway run` startup overhead; still writes PNGs to repo tool-images/.
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

rename-site-type-images:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m scripts.rename_site_type_images $(CRON_EXTRA)

flutter-test:
	cd flutter && flutter test

run-flutter:
	cd flutter && flutter run

test-all: backend-test flutter-test
