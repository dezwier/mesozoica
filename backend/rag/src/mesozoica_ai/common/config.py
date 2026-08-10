"""Unified configuration for retrieve, index, and generate."""

from __future__ import annotations

from pydantic import Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

from .errors import ConfigurationError


class AiConfig(BaseSettings):
    """Single settings object for embeddings, Azure Search, and chat generation.

    Search deliberately uses separate credentials: an admin key for schema/write
    operations and a query key for least-privileged retrieval.
    """

    model_config = SettingsConfigDict(
        env_file=".env", extra="ignore", populate_by_name=True
    )

    openai_endpoint: str = Field(min_length=1, validation_alias="AZURE_OPENAI_ENDPOINT")
    openai_api_key: SecretStr = Field(validation_alias="AZURE_OPENAI_API_KEY")
    embedding_deployment: str = Field(
        min_length=1, validation_alias="AZURE_OPENAI_EMBEDDING_DEPLOYMENT"
    )
    embedding_dimensions: int = Field(
        default=1536, gt=0, validation_alias="AZURE_OPENAI_EMBEDDING_DIMENSIONS"
    )
    embedding_encoding: str = Field(
        default="cl100k_base", validation_alias="RAG_EMBEDDING_ENCODING"
    )
    chat_deployment: str = Field(
        default="", validation_alias="AZURE_OPENAI_CHAT_DEPLOYMENT"
    )
    chat_encoding: str = Field(default="o200k_base", validation_alias="RAG_CHAT_ENCODING")
    max_prompt_tokens: int = Field(
        default=16_000, gt=0, validation_alias="RAG_MAX_PROMPT_TOKENS"
    )
    max_completion_tokens: int = Field(
        default=1_000, gt=0, validation_alias="RAG_MAX_COMPLETION_TOKENS"
    )
    prompt_safety_margin: int = Field(
        default=512, ge=0, validation_alias="RAG_PROMPT_SAFETY_MARGIN"
    )

    search_endpoint: str = Field(min_length=1, validation_alias="AZURE_SEARCH_ENDPOINT")
    search_admin_key: SecretStr | None = Field(
        default=None, validation_alias="AZURE_SEARCH_ADMIN_KEY"
    )
    search_query_key: SecretStr = Field(validation_alias="AZURE_SEARCH_QUERY_KEY")
    search_index: str = Field(min_length=1, validation_alias="AZURE_SEARCH_INDEX")
    semantic_configuration_name: str = Field(
        default="knowledge-semantic", validation_alias="RAG_SEMANTIC_CONFIGURATION"
    )

    chunk_size: int = Field(default=500, gt=0, validation_alias="RAG_CHUNK_SIZE")
    chunk_overlap: int = Field(default=75, ge=0, validation_alias="RAG_CHUNK_OVERLAP")
    candidate_k: int = Field(default=50, ge=50, le=1000, validation_alias="RAG_CANDIDATE_K")
    fetch_k: int = Field(default=24, ge=1, le=100, validation_alias="RAG_FETCH_K")
    top_k: int = Field(default=8, ge=1, le=100, validation_alias="RAG_TOP_K")

    embedding_batch_size: int = Field(
        default=64, ge=1, le=2048, validation_alias="RAG_EMBEDDING_BATCH_SIZE"
    )
    write_batch_size: int = Field(
        default=250, ge=1, le=1000, validation_alias="RAG_WRITE_BATCH_SIZE"
    )
    write_batch_bytes: int = Field(
        default=8_000_000, ge=100_000, validation_alias="RAG_WRITE_BATCH_BYTES"
    )
    write_attempts: int = Field(default=4, ge=1, le=10, validation_alias="RAG_WRITE_ATTEMPTS")

    @property
    def openai_v1_base_url(self) -> str:
        """Return the Azure OpenAI v1 base URL expected by LangChain clients."""
        endpoint = self.openai_endpoint.rstrip("/")
        return endpoint + "/" if endpoint.endswith("/openai/v1") else endpoint + "/openai/v1/"

    @field_validator("openai_endpoint", "search_endpoint")
    @classmethod
    def validate_https_endpoint(cls, value: str) -> str:
        """Require explicit HTTP(S) provider endpoints without embedded credentials."""
        normalized = value.rstrip("/")
        if not normalized.startswith(("https://", "http://")) or "@" in normalized:
            raise ConfigurationError(
                "Azure endpoints must be absolute HTTP(S) URLs without credentials"
            )
        return normalized

    @model_validator(mode="after")
    def validate_pipeline(self) -> AiConfig:
        """Reject cross-field combinations that would fail later and less clearly."""
        problems: list[str] = []
        if not self.openai_api_key.get_secret_value().strip():
            problems.append("AZURE_OPENAI_API_KEY must not be blank")
        if not self.search_query_key.get_secret_value().strip():
            problems.append("AZURE_SEARCH_QUERY_KEY must not be blank")
        if (
            self.search_admin_key is not None
            and not self.search_admin_key.get_secret_value().strip()
        ):
            problems.append("AZURE_SEARCH_ADMIN_KEY must be omitted or nonblank")
        if self.chunk_overlap >= self.chunk_size:
            problems.append("RAG_CHUNK_OVERLAP must be smaller than RAG_CHUNK_SIZE")
        if self.fetch_k < self.top_k:
            problems.append("RAG_FETCH_K must be greater than or equal to RAG_TOP_K")
        if self.candidate_k < self.fetch_k:
            problems.append("RAG_CANDIDATE_K must be greater than or equal to RAG_FETCH_K")
        if self.chat_deployment.strip() and (
            self.max_completion_tokens + self.prompt_safety_margin >= self.max_prompt_tokens
        ):
            problems.append(
                "completion allowance plus safety margin must be smaller than the prompt budget"
            )
        if problems:
            raise ConfigurationError("; ".join(problems))
        return self
