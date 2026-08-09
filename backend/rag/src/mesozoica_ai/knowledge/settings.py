from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class KnowledgeSettings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        extra="ignore",
    )

    openai_endpoint: str = Field(
        validation_alias="AZURE_OPENAI_ENDPOINT"
    )

    openai_api_key: SecretStr = Field(
        validation_alias="AZURE_OPENAI_API_KEY"
    )

    embedding_model: str = Field(
        validation_alias="AZURE_OPENAI_EMBEDDING_DEPLOYMENT"
    )

    search_endpoint: str = Field(
        validation_alias="AZURE_SEARCH_ENDPOINT"
    )

    search_api_key: SecretStr = Field(
        validation_alias="AZURE_SEARCH_API_KEY"
    )

    search_index: str = "dinosaur-knowledge"

    chunk_size: int = 1000
    chunk_overlap: int = 150