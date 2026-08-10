"""Small provider-neutral contracts for structured RAG generation."""

from __future__ import annotations

from typing import Any, Generic, TypeVar

from pydantic import BaseModel, Field, field_validator


class Evidence(BaseModel):
    """One retrieved evidence block supplied by application orchestration."""

    id: str = Field(min_length=1)
    document_id: str = Field(min_length=1)
    text: str = Field(min_length=1)
    source: str = Field(min_length=1)
    url: str | None = None


class CitedOutput(BaseModel):
    """Base class for generated outputs that must cite supplied evidence IDs."""

    source_chunk_ids: list[str] = Field(min_length=1)

    @field_validator("source_chunk_ids")
    @classmethod
    def validate_citation_ids(cls, values: list[str]) -> list[str]:
        """Require nonblank unique citation IDs."""
        cleaned = [value.strip() for value in values]
        if not all(cleaned):
            raise ValueError("citation chunk IDs must not be blank")
        if len(set(cleaned)) != len(cleaned):
            raise ValueError("citation chunk IDs must be unique")
        return cleaned


class PromptBudgetDiagnostics(BaseModel):
    """Exact token accounting for a rendered generation request."""

    max_prompt_tokens: int
    fixed_tokens: int
    system_tokens: int
    instructions_tokens: int
    query_tokens: int
    application_context_tokens: int
    output_schema_tokens: int
    evidence_tokens: int
    completion_allowance: int
    safety_margin: int
    unused_prompt_tokens: int
    included_evidence_ids: list[str]
    omitted_evidence_ids: list[str]


OutputT = TypeVar("OutputT", bound=BaseModel)


class RagResult(BaseModel, Generic[OutputT]):
    """Validated output with rendered evidence, usage, and prompt diagnostics."""

    output: OutputT
    rendered_evidence: str
    usage: dict[str, Any] = Field(default_factory=dict)
    prompt_budget: PromptBudgetDiagnostics
