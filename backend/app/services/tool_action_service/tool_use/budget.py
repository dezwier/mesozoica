"""Lifetime battery: total / used / remaining for a tool occurrence."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from sqlmodel import Session, col, select

from app.core.exceptions import ValidationError
from app.models.formation_map_session import FormationMapSession
from app.models.guidance_session import GuidanceSession
from app.models.orbit_survey_session import OrbitSurveySession
from app.models.terrain_echo_session import TerrainEchoSession
from app.models.tool import Tool
from app.models.tool_mission import (
    MISSION_STATUS_ENSURING,
    MISSION_STATUS_FLYING,
    ToolMission,
)
from app.models.tool_type import ToolType
from app.services.tool_service.params import effective_params_for_instance

_ACTIVE = "active"


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def total_duration_s_for_instance(
    tool_type: ToolType,
    instance: Tool,
) -> int:
    """Lifetime battery in seconds from effective params / YAML."""
    params = effective_params_for_instance(tool_type, instance)
    minutes = params.get("duration_minutes")
    if minutes is None:
        minutes = 0
    return max(0, int(float(minutes) * 60))


def _session_charge_s(row: Any, *, now: datetime) -> int:
    if row.used_duration_s is not None:
        return max(0, int(row.used_duration_s))
    if row.status == _ACTIVE:
        allocated = max(0, int((row.expires_at - row.started_at).total_seconds()))
        elapsed = max(0, int((now - row.started_at).total_seconds()))
        return min(elapsed, allocated)
    end = row.ended_at or row.cancelled_at or row.expires_at or row.updated_at
    return max(0, int((end - row.started_at).total_seconds()))


def _mission_charge_s(mission: ToolMission, *, now: datetime) -> int:
    if mission.used_duration_s is not None:
        return max(0, int(mission.used_duration_s))
    if mission.status == MISSION_STATUS_ENSURING:
        # Reserve planned flight time until takeoff or cancel.
        return max(0, int(mission.flight_duration_s))
    if mission.status == MISSION_STATUS_FLYING and mission.flight_started_at is not None:
        elapsed = max(0, int((now - mission.flight_started_at).total_seconds()))
        return min(elapsed, max(0, int(mission.flight_duration_s)))
    if mission.flight_started_at is None:
        return 0
    end = mission.ended_at or mission.flight_ends_at or mission.updated_at
    return max(0, int((end - mission.flight_started_at).total_seconds()))


def used_duration_s_for_tool(
    session: Session,
    *,
    tool_id: int,
    now: datetime | None = None,
) -> int:
    """Sum charged seconds across all uses of this tool occurrence."""
    clock = now or _utcnow()
    total = 0

    for model in (
        GuidanceSession,
        OrbitSurveySession,
        FormationMapSession,
        TerrainEchoSession,
    ):
        rows = session.exec(
            select(model).where(col(model.tool_id) == tool_id)
        ).all()
        for row in rows:
            total += _session_charge_s(row, now=clock)

    missions = session.exec(
        select(ToolMission).where(col(ToolMission.tool_id) == tool_id)
    ).all()
    for mission in missions:
        total += _mission_charge_s(mission, now=clock)

    return total


def remaining_duration_s(
    session: Session,
    *,
    tool_type: ToolType,
    instance: Tool,
    now: datetime | None = None,
) -> int:
    total = total_duration_s_for_instance(tool_type, instance)
    used = used_duration_s_for_tool(
        session, tool_id=int(instance.id), now=now
    )
    return max(0, total - used)


def allocate_remaining_for_start(
    session: Session,
    *,
    tool_type: ToolType,
    instance: Tool,
    min_duration_minutes: int | None = None,
    now: datetime | None = None,
) -> int:
    """Return remaining seconds to allocate for a new use, or raise.

    Timed sessions consume the full remaining battery. Aerial callers use this
    to size max route from remaining minutes.
    """
    clock = now or _utcnow()
    remaining = remaining_duration_s(
        session, tool_type=tool_type, instance=instance, now=clock
    )
    if remaining <= 0:
        raise ValidationError("No duration left on this tool card")
    if min_duration_minutes is not None:
        min_s = int(min_duration_minutes) * 60
        if remaining < min_s:
            raise ValidationError(
                f"Need at least {min_duration_minutes} minutes left on this tool card"
            )
    return remaining


def remaining_minutes_for_route(
    session: Session,
    *,
    tool_type: ToolType,
    instance: Tool,
    now: datetime | None = None,
) -> float:
    """Remaining battery as fractional minutes (for aerial max-route)."""
    remaining_s = remaining_duration_s(
        session, tool_type=tool_type, instance=instance, now=now
    )
    return remaining_s / 60.0
