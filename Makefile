SHELL := /bin/bash

# Railway service that has DATABASE_URL + cron env vars linked.
RAILWAY_SERVICE ?= backend
CRON_EXTRA ?=

.PHONY: help backend-install backend-test run-backend flutter-test run-flutter test-all run-cron run-wikipedia-sync run-dinosaur-enrich

help:
	@echo "Available targets:"
	@echo "  backend-install     Install backend Python dependencies"
	@echo "  backend-test        Run backend pytest suite"
	@echo "  run-backend         Start FastAPI dev server (reads backend/.env)"
	@echo "  run-cron            Run due cron jobs on Railway"
	@echo "  run-wikipedia-sync  Wikipedia dinosaur sync on Railway"
	@echo "  run-dinosaur-enrich LLM dinosaur enrichment on Railway"
	@echo "  flutter-test        Run Flutter tests"
	@echo "  run-flutter         Start Flutter app"
	@echo "  test-all            Run backend and Flutter tests"
	@echo ""
	@echo "Cron jobs always run via Railway (never a local DB). Examples:"
	@echo "  make run-wikipedia-sync CRON_EXTRA='--overwrite'"
	@echo "  make run-dinosaur-enrich CRON_EXTRA='--overwrite'"

backend-install:
	cd backend && python3 -m pip install --upgrade pip && pip install -r requirements.txt -r requirements-dev.txt

backend-test:
	cd backend && pytest tests/ -v

run-backend:
	cd backend && uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# Cron jobs: railway run injects Railway DATABASE_URL and secrets.
run-cron:
	cd backend && RAILWAY_RUN=1 railway run --service $(RAILWAY_SERVICE) python -m app.crons.runner $(CRON_EXTRA)

run-wikipedia-sync:
	cd backend && RAILWAY_RUN=1 railway run --service $(RAILWAY_SERVICE) python -m app.crons.runner --job wikipedia_dinosaur_sync $(CRON_EXTRA)

run-dinosaur-enrich:
	cd backend && RAILWAY_RUN=1 railway run --service $(RAILWAY_SERVICE) python -m app.crons.runner --job dinosaur_llm_enrich $(CRON_EXTRA)

flutter-test:
	cd flutter && flutter test

run-flutter:
	cd flutter && flutter run

test-all: backend-test flutter-test
