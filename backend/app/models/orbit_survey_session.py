"""Timed Orbit Survey tool sessions (period mosaic overlay)."""

from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlmodel import Field, SQLModel

ACTION_KEY_ORBIT_SURVEY = "orbit_survey"
ORBIT_SURVEY_ACTION_KEYS = (ACTION_KEY_ORBIT_SURVEY,)

SESSION_STATUS_ACTIVE = "active"
SESSION_STATUS_CANCELLED = "cancelled"
SESSION_STATUS_EXPIRED = "expired"


class OrbitSurveySession(SQLModel, table=True):
    __tablename__ = "orbit_survey_session"

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(index=True, foreign_key="user.id")
    tool_id: int = Field(foreign_key="tool.id")
    action_key: str = Field(default=ACTION_KEY_ORBIT_SURVEY, max_length=64, index=True)
    status: str = Field(default=SESSION_STATUS_ACTIVE, max_length=16, index=True)
    # Snapshotted from tool_actions.yaml at start.
    duration_minutes: int = Field(default=10)
    accuracy: float = Field(default=0.75)
    range: float = Field(default=0.35)
    min_range_m: float = Field(default=200.0)
    max_range_m: float = Field(default=2000.0)
    started_at: datetime = Field(default_factory=datetime.utcnow)
    expires_at: datetime = Field(index=True)
    cancelled_at: Optional[datetime] = Field(default=None)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
