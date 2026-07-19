"""Lifecycle status history for field sites."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import Column, DateTime, ForeignKey, Integer, text
from sqlmodel import Field, SQLModel

SITE_STATUS_HIDDEN = "hidden"
SITE_STATUS_DISCOVERED = "discovered"
SITE_STATUS_EXCAVATION = "excavation"
SITE_STATUS_EXHAUSTED = "exhausted"
SITE_STATUS_PROTECTED = "protected"

SITE_STATUSES: tuple[str, ...] = (
    SITE_STATUS_HIDDEN,
    SITE_STATUS_DISCOVERED,
    SITE_STATUS_EXCAVATION,
    SITE_STATUS_EXHAUSTED,
    SITE_STATUS_PROTECTED,
)


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class SiteStatus(SQLModel, table=True):
    """Append-only status records; current status is the latest by timestamp."""

    __tablename__ = "site_status"

    id: Optional[int] = Field(default=None, primary_key=True)
    site_id: int = Field(
        sa_column=Column(
            Integer,
            ForeignKey("site.site_id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
    )
    timestamp: datetime = Field(
        default_factory=_utc_now,
        sa_column=Column(
            DateTime(timezone=True),
            nullable=False,
            server_default=text("CURRENT_TIMESTAMP"),
            index=True,
        ),
    )
    status: str = Field(
        default=SITE_STATUS_HIDDEN,
        max_length=16,
        description=(
            "hidden, discovered, excavation, exhausted, or protected"
        ),
    )
