"""Pytest fixtures for API tests."""

import os
import tempfile

if os.environ.get("USE_POSTGRES_FOR_TESTS", "") != "1":
    os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-pytest")
os.environ.setdefault("ENVIRONMENT", "development")

import app.core.config as _config  # noqa: E402

if os.environ.get("USE_POSTGRES_FOR_TESTS", "") == "1":
    pg_url = os.environ.get("DATABASE_URL", "")
    if not pg_url:
        raise RuntimeError("USE_POSTGRES_FOR_TESTS requires DATABASE_URL")
    _config.settings.database_url = pg_url.replace("postgres://", "postgresql://", 1)
else:
    _test_db = os.path.join(tempfile.gettempdir(), "mesozoica_test.db")
    if os.path.exists(_test_db):
        try:
            os.remove(_test_db)
        except OSError:
            pass
    _config.settings.database_url = f"sqlite:///{_test_db}"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlmodel import SQLModel, Session  # noqa: E402

from app.core.database import engine, init_db  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture(autouse=True)
def _reset_db_between_tests():
    import app.models.models  # noqa: F401

    SQLModel.metadata.drop_all(engine)
    init_db()
    yield


@pytest.fixture
def client():
    return TestClient(app)


@pytest.fixture
def session():
    with Session(engine) as db_session:
        yield db_session
