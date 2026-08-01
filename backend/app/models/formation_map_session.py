"""Timed Formation Map tool sessions (rock-type square mosaic)."""

from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlmodel import Field, SQLModel

ACTION_KEY_FORMATION_MAP = "formation_map"
FORMATION_MAP_ACTION_KEYS = (ACTION_KEY_FORMATION_MAP,)

SESSION_STATUS_ACTIVE = "active"
SESSION_STATUS_CANCELLED = "cancelled"
SESSION_STATUS_EXPIRED = "expired"


class FormationMapSession(SQLModel, table=True):
    __tablename__ = "formation_map_session"

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(index=True, foreign_key="user.id")
    tool_id: int = Field(foreign_key="tool.id")
    action_key: str = Field(default=ACTION_KEY_FORMATION_MAP, max_length=64, index=True)
    status: str = Field(default=SESSION_STATUS_ACTIVE, max_length=16, index=True)
    duration_minutes: int = Field(default=10)
    accuracy: float = Field(default=0.75)
    wideness_m: float = Field(default=500.0)
    cell_size_m: float = Field(default=500.0)
    center_lat: float = Field(default=0.0)
    center_lon: float = Field(default=0.0)
    started_at: datetime = Field(default_factory=datetime.utcnow)
    expires_at: datetime = Field(index=True)
    cancelled_at: Optional[datetime] = Field(default=None)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
