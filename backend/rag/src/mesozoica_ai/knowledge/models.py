"""Validated document, synchronization, and retrieval contracts."""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


class RetrievalMode(str, Enum):
    """Supported deterministic Azure Search retrieval strategies."""

    KEYWORD = "keyword"
    VECTOR = "vector"
    HYBRID = "hybrid"
    SEMANTIC_HYBRID = "semantic_hybrid"


class SourceMetadata(BaseModel):
    """Common provenance with source-specific validated extras permitted."""

    model_config = ConfigDict(extra="allow")

    source: str = Field(min_length=1)
    source_id: str = Field(min_length=1)
    source_version: str | None = None
    title: str = Field(min_length=1)
    section: str | None = None
    section_path: list[str] = Field(default_factory=list)
    section_depth: int | None = Field(default=None, ge=0)
    section_ordinal: int | None = Field(default=None, ge=0)
    source_url: str | None = None
    published_at: datetime | None = None
    updated_at: datetime | None = None
    namespace: str | None = None
    subject_id: str | None = None

    @field_validator("published_at", "updated_at")
    @classmethod
    def require_timezone(cls, value: datetime | None) -> datetime | None:
        """Ensure persisted provenance timestamps have an unambiguous timezone."""
        if value is not None and value.tzinfo is None:
            raise ValueError("source timestamps must include a timezone")
        return value


class KnowledgeDocument(BaseModel):
    """One source-level unit, normally a Wikipedia section or paper abstract."""

    id: str = Field(min_length=1)
    text: str = Field(min_length=1)
    metadata: SourceMetadata


class KnowledgeChunk(BaseModel):
    """A deterministic token-bounded unit ready for embedding."""

    id: str
    document_id: str
    text: str
    embedding_text: str
    metadata: SourceMetadata
    chunk_index: int = Field(ge=0)
    start_index: int = Field(ge=0)
    embedding_hash: str
    document_hash: str
    pipeline_fingerprint: str


class EmbeddedChunk(KnowledgeChunk):
    """A chunk paired with its embedding vector."""

    embedding: list[float]


class RetrievedChunk(BaseModel):
    """Evidence returned by the search service before or after policy selection."""

    id: str
    document_id: str
    text: str
    metadata: SourceMetadata
    chunk_index: int = Field(default=0, ge=0)
    embedding_hash: str | None = None
    document_hash: str | None = None
    pipeline_fingerprint: str | None = None
    score: float
    reranker_score: float | None = None


class EvidencePolicy(BaseModel):
    """Deterministic evidence-quality guardrails applied after Azure ranking."""

    max_chunks_per_document: int = Field(default=2, ge=1, le=20)
    deduplicate_exact_content: bool = True
    minimum_chunks: int = Field(default=1, ge=1, le=100)
    minimum_reranker_score: float | None = Field(default=None, ge=0)


class RetrievalRequest(BaseModel):
    """A retrieval request with explicit ranking depth and evidence policy."""

    query: str = Field(min_length=1)
    mode: RetrievalMode = RetrievalMode.SEMANTIC_HYBRID
    filters: dict[str, Any] = Field(default_factory=dict)
    candidate_k: int = Field(default=50, ge=1, le=1000)
    fetch_k: int = Field(default=24, ge=1, le=100)
    top_k: int = Field(default=8, ge=1, le=100)
    evidence_policy: EvidencePolicy = Field(default_factory=EvidencePolicy)

    @model_validator(mode="after")
    def validate_depths(self) -> "RetrievalRequest":
        """Ensure candidate, fetch, selection, and policy depths are coherent."""
        if self.candidate_k < self.fetch_k:
            raise ValueError("candidate_k must be greater than or equal to fetch_k")
        if self.fetch_k < self.top_k:
            raise ValueError("fetch_k must be greater than or equal to top_k")
        if self.evidence_policy.minimum_chunks > self.top_k:
            raise ValueError("minimum_chunks must be smaller than or equal to top_k")
        if self.mode == RetrievalMode.SEMANTIC_HYBRID and self.candidate_k < 50:
            raise ValueError("semantic_hybrid requires candidate_k of at least 50")
        return self


class RejectionCounts(BaseModel):
    """Counts explaining why ranked Azure results were not selected."""

    duplicate_content: int = 0
    per_document_cap: int = 0
    below_threshold: int = 0


class RetrievalResult(BaseModel):
    """Selected evidence plus observable retrieval diagnostics."""

    chunks: list[RetrievedChunk]
    raw_result_count: int
    rejection_counts: RejectionCounts = Field(default_factory=RejectionCounts)
    mode: RetrievalMode
    duration_ms: float = Field(ge=0)
    pipeline_fingerprint: str


class ChunkState(BaseModel):
    """Minimal indexed state needed to classify an incremental synchronization."""

    embedding_hash: str | None = None
    document_hash: str | None = None
    pipeline_fingerprint: str | None = None


class SyncResult(BaseModel):
    """Outcome of a safe changed-only knowledge synchronization."""

    document_count: int
    chunk_count: int
    embedded_count: int
    metadata_updated_count: int
    skipped_count: int
    deleted_count: int
    chunk_ids: list[str]
    pipeline_fingerprint: str


class IngestResult(BaseModel):
    """Outcome of an unconditional ingestion."""

    document_count: int
    chunk_count: int
    chunk_ids: list[str]
    pipeline_fingerprint: str
