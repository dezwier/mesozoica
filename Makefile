SHELL := /bin/bash

.PHONY: help backend-install backend-test run-backend flutter-test run-flutter test-all run-cron run-wikipedia-sync run-dinosaur-enrich

help:
	@echo "Available targets:"
	@echo "  backend-install     Install backend Python dependencies"
	@echo "  backend-test        Run backend pytest suite"
	@echo "  run-backend         Start FastAPI dev server"
	@echo "  run-cron            Run all due cron jobs"
	@echo "  run-wikipedia-sync  Run Wikipedia dinosaur sync once"
	@echo "  run-dinosaur-enrich Run dinosaur LLM enrichment once"
	@echo "  flutter-test        Run Flutter tests"
	@echo "  run-flutter         Start Flutter app"
	@echo "  test-all            Run backend and Flutter tests"

backend-install:
	cd backend && python3 -m pip install --upgrade pip && pip install -r requirements.txt -r requirements-dev.txt

backend-test:
	cd backend && pytest tests/ -v

run-backend:
	cd backend && uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

run-cron:
	cd backend && python -m app.crons.runner

run-wikipedia-sync:
	cd backend && python -m app.crons.runner --job wikipedia_dinosaur_sync

run-dinosaur-enrich:
	cd backend && python -m app.crons.runner --job dinosaur_llm_enrich

flutter-test:
	cd flutter && flutter test

run-flutter:
	cd flutter && flutter run

test-all: backend-test flutter-test
