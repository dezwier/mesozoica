"""Queued tool-action missions (e.g. Aerial Recon scout loops)."""

from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlmodel import Field, SQLModel

MISSION_STATUS_ENSURING = "ensuring"
MISSION_STATUS_FLYING = "flying"
MISSION_STATUS_DONE = "done"
MISSION_STATUS_FAILED = "failed"

ACTION_KEY_AERIAL_RECON = "aerial_recon"


class ToolMission(SQLModel, table=True):
    __tablename__ = "tool_mission"

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(index=True, foreign_key="user.id")
    tool_id: int = Field(foreign_key="tool.id")
    action_key: str = Field(max_length=64, index=True)
    status: str = Field(default=MISSION_STATUS_ENSURING, max_length=16, index=True)
    route_json: str
    route_length_km: float
    flight_duration_s: int
    ensure_job_ids_json: Optional[str] = Field(default=None)
    flight_started_at: Optional[datetime] = Field(default=None)
    flight_ends_at: Optional[datetime] = Field(default=None)
    error_message: Optional[str] = Field(default=None, max_length=2000)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
