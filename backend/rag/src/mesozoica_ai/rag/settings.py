"""Validated Azure OpenAI and prompt-budget settings."""

from pydantic import Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

from .errors import RagConfigurationError


class RagSettings(BaseSettings):
    """Configuration used only for structured generation."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    openai_endpoint: str = Field(validation_alias="AZURE_OPENAI_ENDPOINT")
    openai_api_key: SecretStr = Field(validation_alias="AZURE_OPENAI_API_KEY")
    chat_deployment: str = Field(validation_alias="AZURE_OPENAI_CHAT_DEPLOYMENT")
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

    @property
    def openai_v1_base_url(self) -> str:
        """Return the Azure OpenAI v1 base URL expected by LangChain."""
        endpoint = self.openai_endpoint.rstrip("/")
        return endpoint + "/" if endpoint.endswith("/openai/v1") else endpoint + "/openai/v1/"

    @field_validator("openai_endpoint")
    @classmethod
    def validate_endpoint(cls, value: str) -> str:
        """Require an absolute endpoint without embedded credentials."""
        normalized = value.rstrip("/")
        if not normalized.startswith(("https://", "http://")) or "@" in normalized:
            raise RagConfigurationError(
                "AZURE_OPENAI_ENDPOINT must be an absolute HTTP(S) URL without credentials"
            )
        return normalized

    @model_validator(mode="after")
    def validate_budget(self) -> "RagSettings":
        """Reject blank credentials and impossible prompt reservations."""
        if not self.openai_api_key.get_secret_value().strip():
            raise RagConfigurationError("AZURE_OPENAI_API_KEY must not be blank")
        if not self.chat_deployment.strip():
            raise RagConfigurationError("AZURE_OPENAI_CHAT_DEPLOYMENT must not be blank")
        if self.max_completion_tokens + self.prompt_safety_margin >= self.max_prompt_tokens:
            raise RagConfigurationError(
                "completion allowance plus safety margin must be smaller than the prompt budget"
            )
        return self
