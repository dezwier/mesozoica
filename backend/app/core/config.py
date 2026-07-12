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

    wikipedia_user_agent: str = Field(
        default="MesozoicaBot/1.0 (dev; contact@mesozoica.app)",
        validation_alias="WIKIPEDIA_USER_AGENT",
    )
    wikipedia_dinosaur_category: str = Field(
        default="Category:Dinosaur_genera",
        validation_alias="WIKIPEDIA_DINOSAUR_CATEGORY",
    )
    wikipedia_base_url: str = Field(
        default="https://en.wikipedia.org",
        validation_alias="WIKIPEDIA_BASE_URL",
    )
    wikipedia_request_delay_ms: int = Field(
        default=200,
        validation_alias="WIKIPEDIA_REQUEST_DELAY_MS",
    )
    wikipedia_sync_max_pages: int | None = Field(
        default=None,
        validation_alias="WIKIPEDIA_SYNC_MAX_PAGES",
    )
    wikipedia_sync_failure_threshold: float = Field(
        default=0.10,
        validation_alias="WIKIPEDIA_SYNC_FAILURE_THRESHOLD",
    )

    google_gemini_api_key: str = Field(default="", validation_alias="GOOGLE_GEMINI_API_KEY")
    gemini_model: str = Field(default="gemini-2.5-flash", validation_alias="GEMINI_MODEL")
    gemini_temperature: float = Field(default=0.0, validation_alias="GEMINI_TEMPERATURE")
    dinosaur_enrich_max_records: int | None = Field(
        default=None,
        validation_alias="DINOSAUR_ENRICH_MAX_RECORDS",
    )
    dinosaur_enrich_failure_threshold: float = Field(
        default=0.10,
        validation_alias="DINOSAUR_ENRICH_FAILURE_THRESHOLD",
    )
    dinosaur_enrich_request_delay_ms: int = Field(
        default=500,
        validation_alias="DINOSAUR_ENRICH_REQUEST_DELAY_MS",
    )

    dinosaur_images_dir: str = Field(
        default="../dinosaur-images",
        validation_alias="DINOSAUR_IMAGES_DIR",
    )
    curated_images_data_root: str = Field(
        default="",
        validation_alias="CURATED_IMAGES_DATA_ROOT",
    )
    public_base_url: str = Field(
        default="http://127.0.0.1:8000",
        validation_alias="PUBLIC_BASE_URL",
    )
    railway_dinosaur_images_volume: str = Field(
        default="dinosaur-images",
        validation_alias="RAILWAY_DINOSAUR_IMAGES_VOLUME",
    )
    dinosaur_image_sync_secret: str = Field(
        default="",
        validation_alias="DINOSAUR_IMAGE_SYNC_SECRET",
    )

    fossil_images_dir: str = Field(
        default="../fossil-images",
        validation_alias="FOSSIL_IMAGES_DIR",
    )
    railway_fossil_images_volume: str = Field(
        default="fossil-images",
        validation_alias="RAILWAY_FOSSIL_IMAGES_VOLUME",
    )
    fossil_image_sync_secret: str = Field(
        default="",
        validation_alias="FOSSIL_IMAGE_SYNC_SECRET",
    )

    @property
    def resolved_dinosaur_images_dir(self) -> Path:
        from app.services.curated_image_service.common import resolve_curated_storage_dir

        return resolve_curated_storage_dir(
            configured_dir=self.dinosaur_images_dir,
            default_relative="../dinosaur-images",
            data_root=self.curated_images_data_root,
            subdir_name="dinosaur-images",
        )

    @property
    def resolved_fossil_images_dir(self) -> Path:
        from app.services.curated_image_service.common import resolve_curated_storage_dir

        return resolve_curated_storage_dir(
            configured_dir=self.fossil_images_dir,
            default_relative="../fossil-images",
            data_root=self.curated_images_data_root,
            subdir_name="fossil-images",
        )

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

    @field_validator("wikipedia_sync_max_pages", mode="before")
    @classmethod
    def empty_max_pages_is_none(cls, value: Any) -> Any:
        if value in ("", None):
            return None
        return value

    @field_validator("dinosaur_enrich_max_records", mode="before")
    @classmethod
    def empty_enrich_max_records_is_none(cls, value: Any) -> Any:
        if value in ("", None):
            return None
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
    _ua = (os.getenv("WIKIPEDIA_USER_AGENT") or "").strip()
    if not _ua:
        raise ValueError(
            "WIKIPEDIA_USER_AGENT environment variable is required in production "
            "for Wikipedia cron jobs."
        )
else:
    if not os.getenv("SECRET_KEY"):
        _logger.warning(
            "SECRET_KEY is not set; a random key is used and tokens reset on restart."
        )
