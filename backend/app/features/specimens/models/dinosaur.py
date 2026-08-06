"""Individual dinosaur occurrences (e.g. future reconstructions). Owned by the specimens feature."""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, ForeignKey, Integer, text
from sqlmodel import Field, SQLModel


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class Dinosaur(SQLModel, table=True):
    """One owned/reconstructed occurrence of a dinosaur type."""

    __tablename__ = "dinosaur"

    id: int | None = Field(default=None, primary_key=True)
    dinosaur_type_id: int = Field(
        sa_column=Column(
            Integer,
            ForeignKey("dinosaur_type.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
    )
    dinosaur_type_revision_id: int | None = Field(
        default=None,
        sa_column=Column(
            Integer,
            ForeignKey("dinosaur_type_revision.id", ondelete="SET NULL"),
            nullable=True,
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
    version: str = Field(
        default="Original",
        max_length=64,
        description="Curated image version folder name for this occurrence",
    )
