from typing import Any

from pydantic import BaseModel, Field


class KnowledgeDocument(BaseModel):
    id: str
    text: str
    metadata: dict[str, Any] = Field(default_factory=dict)


class KnowledgeChunk(KnowledgeDocument):
    content_hash: str | None = None

class EmbeddedChunk(KnowledgeChunk):
    embedding: list[float]


class RetrievedChunk(KnowledgeChunk):
    score: float


class IngestResult(BaseModel):
    document_count: int
    chunk_count: int
    chunk_ids: list[str]

class SyncResult(BaseModel):
    document_count: int
    chunk_count: int

    embedded_count: int
    skipped_count: int
    deleted_count: int

    chunk_ids: list[str]    