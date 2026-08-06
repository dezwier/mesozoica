"""Events that fire during a tool session (e.g. aerial site discoveries). Owned by the tools feature."""

from __future__ import annotations

from datetime import datetime
from typing import Any, Optional

from sqlalchemy import JSON, Column
from sqlmodel import Field, SQLModel

EVENT_TYPE_DISCOVER_SITE = "discover_site"

EVENT_STATUS_PENDING = "pending"
EVENT_STATUS_DONE = "done"
EVENT_STATUS_MISS = "miss"
EVENT_STATUS_SKIPPED = "skipped"


class ToolSessionEvent(SQLModel, table=True):
    __tablename__ = "tool_session_event"

    id: Optional[int] = Field(default=None, primary_key=True)
    session_id: int = Field(index=True, foreign_key="tool_session.id")
    event_type: str = Field(max_length=32)
    site_id: Optional[int] = Field(default=None, foreign_key="site.site_id")
    due_at: datetime = Field(index=True)
    status: str = Field(default=EVENT_STATUS_PENDING, max_length=16, index=True)
    lat: Optional[float] = Field(default=None)
    lon: Optional[float] = Field(default=None)
    payload_json: dict[str, Any] = Field(
        default_factory=dict,
        sa_column=Column(JSON, nullable=False),
    )
    created_at: datetime = Field(default_factory=datetime.utcnow)
    processed_at: Optional[datetime] = Field(default=None)
