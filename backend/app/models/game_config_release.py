"""Singleton pointer to the currently active game config revision."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import (
    CheckConstraint,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    text,
)
from sqlmodel import Field, SQLModel


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)

# The single row every process polls and every writer locks.
RELEASE_ROW_ID = 1


class GameConfigRelease(SQLModel, table=True):
    """Which revision is live. Exactly one row, id == 1.

    Kept separate from the revision table so the hot path — "has the config
    changed?" — is one narrow read of two columns instead of pulling the whole
    document bundle. Writers take ``SELECT ... FOR UPDATE`` on this row, which
    serializes concurrent publishes.
    """

    __tablename__ = "game_config_release"
    __table_args__ = (
        CheckConstraint("id = 1", name="ck_game_config_release_singleton"),
    )

    id: Optional[int] = Field(default=RELEASE_ROW_ID, primary_key=True)
    active_version: int = Field(nullable=False)
    active_checksum: str = Field(max_length=64)
    revision_id: int = Field(
        sa_column=Column(
            Integer,
            ForeignKey("game_config_revision.id", ondelete="RESTRICT"),
            nullable=False,
        ),
    )
    activated_at: datetime = Field(
        default_factory=_utc_now,
        sa_column=Column(
            DateTime(timezone=True),
            nullable=False,
            server_default=text("CURRENT_TIMESTAMP"),
        ),
    )
    activated_by_user_id: Optional[int] = Field(
        default=None,
        sa_column=Column(
            Integer, ForeignKey("user.id", ondelete="SET NULL"), nullable=True
        ),
    )
