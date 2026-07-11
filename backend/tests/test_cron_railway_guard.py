"""Tests for Railway-only cron guard."""

import os

import pytest

from app.crons.railway_guard import require_railway_database


def test_blocks_plain_local_invocation(monkeypatch):
    monkeypatch.delenv("ALLOW_LOCAL_CRON", raising=False)
    monkeypatch.delenv("RAILWAY_RUN", raising=False)
    monkeypatch.delenv("RAILWAY_ENVIRONMENT", raising=False)
    monkeypatch.delenv("RAILWAY_SERVICE_NAME", raising=False)

    with pytest.raises(RuntimeError, match="must run on Railway"):
        require_railway_database()


def test_allows_railway_run_wrapper(monkeypatch):
    monkeypatch.setenv("RAILWAY_RUN", "1")
    monkeypatch.delenv("RAILWAY_ENVIRONMENT", raising=False)
    monkeypatch.setenv(
        "DATABASE_URL",
        "postgresql://user:pass@hayabusa.proxy.rlwy.net:5432/railway",
    )
    import app.core.config as config

    monkeypatch.setattr(
        config.settings,
        "database_url",
        "postgresql://user:pass@hayabusa.proxy.rlwy.net:5432/railway",
    )
    require_railway_database()


def test_allows_railway_platform(monkeypatch):
    monkeypatch.setenv("RAILWAY_ENVIRONMENT", "production")
    monkeypatch.setenv(
        "DATABASE_URL",
        "postgresql://user:pass@postgres.railway.internal:5432/railway",
    )
    import app.core.config as config

    monkeypatch.setattr(
        config.settings,
        "database_url",
        "postgresql://user:pass@postgres.railway.internal:5432/railway",
    )
    require_railway_database()
