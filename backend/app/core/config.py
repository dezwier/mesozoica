from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import Any

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

_logger = logging.getLogger(__name__)

try:
    from dotenv import load_dotenv

    _backend_dir = Path(__file__).parent.parent.parent
    _env_path = _backend_dir / ".env"
    if _env_path.exists():
        load_dotenv(_env_path, override=True)
except ImportError:
    _logger.warning("python-dotenv not installed")
except Exception as exc:  # pragma: no cover
    _logger.warning("Error loading .env file: %s", exc)


def _generate_secret_key() -> str:
    return os.urandom(32).hex()


class Settings(BaseSettings):
    """Application settings loaded from environment variables and `.env`."""

    model_config = SettingsConfigDict(
        env_file=".env",
        case_sensitive=False,
        extra="ignore",
    )

    database_url: str = ""
    secret_key: str = Field(default_factory=_generate_secret_key)
    environment: str = Field(default="development", validation_alias="ENVIRONMENT")
    api_v1_prefix: str = "/api/v1"
    cors_origins_str: str = Field(default="*", validation_alias="CORS_ORIGINS")
    debug: bool = False

    @property
    def cors_origins(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins_str.split(",") if origin.strip()]

    @property
    def is_production(self) -> bool:
        return self.environment.lower() in ("production", "prod")

    @field_validator("database_url", mode="before")
    @classmethod
    def normalize_database_url(cls, value: Any) -> Any:
        if isinstance(value, str) and value.startswith("postgres://"):
            return value.replace("postgres://", "postgresql://", 1)
        return value


settings = Settings()

if not settings.database_url:
    raise ValueError("DATABASE_URL environment variable is required")

_env = os.getenv("ENVIRONMENT", "production").strip().lower()
_is_production = _env not in ("development", "dev", "local")

if _is_production:
    if not (os.getenv("SECRET_KEY") or "").strip():
        raise ValueError(
            "SECRET_KEY environment variable is required in production. "
            "Set SECRET_KEY in your Railway service variables."
        )
    _cors = (os.getenv("CORS_ORIGINS") or "").strip()
    if not _cors or _cors == "*":
        raise ValueError(
            "CORS_ORIGINS must be set to explicit origins in production. "
            "Cannot use '*' when credentials are allowed."
        )
else:
    if not os.getenv("SECRET_KEY"):
        _logger.warning(
            "SECRET_KEY is not set; a random key is used and tokens reset on restart."
        )
