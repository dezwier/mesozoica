"""User–tool ownership (collection level on the catalog card)."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import Column, DateTime, ForeignKey, Integer, UniqueConstraint, text
from sqlmodel import Field, SQLModel


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class UserTool(SQLModel, table=True):
    """Links a user to a tool card with a collection level."""

    __tablename__ = "user_tool"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "tool_id",
            name="uq_user_tool_user_tool",
        ),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(
        sa_column=Column(
            Integer,
            ForeignKey("user.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
    )
    tool_id: int = Field(
        sa_column=Column(
            Integer,
            ForeignKey("tool.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
    )
    level: int = Field(default=1, ge=1)
    timestamp: datetime = Field(
        default_factory=_utc_now,
        sa_column=Column(
            DateTime(timezone=True),
            nullable=False,
            server_default=text("CURRENT_TIMESTAMP"),
            index=True,
        ),
    )
