"""Individual tool occurrences (instances of a catalog tool type). Owned by the tools feature."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from sqlalchemy import JSON, Column, DateTime, ForeignKey, Integer, text
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
    version: str = Field(
        default="Original",
        max_length=64,
        description="Curated image version folder name for this occurrence",
    )
    params_json: dict[str, Any] = Field(
        default_factory=dict,
        sa_column=Column(JSON, nullable=False),
    )
