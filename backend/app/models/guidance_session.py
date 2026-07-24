"""Timed site-guidance tool sessions (compass / proximity / navigator)."""

from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlmodel import Field, SQLModel

ACTION_KEY_GEO_COMPASS = "geo_compass"
ACTION_KEY_PROXIMITY_SCANNER = "proximity_scanner"
ACTION_KEY_SITE_NAVIGATOR = "site_navigator"
GUIDANCE_ACTION_KEYS = (
    ACTION_KEY_GEO_COMPASS,
    ACTION_KEY_PROXIMITY_SCANNER,
    ACTION_KEY_SITE_NAVIGATOR,
)

SESSION_STATUS_ACTIVE = "active"
SESSION_STATUS_CANCELLED = "cancelled"
SESSION_STATUS_EXPIRED = "expired"


class GuidanceSession(SQLModel, table=True):
    __tablename__ = "guidance_session"

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(index=True, foreign_key="user.id")
    tool_id: int = Field(foreign_key="tool.id")
    action_key: str = Field(max_length=64, index=True)
    status: str = Field(default=SESSION_STATUS_ACTIVE, max_length=16, index=True)
    # Snapshotted from tool_actions.yaml at start.
    discovery_chance: Optional[float] = Field(default=None)
    direction_exactness: Optional[float] = Field(default=None)
    distance_exactness: Optional[float] = Field(default=None)
    duration_minutes: int = Field(default=15)
    started_at: datetime = Field(default_factory=datetime.utcnow)
    expires_at: datetime = Field(index=True)
    cancelled_at: Optional[datetime] = Field(default=None)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
