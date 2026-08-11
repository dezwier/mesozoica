"""Acquired knowledge document (one Wikipedia/OpenAlex section)."""

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


class DinosaurKnowledgeDoc(SQLModel, table=True):
    __tablename__ = "dinosaur_knowledge_doc"
    __table_args__ = (
        UniqueConstraint(
            "source_id",
            "document_id",
            name="uq_dinosaur_knowledge_doc_source_document",
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
    text: str = Field(sa_column=Column(Text, nullable=False))
    # Metadata.source — wikipedia/openalex (mirrors parent source usually).
    doc_source: str = Field(max_length=32, index=True)
    provenance_source_id: str = Field(max_length=255, index=True)
    title: str = Field(max_length=1024)
    section: str | None = Field(default=None, max_length=1024)
    section_path: list[str] = Field(
        default_factory=list, sa_column=Column(JSON, nullable=False)
    )
    section_depth: int | None = Field(default=None)
    section_ordinal: int | None = Field(default=None)
    source_url: str | None = Field(default=None, max_length=2048)
    published_at: datetime | None = Field(
        default=None, sa_column=Column(DateTime(timezone=True))
    )
    updated_at_source: datetime | None = Field(
        default=None, sa_column=Column(DateTime(timezone=True))
    )
    namespace: str | None = Field(default=None, max_length=64)
    subject_id: str | None = Field(default=None, max_length=64)
    extra_metadata: dict[str, Any] = Field(
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
