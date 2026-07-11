SHELL := /bin/bash

.PHONY: help backend-install backend-test run-backend flutter-test run-flutter test-all

help:
	@echo "Available targets:"
	@echo "  backend-install  Install backend Python dependencies"
	@echo "  backend-test     Run backend pytest suite"
	@echo "  run-backend      Start FastAPI dev server"
	@echo "  flutter-test     Run Flutter tests"
	@echo "  run-flutter      Start Flutter app"
	@echo "  test-all         Run backend and Flutter tests"

backend-install:
	cd backend && python3 -m pip install --upgrade pip && pip install -r requirements.txt -r requirements-dev.txt

backend-test:
	cd backend && pytest tests/ -v

run-backend:
	cd backend && uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

flutter-test:
	cd flutter && flutter test

run-flutter:
	cd flutter && flutter run

test-all: backend-test flutter-test
