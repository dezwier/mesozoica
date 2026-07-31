"""Immutable Wikipedia + LLM content snapshot for a dinosaur genus."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Optional

from sqlalchemy import Column, DateTime, ForeignKey, Integer, JSON, Text, UniqueConstraint, text
from sqlmodel import Field, SQLModel


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class DinosaurTypeRevision(SQLModel, table=True):
    """One Wikipedia-era content revision for a dinosaur_type."""

    __tablename__ = "dinosaur_type_revision"
    __table_args__ = (
        UniqueConstraint(
            "dinosaur_type_id",
            "content_hash",
            name="uq_dinosaur_type_revision_type_hash",
        ),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    dinosaur_type_id: int = Field(
        sa_column=Column(
            Integer,
            ForeignKey("dinosaur_type.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
    )
    created_at: datetime = Field(
        default_factory=_utc_now,
        sa_column=Column(
            DateTime(timezone=True),
            nullable=False,
            server_default=text("CURRENT_TIMESTAMP"),
            index=True,
        ),
    )
    wikipedia_revision_id: Optional[int] = Field(default=None, index=True)
    article_date: Optional[datetime] = Field(
        default=None,
        sa_column=Column(DateTime(timezone=True), nullable=True),
    )
    content_hash: str = Field(max_length=64, index=True)

    birth: Optional[float] = Field(default=None, description="Earliest appearance in Ma")
    death: Optional[float] = Field(default=None, description="Latest extinction in Ma")
    period: Optional[str] = Field(default=None, max_length=255)
    cladogram: dict[str, Any] = Field(
        default_factory=dict, sa_column=Column(JSON, nullable=False)
    )
    diet_type: Optional[str] = Field(default=None, max_length=64)
    long_description: Optional[str] = Field(default=None, sa_column=Column(Text))
    article: Optional[str] = Field(default=None, sa_column=Column(Text))

    length: Optional[str] = Field(default=None, max_length=128)
    mass: Optional[str] = Field(default=None, max_length=128)
    location: Optional[str] = Field(default=None, max_length=512)
    short_description: Optional[str] = Field(default=None, sa_column=Column(Text))
    llm_enriched: bool = Field(default=False, index=True)
