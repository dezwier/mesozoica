"""Individual dinosaur occurrences (e.g. future reconstructions)."""

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
    created_at: datetime = Field(
        default_factory=_utc_now,
        sa_column=Column(
            DateTime(timezone=True),
            nullable=False,
            server_default=text("CURRENT_TIMESTAMP"),
            index=True,
        ),
    )
