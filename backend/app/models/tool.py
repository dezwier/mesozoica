"""Individual tool occurrences (instances of a catalog tool type)."""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, ForeignKey, Integer, text
from sqlmodel import Field, SQLModel


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class Tool(SQLModel, table=True):
    """One owned/spawned occurrence of a tool type."""

    __tablename__ = "tool"

    id: int | None = Field(default=None, primary_key=True)
    tool_type_id: int = Field(
        sa_column=Column(
            Integer,
            ForeignKey("tool_type.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
    )
    spawn_date: datetime = Field(
        default_factory=_utc_now,
        sa_column=Column(
            DateTime(timezone=True),
            nullable=False,
            server_default=text("CURRENT_TIMESTAMP"),
            index=True,
        ),
    )
    level: int = Field(default=1, ge=1)
