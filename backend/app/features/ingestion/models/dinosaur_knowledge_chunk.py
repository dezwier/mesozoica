"""Embedded knowledge chunk (text + vector) for one source snapshot."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from sqlalchemy import (
    Column,
    DateTime,
    ForeignKey,
    JSON,
    Text,
    UniqueConstraint,
    text as sa_text,
)
from sqlmodel import Field, SQLModel


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class DinosaurKnowledgeChunk(SQLModel, table=True):
    __tablename__ = "dinosaur_knowledge_chunk"
    __table_args__ = (
        UniqueConstraint(
            "source_id",
            "chunk_id",
            name="uq_dinosaur_knowledge_chunk_source_chunk",
        ),
    )

    id: int | None = Field(default=None, primary_key=True)
    source_id: int = Field(
        sa_column=Column(
            ForeignKey("dinosaur_knowledge_source.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        )
    )
    document_id: str = Field(index=True, max_length=512)
    chunk_id: str = Field(index=True, max_length=512)
    chunk_index: int = Field(default=0, ge=0)
    start_index: int = Field(default=0, ge=0)
    text: str = Field(sa_column=Column(Text, nullable=False))
    embedding_text: str = Field(sa_column=Column(Text, nullable=False))
    embedding: list[float] = Field(
        default_factory=list, sa_column=Column(JSON, nullable=False)
    )
    embedding_hash: str = Field(max_length=64, index=True)
    document_hash: str = Field(max_length=64)
    pipeline_fingerprint: str = Field(max_length=64, index=True)
    metadata_json: dict[str, Any] = Field(
        default_factory=dict, sa_column=Column(JSON, nullable=False)
    )
    created_at: datetime = Field(
        default_factory=_utc_now,
        sa_column=Column(
            DateTime(timezone=True),
            nullable=False,
            server_default=sa_text("CURRENT_TIMESTAMP"),
        ),
    )
    updated_at: datetime = Field(
        default_factory=_utc_now,
        sa_column=Column(
            DateTime(timezone=True),
            nullable=False,
            server_default=sa_text("CURRENT_TIMESTAMP"),
        ),
    )
