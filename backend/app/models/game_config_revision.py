"""Immutable snapshot of the whole game config control board."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Optional

from sqlalchemy import Column, DateTime, ForeignKey, Integer, JSON, Text, text
from sqlmodel import Field, SQLModel


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class GameConfigRevision(SQLModel, table=True):
    """One complete, validated set of control board documents.

    Snapshots rather than per-document rows: gameplay math spans documents
    (``tool_actions`` modifies ``site_discovery`` params), so a partial write
    could publish an internally inconsistent config. Rows are append-only —
    rollback writes a new revision holding the old content, so ``version``
    only ever increases.
    """

    __tablename__ = "game_config_revision"

    id: Optional[int] = Field(default=None, primary_key=True)
    version: int = Field(sa_column=Column(Integer, nullable=False, unique=True, index=True))
    documents: dict[str, Any] = Field(
        default_factory=dict, sa_column=Column(JSON, nullable=False)
    )
    checksum: str = Field(max_length=64, index=True)
    source: str = Field(default="admin", max_length=16)
    note: str = Field(default="", sa_column=Column(Text, nullable=False, server_default=""))
    created_at: datetime = Field(
        default_factory=_utc_now,
        sa_column=Column(
            DateTime(timezone=True),
            nullable=False,
            server_default=text("CURRENT_TIMESTAMP"),
            index=True,
        ),
    )
    created_by_user_id: Optional[int] = Field(
        default=None,
        sa_column=Column(
            Integer, ForeignKey("user.id", ondelete="SET NULL"), nullable=True
        ),
    )
