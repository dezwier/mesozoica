"""Ensure cron jobs only run against Railway Postgres, not a local database."""

from __future__ import annotations

import os

from app.core.config import settings


def require_railway_database() -> None:
    """
    Cron jobs must use the Railway Postgres database.

    Allowed when:
    - Running inside Railway (scheduled cron service), or
    - Invoked via `make run-*` / `railway run` (sets RAILWAY_RUN=1), or
    - ALLOW_LOCAL_CRON=1 (tests / emergency only)
    """
    if os.getenv("ALLOW_LOCAL_CRON", "").strip() == "1":
        return

    if os.getenv("RAILWAY_ENVIRONMENT") or os.getenv("RAILWAY_SERVICE_NAME"):
        _reject_local_database_url()
        return

    if os.getenv("RAILWAY_RUN", "").strip() == "1":
        _reject_local_database_url()
        return

    raise RuntimeError(
        "Cron jobs must run on Railway (not directly on your laptop). Use:\n"
        "  make run-wikipedia-sync\n"
        "  make run-dinosaur-enrich\n"
        "  make run-wikipedia-sync CRON_EXTRA='--overwrite'\n"
        "Or wait for the Railway cron service schedule."
    )


def _reject_local_database_url() -> None:
    url = (settings.database_url or "").lower()
    if not url:
        raise RuntimeError("DATABASE_URL is not set.")
    if "sqlite" in url:
        raise RuntimeError(
            "Cron jobs cannot use SQLite. Link Railway Postgres to this service."
        )
    if "localhost" in url or "127.0.0.1" in url:
        raise RuntimeError(
            "Cron jobs cannot use a local Postgres URL. Use Railway DATABASE_URL."
        )
