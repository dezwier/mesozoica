"""Timed Terrain Echo tool sessions (vintage radar overlay)."""

from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlmodel import Field, SQLModel

ACTION_KEY_TERRAIN_ECHO = "terrain_echo"
TERRAIN_ECHO_ACTION_KEYS = (ACTION_KEY_TERRAIN_ECHO,)

SESSION_STATUS_ACTIVE = "active"
SESSION_STATUS_CANCELLED = "cancelled"
SESSION_STATUS_EXPIRED = "expired"


class TerrainEchoSession(SQLModel, table=True):
    __tablename__ = "terrain_echo_session"

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(index=True, foreign_key="user.id")
    tool_id: int = Field(foreign_key="tool.id")
    action_key: str = Field(default=ACTION_KEY_TERRAIN_ECHO, max_length=64, index=True)
    status: str = Field(default=SESSION_STATUS_ACTIVE, max_length=16, index=True)
    # Snapshotted from tool_actions.yaml at start.
    duration_minutes: int = Field(default=5)
    degrees: float = Field(default=20.0)
    accuracy: float = Field(default=0.0)
    range_m: float = Field(default=20.0)
    started_at: datetime = Field(default_factory=datetime.utcnow)
    expires_at: datetime = Field(index=True)
    cancelled_at: Optional[datetime] = Field(default=None)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
