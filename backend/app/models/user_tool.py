"""Append-only user–tool action log (owned, deployed, used, …)."""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, text
from sqlmodel import Field, SQLModel

USER_TOOL_ACTION_OWNED = "owned"
USER_TOOL_ACTION_DEPLOYED = "deployed"
USER_TOOL_ACTION_USED = "used"
USER_TOOL_ACTIONS = (
    USER_TOOL_ACTION_OWNED,
    USER_TOOL_ACTION_DEPLOYED,
    USER_TOOL_ACTION_USED,
)


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class UserTool(SQLModel, table=True):
    """One event linking a user to a tool instance."""

    __tablename__ = "user_tool"

    user_id: int = Field(
        sa_column=Column(
            Integer,
            ForeignKey("user.id", ondelete="CASCADE"),
            nullable=False,
            primary_key=True,
            index=True,
        ),
    )
    tool_id: int = Field(
        sa_column=Column(
            Integer,
            ForeignKey("tool.id", ondelete="CASCADE"),
            nullable=False,
            primary_key=True,
            index=True,
        ),
    )
    timestamp: datetime = Field(
        default_factory=_utc_now,
        sa_column=Column(
            DateTime(timezone=True),
            nullable=False,
            server_default=text("CURRENT_TIMESTAMP"),
            primary_key=True,
            index=True,
        ),
    )
    action: str = Field(
        default=USER_TOOL_ACTION_OWNED,
        sa_column=Column(String(32), nullable=False, index=True),
    )
