"""Pytest fixtures for API tests."""

import os
import tempfile

if os.environ.get("USE_POSTGRES_FOR_TESTS", "") != "1":
    os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-pytest")
os.environ.setdefault("ENVIRONMENT", "development")
# Default the suite to the bundled YAML control board so tests stay independent
# of what happens to be seeded. The stored-config tests opt into "db" per test.
os.environ.setdefault("GAME_CONFIG_SOURCE", "yaml")

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
def _isolate_versioned_curated_image_dirs(tmp_path_factory, monkeypatch):
    """Keep API tests from resolving against the developer's real images/ tree."""
    root = tmp_path_factory.mktemp("curated-images")
    site_types = root / "site-types"
    tools = root / "tools"
    site_types.mkdir()
    tools.mkdir()
    monkeypatch.setattr(_config.settings, "site_type_images_dir", str(site_types))
    monkeypatch.setattr(_config.settings, "tool_images_dir", str(tools))
    monkeypatch.setattr(_config.settings, "curated_images_data_root", "")
    monkeypatch.setenv("SITE_TYPE_IMAGES_SOURCE_DIR", str(site_types))
    monkeypatch.setenv("TOOL_IMAGES_SOURCE_DIR", str(tools))


@pytest.fixture(autouse=True)
def _reset_db_between_tests():
    import app.models.models  # noqa: F401

    SQLModel.metadata.drop_all(engine)
    init_db()
    yield


@pytest.fixture(autouse=True)
def _reset_game_config_cache():
    """Drop the cached snapshot so config never leaks across tests."""
    from app.core.game_config_provider import invalidate_game_config_cache

    invalidate_game_config_cache()
    yield
    invalidate_game_config_cache()


@pytest.fixture
def client():
    return TestClient(app)


@pytest.fixture
def session():
    with Session(engine) as db_session:
        yield db_session
