from __future__ import annotations

from pydantic import Field, SecretStr, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class KnowledgeSettings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    openai_endpoint: str = Field(
        min_length=1, validation_alias="AZURE_OPENAI_ENDPOINT"
    )
    openai_api_key: SecretStr = Field(validation_alias="AZURE_OPENAI_API_KEY")
    embedding_model: str = Field(
        min_length=1, validation_alias="AZURE_OPENAI_EMBEDDING_DEPLOYMENT"
    )
    chat_model: str = Field(default="", validation_alias="AZURE_OPENAI_CHAT_DEPLOYMENT")
    embedding_dimensions: int = Field(
        default=1536, gt=0, validation_alias="AZURE_OPENAI_EMBEDDING_DIMENSIONS"
    )
    search_endpoint: str = Field(min_length=1, validation_alias="AZURE_SEARCH_ENDPOINT")
    search_api_key: SecretStr = Field(validation_alias="AZURE_SEARCH_API_KEY")
    search_index: str = Field(min_length=1, validation_alias="AZURE_SEARCH_INDEX")
    semantic_configuration_name: str = Field(
        default="knowledge-semantic", validation_alias="RAG_SEMANTIC_CONFIGURATION"
    )
    chunk_size: int = Field(default=500, gt=0, validation_alias="RAG_CHUNK_SIZE")
    chunk_overlap: int = Field(default=75, ge=0, validation_alias="RAG_CHUNK_OVERLAP")
    context_token_budget: int = Field(
        default=6000, gt=0, validation_alias="RAG_CONTEXT_TOKEN_BUDGET"
    )

    @model_validator(mode="after")
    def validate_chunking(self) -> KnowledgeSettings:
        if self.chunk_overlap >= self.chunk_size:
            raise ValueError("RAG_CHUNK_OVERLAP must be smaller than RAG_CHUNK_SIZE")
        return self
