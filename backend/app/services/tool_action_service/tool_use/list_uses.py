"""Unified tool-use history across missions and timed sessions."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

from sqlmodel import Session, col, select

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
from app.schemas.tool import ToolUseItem, ToolUsesResponse
from app.services.tool_action_service.tool_use.budget import (
    remaining_duration_s,
    total_duration_s_for_instance,
    used_duration_s_for_tool,
)


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


@dataclass
class ToolUseRecord:
    id: int
    kind: str
    action_key: str
    status: str
    started_at: datetime
    ended_at: datetime | None
    duration_s: int
    stop_reason: str | None
    params: dict[str, Any] = field(default_factory=dict)
    result: dict[str, Any] | None = None


def _session_params_guidance(row: GuidanceSession) -> dict[str, Any]:
    out: dict[str, Any] = {"duration_minutes": row.duration_minutes}
    if row.discovery_chance is not None:
        out["discovery_chance"] = row.discovery_chance
    if row.direction_exactness is not None:
        out["direction_exactness"] = row.direction_exactness
    if row.distance_exactness is not None:
        out["distance_exactness"] = row.distance_exactness
    return out


def _session_params_orbit(row: OrbitSurveySession) -> dict[str, Any]:
    return {
        "duration_minutes": row.duration_minutes,
        "accuracy": row.accuracy,
        "range": row.range,
    }


def _session_params_formation(row: FormationMapSession) -> dict[str, Any]:
    return {
        "duration_minutes": row.duration_minutes,
        "accuracy": row.accuracy,
        "wideness_m": row.wideness_m,
    }


def _session_params_echo(row: TerrainEchoSession) -> dict[str, Any]:
    return {
        "duration_minutes": row.duration_minutes,
        "accuracy": row.accuracy,
        "range_m": row.range_m,
    }


def _session_record(
    *,
    kind: str,
    row: Any,
    params: dict[str, Any],
    now: datetime,
) -> ToolUseRecord:
    if row.used_duration_s is not None:
        duration_s = int(row.used_duration_s)
        ended = row.ended_at
        stop = row.stop_reason
    elif row.status == "active":
        allocated = max(0, int((row.expires_at - row.started_at).total_seconds()))
        duration_s = min(
            max(0, int((now - row.started_at).total_seconds())),
            allocated,
        )
        ended = None
        stop = None
    else:
        end = row.ended_at or row.cancelled_at or row.expires_at or row.updated_at
        duration_s = max(0, int((end - row.started_at).total_seconds()))
        ended = end
        stop = row.stop_reason
    return ToolUseRecord(
        id=int(row.id),
        kind=kind,
        action_key=row.action_key,
        status=row.status,
        started_at=row.started_at,
        ended_at=ended,
        duration_s=duration_s,
        stop_reason=stop,
        params=params,
        result=None,
    )


def _mission_record(
    mission: ToolMission,
    *,
    discovered_site_ids: list[int],
    now: datetime,
) -> ToolUseRecord:
    if mission.used_duration_s is not None:
        duration_s = int(mission.used_duration_s)
        ended = mission.ended_at
        stop = mission.stop_reason
    elif mission.status == MISSION_STATUS_ENSURING:
        duration_s = max(0, int(mission.flight_duration_s))
        ended = None
        stop = None
    elif mission.status == MISSION_STATUS_FLYING and mission.flight_started_at:
        duration_s = min(
            max(0, int((now - mission.flight_started_at).total_seconds())),
            max(0, int(mission.flight_duration_s)),
        )
        ended = None
        stop = None
    else:
        if mission.flight_started_at is None:
            duration_s = 0
        else:
            end = mission.ended_at or mission.flight_ends_at or mission.updated_at
            duration_s = max(
                0, int((end - mission.flight_started_at).total_seconds())
            )
        ended = mission.ended_at or mission.flight_ends_at
        stop = mission.stop_reason

    started = mission.flight_started_at or mission.created_at
    params: dict[str, Any] = {
        "flight_duration_s": mission.flight_duration_s,
        "route_length_km": mission.route_length_km,
    }
    if mission.flight_speed_kmh is not None:
        params["flight_speed_kmh"] = mission.flight_speed_kmh
    if mission.max_route_km is not None:
        params["max_route_km"] = mission.max_route_km
    if mission.discovery_chance is not None:
        params["discovery_chance"] = mission.discovery_chance
    if mission.discovery_distance_m is not None:
        params["discovery_distance_m"] = mission.discovery_distance_m

    result: dict[str, Any] | None = None
    if discovered_site_ids:
        result = {
            "discovered_site_ids": discovered_site_ids,
            "discovered_count": len(discovered_site_ids),
        }

    return ToolUseRecord(
        id=int(mission.id),
        kind="aerial_mission",
        action_key=mission.action_key,
        status=mission.status,
        started_at=started,
        ended_at=ended,
        duration_s=duration_s,
        stop_reason=stop,
        params=params,
        result=result,
    )


def list_tool_uses(
    session: Session,
    *,
    tool_id: int,
    now: datetime | None = None,
) -> list[ToolUseRecord]:
    """All uses for a tool occurrence, newest first."""
    clock = now or _utcnow()
    records: list[ToolUseRecord] = []

    for row in session.exec(
        select(GuidanceSession).where(col(GuidanceSession.tool_id) == tool_id)
    ).all():
        records.append(
            _session_record(
                kind="guidance",
                row=row,
                params=_session_params_guidance(row),
                now=clock,
            )
        )

    for row in session.exec(
        select(OrbitSurveySession).where(
            col(OrbitSurveySession.tool_id) == tool_id
        )
    ).all():
        records.append(
            _session_record(
                kind="orbit_survey",
                row=row,
                params=_session_params_orbit(row),
                now=clock,
            )
        )

    for row in session.exec(
        select(FormationMapSession).where(
            col(FormationMapSession.tool_id) == tool_id
        )
    ).all():
        records.append(
            _session_record(
                kind="formation_map",
                row=row,
                params=_session_params_formation(row),
                now=clock,
            )
        )

    for row in session.exec(
        select(TerrainEchoSession).where(
            col(TerrainEchoSession.tool_id) == tool_id
        )
    ).all():
        records.append(
            _session_record(
                kind="terrain_echo",
                row=row,
                params=_session_params_echo(row),
                now=clock,
            )
        )

    from app.services.tool_action_service.serializers import (
        discovered_site_ids_by_mission,
    )

    missions = list(
        session.exec(
            select(ToolMission).where(col(ToolMission.tool_id) == tool_id)
        ).all()
    )
    by_mission = discovered_site_ids_by_mission(
        session, [int(m.id) for m in missions if m.id is not None]
    )
    for mission in missions:
        records.append(
            _mission_record(
                mission,
                discovered_site_ids=by_mission.get(int(mission.id), []),
                now=clock,
            )
        )

    records.sort(key=lambda r: r.started_at, reverse=True)
    return records


def tool_uses_response(
    session: Session,
    *,
    tool_type: ToolType,
    instance: Tool,
) -> ToolUsesResponse:
    now = _utcnow()
    total = total_duration_s_for_instance(tool_type, instance)
    used = used_duration_s_for_tool(
        session, tool_id=int(instance.id), now=now
    )
    remaining = remaining_duration_s(
        session, tool_type=tool_type, instance=instance, now=now
    )
    records = list_tool_uses(session, tool_id=int(instance.id), now=now)
    return ToolUsesResponse(
        tool_id=int(instance.id),
        total_duration_s=total,
        used_duration_s=used,
        remaining_duration_s=remaining,
        items=[
            ToolUseItem(
                id=r.id,
                kind=r.kind,
                action_key=r.action_key,
                status=r.status,
                started_at=r.started_at,
                ended_at=r.ended_at,
                duration_s=r.duration_s,
                stop_reason=r.stop_reason,
                params=r.params,
                result=r.result,
            )
            for r in records
        ],
    )
