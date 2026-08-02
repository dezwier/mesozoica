"""Persist ended_at / used_duration_s / stop_reason on sessions and missions."""

from __future__ import annotations

from datetime import datetime
from typing import Protocol

from app.models.guidance_session import STOP_REASON_EXHAUSTED, STOP_REASON_MANUAL
from app.models.tool_mission import (
    MISSION_STATUS_CANCELLED,
    MISSION_STATUS_DONE,
    MISSION_STATUS_FAILED,
    STOP_REASON_FAILED,
    ToolMission,
)


class _SessionLike(Protocol):
    started_at: datetime
    expires_at: datetime
    cancelled_at: datetime | None
    ended_at: datetime | None
    used_duration_s: int | None
    stop_reason: str | None
    updated_at: datetime


def close_session(
    row: _SessionLike,
    *,
    now: datetime,
    stop_reason: str,
) -> None:
    """Stamp close-out fields for a timed tool session."""
    if row.used_duration_s is not None:
        return
    if stop_reason == STOP_REASON_MANUAL:
        end = now
        if row.cancelled_at is None:
            row.cancelled_at = now
        elapsed = max(0, int((end - row.started_at).total_seconds()))
    else:
        # Exhausted: charge the allocated window.
        end = row.expires_at if row.expires_at <= now else now
        allocated = max(0, int((row.expires_at - row.started_at).total_seconds()))
        elapsed = allocated
    row.ended_at = end
    row.used_duration_s = elapsed
    row.stop_reason = stop_reason
    row.updated_at = now


def close_mission(
    mission: ToolMission,
    *,
    now: datetime,
    stop_reason: str | None = None,
) -> None:
    """Stamp close-out fields for an aerial mission."""
    if mission.used_duration_s is not None:
        return
    reason = stop_reason
    if reason is None:
        if mission.status == MISSION_STATUS_CANCELLED:
            reason = STOP_REASON_MANUAL
        elif mission.status == MISSION_STATUS_FAILED:
            reason = STOP_REASON_FAILED
        elif mission.status == MISSION_STATUS_DONE:
            reason = STOP_REASON_EXHAUSTED
        else:
            reason = STOP_REASON_MANUAL

    if mission.flight_started_at is None:
        used = 0
        end = now
    elif reason == STOP_REASON_EXHAUSTED:
        used = max(0, int(mission.flight_duration_s))
        end = mission.flight_ends_at or now
    else:
        end = mission.flight_ends_at or now
        used = max(0, int((end - mission.flight_started_at).total_seconds()))

    mission.ended_at = end
    mission.used_duration_s = used
    mission.stop_reason = reason
    mission.updated_at = now
