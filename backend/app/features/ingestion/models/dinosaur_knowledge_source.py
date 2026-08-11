"""Job-tracking checkpoint for one dinosaur × knowledge source."""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, Text, UniqueConstraint, text
from sqlmodel import Field, SQLModel

KNOWLEDGE_STATUS_PENDING = "pending"
KNOWLEDGE_STATUS_RUNNING = "running"
KNOWLEDGE_STATUS_SUCCEEDED = "succeeded"
KNOWLEDGE_STATUS_FAILED = "failed"
KNOWLEDGE_STATUSES = (
    KNOWLEDGE_STATUS_PENDING,
    KNOWLEDGE_STATUS_RUNNING,
    KNOWLEDGE_STATUS_SUCCEEDED,
    KNOWLEDGE_STATUS_FAILED,
)


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class DinosaurKnowledgeSource(SQLModel, table=True):
    __tablename__ = "dinosaur_knowledge_source"
    __table_args__ = (
        UniqueConstraint(
            "subject_kind",
            "subject_id",
            "source",
            name="uq_dinosaur_knowledge_source_subject_source",
        ),
    )

    id: int | None = Field(default=None, primary_key=True)
    subject_kind: str = Field(index=True, max_length=32)
    subject_id: str = Field(index=True, max_length=64)
    subject_name: str = Field(index=True, max_length=255)
    source: str = Field(index=True, max_length=32)
    source_version: str | None = Field(default=None, max_length=255)
    source_hash: str | None = Field(default=None, max_length=64)
    content_hash: str | None = Field(default=None, max_length=64, index=True)
    embedded_hash: str | None = Field(default=None, max_length=64)
    embedded_pipeline_fingerprint: str | None = Field(default=None, max_length=64)
    indexed_hash: str | None = Field(default=None, max_length=64)
    indexed_pipeline_fingerprint: str | None = Field(default=None, max_length=64)
    acquisition_status: str = Field(
        default=KNOWLEDGE_STATUS_PENDING, index=True, max_length=16
    )
    embed_status: str = Field(
        default=KNOWLEDGE_STATUS_PENDING, index=True, max_length=16
    )
    index_status: str = Field(
        default=KNOWLEDGE_STATUS_PENDING, index=True, max_length=16
    )
    acquisition_attempts: int = Field(default=0)
    embed_attempts: int = Field(default=0)
    index_attempts: int = Field(default=0)
    acquisition_error: str | None = Field(default=None, sa_column=Column(Text))
    embed_error: str | None = Field(default=None, sa_column=Column(Text))
    index_error: str | None = Field(default=None, sa_column=Column(Text))
    acquisition_started_at: datetime | None = Field(
        default=None, sa_column=Column(DateTime(timezone=True))
    )
    acquisition_finished_at: datetime | None = Field(
        default=None, sa_column=Column(DateTime(timezone=True))
    )
    embed_started_at: datetime | None = Field(
        default=None, sa_column=Column(DateTime(timezone=True))
    )
    embed_finished_at: datetime | None = Field(
        default=None, sa_column=Column(DateTime(timezone=True))
    )
    index_started_at: datetime | None = Field(
        default=None, sa_column=Column(DateTime(timezone=True))
    )
    index_finished_at: datetime | None = Field(
        default=None, sa_column=Column(DateTime(timezone=True))
    )
    created_at: datetime = Field(
        default_factory=_utc_now,
        sa_column=Column(
            DateTime(timezone=True),
            nullable=False,
            server_default=text("CURRENT_TIMESTAMP"),
        ),
    )
    updated_at: datetime = Field(
        default_factory=_utc_now,
        sa_column=Column(
            DateTime(timezone=True),
            nullable=False,
            server_default=text("CURRENT_TIMESTAMP"),
        ),
    )


# Backward-compatible name used by a few call sites during the cutover.
DinosaurKnowledge = DinosaurKnowledgeSource
