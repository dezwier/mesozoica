"""Serialize tool-action domain rows into API response schemas."""

from __future__ import annotations

from sqlmodel import Session, col, select

from app.models.formation_map_session import FormationMapSession
from app.models.orbit_survey_session import OrbitSurveySession
from app.models.guidance_session import GuidanceSession
from app.models.tool import Tool
from app.models.tool_mission import ToolMission
from app.models.tool_mission_event import (
    EVENT_STATUS_DONE,
    EVENT_TYPE_DISCOVER_SITE,
    ToolMissionEvent,
)
from app.models.tool_type import ToolType
from app.schemas.tool import (
    AerialMissionItem,
    AerialMissionResponse,
    FormationMapSessionResponse,
    OrbitSurveySessionResponse,
    GuidanceSessionResponse,
    RoutePointBody,
)
from app.services.tool_action_service.aerial_mission import mission_route_dicts
from app.services.tool_action_service.aerial_mission_kinds import (
    config_for_action_key,
    is_aerial_action_key,
)


def tool_image_url(session: Session, tool_instance_id: int) -> str | None:
    from app.services.curated_image_service.resolve import resolve_tool_card_image_url

    instance = session.get(Tool, tool_instance_id)
    if instance is None:
        return None
    tool_type = session.get(ToolType, int(instance.tool_type_id))
    if tool_type is None:
        return None
    return resolve_tool_card_image_url(
        tool_name=tool_type.name,
        version=instance.version,
        fallback_url=tool_type.main_image_url,
    )


def mission_flight_params(mission: ToolMission) -> tuple[float, float, float, float]:
    """Snapshotted knobs, falling back to current game config for legacy rows."""
    from app.models.tool_mission import ACTION_KEY_AERIAL_RECON

    key = (
        mission.action_key
        if is_aerial_action_key(mission.action_key)
        else ACTION_KEY_AERIAL_RECON
    )
    cfg = config_for_action_key(key)
    return (
        float(mission.flight_speed_kmh)
        if mission.flight_speed_kmh is not None
        else float(cfg.flight_speed_kmh),
        float(mission.max_route_km)
        if mission.max_route_km is not None
        else float(cfg.max_route_km),
        float(mission.discovery_chance)
        if mission.discovery_chance is not None
        else float(cfg.discovery_chance),
        float(mission.discovery_distance_m)
        if mission.discovery_distance_m is not None
        else float(cfg.discovery_distance_m),
    )


def discovered_site_ids_by_mission(
    session: Session,
    mission_ids: list[int],
) -> dict[int, list[int]]:
    """Site IDs from successful discover events, keyed by mission_id."""
    if not mission_ids:
        return {}
    rows = session.exec(
        select(ToolMissionEvent.mission_id, ToolMissionEvent.site_id).where(
            col(ToolMissionEvent.mission_id).in_(mission_ids),
            col(ToolMissionEvent.event_type) == EVENT_TYPE_DISCOVER_SITE,
            col(ToolMissionEvent.status) == EVENT_STATUS_DONE,
            col(ToolMissionEvent.site_id).is_not(None),
        )
    ).all()
    by_mission: dict[int, list[int]] = {mid: [] for mid in mission_ids}
    for mission_id, site_id in rows:
        if site_id is None:
            continue
        by_mission.setdefault(int(mission_id), []).append(int(site_id))
    return by_mission


def mission_item(
    session: Session,
    mission: ToolMission,
    *,
    discovered_site_ids: list[int] | None = None,
) -> AerialMissionItem:
    site_ids = discovered_site_ids
    if site_ids is None:
        site_ids = discovered_site_ids_by_mission(
            session, [int(mission.id)]
        ).get(int(mission.id), [])
    speed_kmh, max_route_km, discovery_chance, discovery_distance_m = (
        mission_flight_params(mission)
    )
    return AerialMissionItem(
        mission_id=int(mission.id),
        action_key=mission.action_key,
        status=mission.status,
        route=[RoutePointBody(**p) for p in mission_route_dicts(mission)],
        route_length_km=mission.route_length_km,
        flight_duration_s=mission.flight_duration_s,
        flight_speed_kmh=speed_kmh,
        max_route_km=max_route_km,
        discovery_chance=discovery_chance,
        discovery_distance_m=discovery_distance_m,
        flight_started_at=mission.flight_started_at,
        flight_ends_at=mission.flight_ends_at,
        created_at=mission.created_at,
        tool_id=int(mission.tool_id),
        tool_image_url=tool_image_url(session, int(mission.tool_id)),
        discovered_site_ids=site_ids,
    )


def mission_response(
    session: Session,
    mission: ToolMission,
    *,
    discovered_site_ids: list[int] | None = None,
) -> AerialMissionResponse:
    item = mission_item(
        session, mission, discovered_site_ids=discovered_site_ids
    )
    return AerialMissionResponse(**item.model_dump())


def guidance_session_response(row: GuidanceSession) -> GuidanceSessionResponse:
    return GuidanceSessionResponse(
        session_id=int(row.id),
        action_key=row.action_key,
        status=row.status,
        tool_id=int(row.tool_id),
        discovery_chance=row.discovery_chance,
        direction_exactness=row.direction_exactness,
        distance_exactness=row.distance_exactness,
        duration_minutes=int(row.duration_minutes),
        started_at=row.started_at,
        expires_at=row.expires_at,
        cancelled_at=row.cancelled_at,
    )


def orbit_survey_session_response(
    row: OrbitSurveySession,
) -> OrbitSurveySessionResponse:
    return OrbitSurveySessionResponse(
        session_id=int(row.id),
        action_key=row.action_key,
        status=row.status,
        tool_id=int(row.tool_id),
        duration_minutes=int(row.duration_minutes),
        accuracy=float(row.accuracy),
        range=float(row.range),
        min_range_m=float(row.min_range_m),
        max_range_m=float(row.max_range_m),
        started_at=row.started_at,
        expires_at=row.expires_at,
        cancelled_at=row.cancelled_at,
    )


def formation_map_session_response(
    row: FormationMapSession,
) -> FormationMapSessionResponse:
    return FormationMapSessionResponse(
        session_id=int(row.id),
        action_key=row.action_key,
        status=row.status,
        tool_id=int(row.tool_id),
        duration_minutes=int(row.duration_minutes),
        accuracy=float(row.accuracy),
        wideness_m=float(row.wideness_m),
        cell_size_m=float(row.cell_size_m),
        center_lat=float(row.center_lat),
        center_lon=float(row.center_lon),
        started_at=row.started_at,
        expires_at=row.expires_at,
        cancelled_at=row.cancelled_at,
    )
