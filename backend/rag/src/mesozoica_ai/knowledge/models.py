from __future__ import annotations

from enum import Enum
from typing import Any, Generic, TypeVar

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


class SearchMode(str, Enum):
    KEYWORD = "keyword"
    VECTOR = "vector"
    HYBRID = "hybrid"
    SEMANTIC_HYBRID = "semantic_hybrid"


class SourceMetadata(BaseModel):
    """Validated common provenance fields with source-specific extensions allowed."""

    model_config = ConfigDict(extra="allow")

    source: str = Field(min_length=1)
    source_id: str = Field(min_length=1)
    source_version: str | None = None
    title: str = Field(min_length=1)
    section: str | None = None
    source_url: str | None = None
    published_at: str | None = None
    updated_at: str | None = None
    namespace: str | None = None
    subject_id: str | None = None


class KnowledgeDocument(BaseModel):
    id: str = Field(min_length=1)
    text: str = Field(min_length=1)
    metadata: dict[str, Any]

    @field_validator("metadata")
    @classmethod
    def validate_source_metadata(cls, value: dict[str, Any]) -> dict[str, Any]:
        return SourceMetadata.model_validate(value).model_dump(exclude_none=True)


class KnowledgeChunk(BaseModel):
    id: str
    document_id: str
    text: str
    embedding_text: str
    metadata: dict[str, Any] = Field(default_factory=dict)
    chunk_index: int = Field(ge=0)
    start_index: int = Field(ge=0)
    content_hash: str


class EmbeddedChunk(KnowledgeChunk):
    embedding: list[float]


class RetrievedChunk(BaseModel):
    id: str
    document_id: str
    text: str
    metadata: dict[str, Any] = Field(default_factory=dict)
    chunk_index: int = Field(default=0, ge=0)
    content_hash: str | None = None
    score: float
    reranker_score: float | None = None


class RetrievalRequest(BaseModel):
    query: str = Field(min_length=1)
    mode: SearchMode = SearchMode.SEMANTIC_HYBRID
    filters: dict[str, Any] = Field(default_factory=dict)
    top_k: int = Field(default=8, ge=1, le=100)
    candidate_k: int = Field(default=50, ge=1, le=1000)

    @model_validator(mode="after")
    def validate_candidate_count(self) -> RetrievalRequest:
        if self.candidate_k < self.top_k:
            raise ValueError("candidate_k must be greater than or equal to top_k")
        return self


class SyncResult(BaseModel):
    document_count: int
    chunk_count: int
    embedded_count: int
    skipped_count: int
    deleted_count: int
    chunk_ids: list[str]


class IngestResult(BaseModel):
    document_count: int
    chunk_count: int
    chunk_ids: list[str]


OutputT = TypeVar("OutputT", bound=BaseModel)


class RagResult(BaseModel, Generic[OutputT]):
    output: OutputT
    chunks: list[RetrievedChunk]
    usage: dict[str, Any] = Field(default_factory=dict)
    context: str
