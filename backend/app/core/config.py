from __future__ import annotations

import logging
import os
import sys
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
    wikipedia_feathered_dinosaur_category: str = Field(
        default="Category:Feathered dinosaurs",
        validation_alias="WIKIPEDIA_FEATHERED_DINOSAUR_CATEGORY",
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
    openalex_api_key: str = Field(default="", validation_alias="OPENALEX_API_KEY")
    openalex_max_works: int = Field(default=10, validation_alias="OPENALEX_MAX_WORKS")

    # OpenAI-compatible LLM (public OpenAI or Azure Foundry `/openai/v1`).
    # When OPENAI_* is blank, falls back to AZURE_OPENAI_* (already used by RAG).
    openai_api_key: str = Field(default="", validation_alias="OPENAI_API_KEY")
    openai_base_url: str = Field(default="", validation_alias="OPENAI_BASE_URL")
    openai_model: str = Field(default="gpt-5-mini", validation_alias="OPENAI_MODEL")
    openai_temperature: float = Field(default=0.0, validation_alias="OPENAI_TEMPERATURE")
    openai_image_model: str = Field(
        default="gpt-image-2.5-flare",
        validation_alias="OPENAI_IMAGE_MODEL",
    )
    openai_image_quality: str = Field(default="low", validation_alias="OPENAI_IMAGE_QUALITY")
    openai_image_size: str = Field(
        default="1024x1024",
        validation_alias="OPENAI_IMAGE_SIZE",
    )
    openai_image_max_article_chars: int = Field(
        default=1200,
        validation_alias="OPENAI_IMAGE_MAX_ARTICLE_CHARS",
    )
    openai_image_max_fossil_json_chars: int = Field(
        default=3500,
        validation_alias="OPENAI_IMAGE_MAX_FOSSIL_JSON_CHARS",
    )
    azure_openai_api_key: str = Field(default="", validation_alias="AZURE_OPENAI_API_KEY")
    azure_openai_endpoint: str = Field(default="", validation_alias="AZURE_OPENAI_ENDPOINT")
    azure_openai_chat_deployment: str = Field(
        default="",
        validation_alias="AZURE_OPENAI_CHAT_DEPLOYMENT",
    )

    # Legacy Gemini env names still accepted so old shells don't crash; unused.
    google_gemini_api_key: str = Field(default="", validation_alias="GOOGLE_GEMINI_API_KEY")
    gemini_model: str = Field(default="", validation_alias="GEMINI_MODEL")
    gemini_image_model: str = Field(default="", validation_alias="GEMINI_IMAGE_MODEL")
    gemini_temperature: float = Field(default=0.0, validation_alias="GEMINI_TEMPERATURE")
    gemini_image_max_article_chars: int = Field(
        default=1200,
        validation_alias="GEMINI_IMAGE_MAX_ARTICLE_CHARS",
    )
    gemini_image_max_fossil_json_chars: int = Field(
        default=3500,
        validation_alias="GEMINI_IMAGE_MAX_FOSSIL_JSON_CHARS",
    )
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
    fossil_enrich_max_records: int | None = Field(
        default=None,
        validation_alias="FOSSIL_ENRICH_MAX_RECORDS",
    )
    fossil_enrich_failure_threshold: float = Field(
        default=0.10,
        validation_alias="FOSSIL_ENRICH_FAILURE_THRESHOLD",
    )
    fossil_enrich_request_delay_ms: int = Field(
        default=500,
        validation_alias="FOSSIL_ENRICH_REQUEST_DELAY_MS",
    )

    dinosaur_images_dir: str = Field(
        default="../images/dinosaurs",
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
        default="images",
        validation_alias="RAILWAY_DINOSAUR_IMAGES_VOLUME",
    )
    dinosaur_image_sync_secret: str = Field(
        default="",
        validation_alias="DINOSAUR_IMAGE_SYNC_SECRET",
    )

    fossil_images_dir: str = Field(
        default="../images/fossils",
        validation_alias="FOSSIL_IMAGES_DIR",
    )
    railway_fossil_images_volume: str = Field(
        default="images",
        validation_alias="RAILWAY_FOSSIL_IMAGES_VOLUME",
    )
    fossil_image_sync_secret: str = Field(
        default="",
        validation_alias="FOSSIL_IMAGE_SYNC_SECRET",
    )

    site_type_images_dir: str = Field(
        default="../images/site-types",
        validation_alias="SITE_TYPE_IMAGES_DIR",
    )
    railway_site_type_images_volume: str = Field(
        default="images",
        validation_alias="RAILWAY_SITE_TYPE_IMAGES_VOLUME",
    )
    site_type_image_sync_secret: str = Field(
        default="",
        validation_alias="SITE_TYPE_IMAGE_SYNC_SECRET",
    )

    tool_images_dir: str = Field(
        default="../images/tools",
        validation_alias="TOOL_IMAGES_DIR",
    )
    railway_tool_images_volume: str = Field(
        default="images",
        validation_alias="RAILWAY_TOOL_IMAGES_VOLUME",
    )
    tool_image_sync_secret: str = Field(
        default="",
        validation_alias="TOOL_IMAGE_SYNC_SECRET",
    )

    access_token_expire_minutes: int = Field(
        default=60 * 24 * 7,
        validation_alias="ACCESS_TOKEN_EXPIRE_MINUTES",
    )
    algorithm: str = Field(default="HS256", validation_alias="JWT_ALGORITHM")
    user_images_dir: str = Field(
        default="../images/users",
        validation_alias="USER_IMAGES_DIR",
    )

    @property
    def resolved_user_images_dir(self) -> Path:
        from app.services.curated_image_service.common import resolve_curated_storage_dir

        return resolve_curated_storage_dir(
            configured_dir=self.user_images_dir,
            default_relative="../images/users",
            data_root=self.curated_images_data_root,
            subdir_name="images/users",
        )

    @property
    def resolved_site_type_images_dir(self) -> Path:
        from app.services.curated_image_service.common import resolve_curated_storage_dir

        return resolve_curated_storage_dir(
            configured_dir=self.site_type_images_dir,
            default_relative="../images/site-types",
            data_root=self.curated_images_data_root,
            subdir_name="images/site-types",
        )

    @property
    def resolved_dinosaur_images_dir(self) -> Path:
        from app.services.curated_image_service.common import resolve_curated_storage_dir

        return resolve_curated_storage_dir(
            configured_dir=self.dinosaur_images_dir,
            default_relative="../images/dinosaurs",
            data_root=self.curated_images_data_root,
            subdir_name="images/dinosaurs",
        )

    @property
    def resolved_fossil_images_dir(self) -> Path:
        from app.services.curated_image_service.common import resolve_curated_storage_dir

        return resolve_curated_storage_dir(
            configured_dir=self.fossil_images_dir,
            default_relative="../images/fossils",
            data_root=self.curated_images_data_root,
            subdir_name="images/fossils",
        )

    @property
    def resolved_tool_images_dir(self) -> Path:
        from app.services.curated_image_service.common import resolve_curated_storage_dir

        return resolve_curated_storage_dir(
            configured_dir=self.tool_images_dir,
            default_relative="../images/tools",
            data_root=self.curated_images_data_root,
            subdir_name="images/tools",
        )

    @property
    def cors_origins(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins_str.split(",") if origin.strip()]

    @property
    def is_production(self) -> bool:
        return self.environment.lower() in ("production", "prod")

    @property
    def resolved_openai_api_key(self) -> str:
        return self.openai_api_key.strip() or self.azure_openai_api_key.strip()

    @property
    def resolved_openai_base_url(self) -> str:
        raw = (
            self.openai_base_url.strip()
            or self.azure_openai_endpoint.strip()
            or "https://api.openai.com/v1"
        )
        raw = raw.rstrip("/")
        if raw.endswith("/openai/v1"):
            return raw
        if "openai.azure.com" in raw or "cognitiveservices.azure.com" in raw:
            return raw if raw.endswith("/openai/v1") else f"{raw}/openai/v1"
        return raw

    @property
    def resolved_openai_model(self) -> str:
        # Explicit OPENAI_MODEL wins; else Azure chat deployment; else field default.
        env_model = os.getenv("OPENAI_MODEL", "").strip()
        if env_model:
            return env_model
        chat = self.azure_openai_chat_deployment.strip()
        if chat:
            return chat
        return self.openai_model.strip() or "gpt-5-mini"

    @property
    def resolved_image_max_article_chars(self) -> int:
        return self.openai_image_max_article_chars or self.gemini_image_max_article_chars

    @property
    def resolved_image_max_fossil_json_chars(self) -> int:
        return (
            self.openai_image_max_fossil_json_chars
            or self.gemini_image_max_fossil_json_chars
        )

    @field_validator("database_url", mode="before")
    @classmethod
    def normalize_database_url(cls, value: Any) -> Any:
        # SQLAlchemy 2.1+ defaults postgresql:// to psycopg (v3). We ship
        # psycopg2-binary, so pin the dialect explicitly.
        if not isinstance(value, str) or not value:
            return value
        if value.startswith("postgres://"):
            value = "postgresql://" + value[len("postgres://") :]
        if value.startswith("postgresql+psycopg://"):
            return "postgresql+psycopg2://" + value[len("postgresql+psycopg://") :]
        if value.startswith("postgresql://"):
            return "postgresql+psycopg2://" + value[len("postgresql://") :]
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

    @field_validator("fossil_enrich_max_records", mode="before")
    @classmethod
    def empty_fossil_enrich_max_records_is_none(cls, value: Any) -> Any:
        if value in ("", None):
            return None
        return value


def _uses_minimal_settings() -> bool:
    """Background workers only need DATABASE_URL, not API/cron env validation."""
    if os.getenv("MESOZOICA_MINIMAL_SETTINGS", "").strip() == "1":
        return True
    return "field_ensure_worker" in " ".join(sys.argv)


settings = Settings()

if not settings.database_url:
    raise ValueError("DATABASE_URL environment variable is required")

_env = os.getenv("ENVIRONMENT", "production").strip().lower()
_is_production = _env not in ("development", "dev", "local")
_minimal_settings = _uses_minimal_settings()

if _is_production and not _minimal_settings:
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
