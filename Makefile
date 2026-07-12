SHELL := /bin/bash

# Optional override: make run-wikipedia-sync RAILWAY_SERVICE=my-service
# Default: uses the service from `cd backend && railway link`
RAILWAY_SERVICE ?=
RAILWAY_SERVICE_FLAG = $(if $(RAILWAY_SERVICE),--service $(RAILWAY_SERVICE),)
CRON_EXTRA ?=

.PHONY: help backend-install backend-test run-backend flutter-test run-flutter test-all run-cron run-wikipedia-sync run-dinosaur-enrich run-fossil-sync sync-dinosaur-images sync-fossil-images

help:
	@echo "Available targets:"
	@echo "  backend-install     Install backend Python dependencies"
	@echo "  backend-test        Run backend pytest suite"
	@echo "  run-backend         Start FastAPI dev server (reads backend/.env)"
	@echo "  run-cron            Run due cron jobs on Railway"
	@echo "  run-wikipedia-sync  Wikipedia dinosaur sync on Railway"
	@echo "  run-dinosaur-enrich LLM dinosaur enrichment on Railway"
	@echo "  run-fossil-sync       PBDB fossil occurrence sync on Railway"
	@echo "  sync-dinosaur-images Upload curated card images to Railway volume + DB"
	@echo "  sync-fossil-images   Upload curated fossil card images to Railway volume + DB"
	@echo "  flutter-test        Run Flutter tests"
	@echo "  run-flutter         Start Flutter app"
	@echo "  test-all            Run backend and Flutter tests"
	@echo ""
	@echo "Cron jobs always run via Railway (never a local DB). Examples:"
	@echo "  make run-wikipedia-sync CRON_EXTRA='--overwrite'"
	@echo "  make run-wikipedia-sync CRON_EXTRA='--dinos Tyrannosaurus Giganotosaurus'"
	@echo "  make run-dinosaur-enrich CRON_EXTRA='--overwrite'"
	@echo "  make run-dinosaur-enrich CRON_EXTRA='--dinos Tyrannosaurus --overwrite'"
	@echo "  make run-fossil-sync CRON_EXTRA='--dinos Tyrannosaurus'"
	@echo "  make run-fossil-sync CRON_EXTRA='--overwrite'"
	@echo "  make run-fossil-sync CRON_EXTRA='--dinos Tyrannosaurus --overwrite'"

backend-install:
	cd backend && python3 -m pip install --upgrade pip && pip install -r requirements.txt -r requirements-dev.txt

backend-test:
	cd backend && pytest tests/ -v

run-backend:
	cd backend && uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# Cron jobs: railway run injects Railway DATABASE_URL and secrets.
run-cron:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner $(CRON_EXTRA)

run-wikipedia-sync:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job wikipedia_dinosaur_sync $(CRON_EXTRA)

run-dinosaur-enrich:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job dinosaur_llm_enrich $(CRON_EXTRA)

run-fossil-sync:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m app.crons.runner --job pbdb_fossil_sync $(CRON_EXTRA)

sync-dinosaur-images:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m scripts.sync_dinosaur_images $(CRON_EXTRA)

sync-fossil-images:
	cd backend && RAILWAY_RUN=1 railway run $(RAILWAY_SERVICE_FLAG) python -m scripts.sync_fossil_images $(CRON_EXTRA)

flutter-test:
	cd flutter && flutter test

run-flutter:
	cd flutter && flutter run

test-all: backend-test flutter-test
