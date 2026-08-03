"""Unified tool-card activation (one row per use)."""

from __future__ import annotations

from datetime import datetime
from typing import Any, Optional

from sqlalchemy import JSON, Column
from sqlmodel import Field, SQLModel

SESSION_STATUS_PENDING = "pending"
SESSION_STATUS_ACTIVE = "active"
SESSION_STATUS_COMPLETED = "completed"
SESSION_STATUS_CANCELLED = "cancelled"
SESSION_STATUS_FAILED = "failed"

STOP_REASON_MANUAL = "manual"
STOP_REASON_EXHAUSTED = "exhausted"
STOP_REASON_FAILED = "failed"

ACTION_KEY_AERIAL_RECON = "aerial_recon"
ACTION_KEY_AERIAL_SCOUT = "aerial_scout"
ACTION_KEY_GEO_COMPASS = "geo_compass"
ACTION_KEY_PROXIMITY_SCANNER = "proximity_scanner"
ACTION_KEY_SITE_NAVIGATOR = "site_navigator"
ACTION_KEY_ORBIT_SURVEY = "orbit_survey"
ACTION_KEY_FORMATION_MAP = "formation_map"
ACTION_KEY_TERRAIN_ECHO = "terrain_echo"
ACTION_KEY_RIDGE_GLASS = "ridge_glass"
ACTION_KEY_EXPEDITION_DRIVETRAIN = "expedition_drivetrain"

AERIAL_ACTION_KEYS = (ACTION_KEY_AERIAL_RECON, ACTION_KEY_AERIAL_SCOUT)
GUIDANCE_ACTION_KEYS = (
    ACTION_KEY_GEO_COMPASS,
    ACTION_KEY_PROXIMITY_SCANNER,
    ACTION_KEY_SITE_NAVIGATOR,
)
# Timed tools whose `using` mods apply globally (not nearest-site only).
GLOBAL_BUFF_ACTION_KEYS = (
    ACTION_KEY_RIDGE_GLASS,
    ACTION_KEY_EXPEDITION_DRIVETRAIN,
)
TIMED_OVERLAY_ACTION_KEYS = (
    ACTION_KEY_ORBIT_SURVEY,
    ACTION_KEY_FORMATION_MAP,
    ACTION_KEY_TERRAIN_ECHO,
    *GLOBAL_BUFF_ACTION_KEYS,
    *GUIDANCE_ACTION_KEYS,
)

# Live / not-yet-closed for battery + mutual exclusivity.
LIVE_STATUSES = (SESSION_STATUS_PENDING, SESSION_STATUS_ACTIVE)


class ToolSession(SQLModel, table=True):
    __tablename__ = "tool_session"

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(index=True, foreign_key="user.id")
    tool_id: int = Field(foreign_key="tool.id", index=True)
    action_key: str = Field(max_length=64, index=True)
    status: str = Field(default=SESSION_STATUS_ACTIVE, max_length=16, index=True)
    started_at: datetime = Field(default_factory=datetime.utcnow)
    expires_at: Optional[datetime] = Field(default=None, index=True)
    ended_at: Optional[datetime] = Field(default=None)
    used_duration_s: Optional[int] = Field(default=None)
    stop_reason: Optional[str] = Field(default=None, max_length=16)
    params_json: dict[str, Any] = Field(
        default_factory=dict,
        sa_column=Column(JSON, nullable=False),
    )
    state_json: dict[str, Any] = Field(
        default_factory=dict,
        sa_column=Column(JSON, nullable=False),
    )
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
