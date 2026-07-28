"""Tool read, collect, and action endpoints."""

from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlmodel import Session, col, select

from app.core.database import get_session
from app.core.exceptions import ValidationError
from app.core.security import get_current_admin_user, get_current_user, get_optional_current_user
from app.models.guidance_session import GuidanceSession
from app.models.tool import Tool
from app.models.tool_mission import ToolMission
from app.models.tool_mission_event import (
    EVENT_STATUS_DONE,
    EVENT_TYPE_DISCOVER_SITE,
    ToolMissionEvent,
)
from app.models.tool_type import ToolType
from app.models.user import User
from app.schemas.tool import ToolCategoryItem, ToolCategoryListResponse, ToolListResponse, ToolSummary
from app.services.tool_action_service import (
    cancel_aerial_mission,
    cancel_guidance_session,
    get_active_guidance_session,
    list_aerial_missions,
    mission_route_dicts,
    start_aerial_mission,
    start_guidance_session,
)
from app.services.tool_action_service.aerial_mission_kinds import (
    config_for_action_key,
    is_aerial_action_key,
)
from app.services.tool_service import (
    collect_tool_for_user,
    get_tool_by_id,
    list_tool_categories,
    list_tools,
    tool_to_summary,
)

router = APIRouter(prefix="/tools", tags=["tools"])


class RoutePointBody(BaseModel):
    lat: float
    lon: float


class AerialMissionRequest(BaseModel):
    route: list[RoutePointBody] = Field(min_length=3)
    origin_lat: float
    origin_lon: float


class AerialMissionItem(BaseModel):
    mission_id: int
    action_key: str
    status: str
    route: list[RoutePointBody]
    route_length_km: float
    flight_duration_s: int
    flight_speed_kmh: float
    max_route_km: float
    discovery_chance: float
    discovery_distance_m: float
    flight_started_at: datetime | None = None
    flight_ends_at: datetime | None = None
    created_at: datetime
    tool_id: int
    tool_image_url: str | None = None
    discovered_site_ids: list[int] = Field(default_factory=list)


class AerialMissionListResponse(BaseModel):
    items: list[AerialMissionItem]


class AerialMissionResponse(BaseModel):
    mission_id: int
    action_key: str
    status: str
    route: list[RoutePointBody]
    route_length_km: float
    flight_duration_s: int
    flight_speed_kmh: float
    max_route_km: float
    discovery_chance: float
    discovery_distance_m: float
    flight_started_at: datetime | None = None
    flight_ends_at: datetime | None = None
    created_at: datetime
    tool_id: int
    tool_image_url: str | None = None
    discovered_site_ids: list[int] = Field(default_factory=list)


class GuidanceSessionResponse(BaseModel):
    session_id: int
    action_key: str
    status: str
    tool_id: int
    discovery_chance: float | None = None
    direction_exactness: float | None = None
    distance_exactness: float | None = None
    duration_minutes: int
    started_at: datetime
    expires_at: datetime
    cancelled_at: datetime | None = None


def _guidance_session_response(
    session: Session, row: GuidanceSession
) -> GuidanceSessionResponse:
    return GuidanceSessionResponse(
        session_id=int(row.id),
        action_key=row.action_key,
        status=row.status,
        tool_id=_tool_type_id_for_instance(session, int(row.tool_id)),
        discovery_chance=row.discovery_chance,
        direction_exactness=row.direction_exactness,
        distance_exactness=row.distance_exactness,
        duration_minutes=int(row.duration_minutes),
        started_at=row.started_at,
        expires_at=row.expires_at,
        cancelled_at=row.cancelled_at,
    )


def _tool_type_id_for_instance(session: Session, tool_instance_id: int) -> int:
    instance = session.get(Tool, tool_instance_id)
    if instance is None:
        return tool_instance_id
    return int(instance.tool_type_id)


def _tool_image_url(session: Session, tool_instance_id: int) -> str | None:
    instance = session.get(Tool, tool_instance_id)
    if instance is None:
        return None
    tool_type = session.get(ToolType, int(instance.tool_type_id))
    return tool_type.main_image_url if tool_type is not None else None


def _mission_flight_params(mission: ToolMission) -> tuple[float, float, float, float]:
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


def _discovered_site_ids_by_mission(
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


def _mission_item(
    session: Session,
    mission: ToolMission,
    *,
    discovered_site_ids: list[int] | None = None,
) -> AerialMissionItem:
    site_ids = discovered_site_ids
    if site_ids is None:
        site_ids = _discovered_site_ids_by_mission(
            session, [int(mission.id)]
        ).get(int(mission.id), [])
    speed_kmh, max_route_km, discovery_chance, discovery_distance_m = (
        _mission_flight_params(mission)
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
        tool_id=_tool_type_id_for_instance(session, int(mission.tool_id)),
        tool_image_url=_tool_image_url(session, int(mission.tool_id)),
        discovered_site_ids=site_ids,
    )


def _require_show_all_admin(current_user: User | None, show_all: bool) -> None:
    if not show_all:
        return
    if current_user is None or not current_user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin access required",
        )


@router.get("", response_model=ToolListResponse)
def get_tools(
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_optional_current_user),
    limit: int = Query(default=200, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    sort: str = Query(default="category"),
    seed: str | None = Query(default=None),
    q: str | None = Query(default=None),
    category: list[str] | None = Query(default=None),
    has_custom_image: bool = Query(default=False),
    show_all: bool = Query(default=False),
) -> ToolListResponse:
    if sort not in ("name", "random", "category"):
        raise ValidationError("sort must be one of: name, random, category")
    _require_show_all_admin(current_user, show_all)
    rows, total = list_tools(
        session,
        limit=limit,
        offset=offset,
        sort=sort,  # type: ignore[arg-type]
        seed=seed,
        q=q,
        categories=category,
        has_custom_image=has_custom_image,
        viewer_user_id=current_user.id if current_user is not None else None,
        show_all=show_all,
    )
    items = [tool_to_summary(tool, level) for tool, level in rows]
    return ToolListResponse(
        items=items,
        total=total,
        limit=limit,
        offset=offset,
        has_next=offset + len(items) < total,
    )


@router.get("/categories", response_model=ToolCategoryListResponse)
def get_tool_categories(
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_optional_current_user),
    show_all: bool = Query(default=False),
) -> ToolCategoryListResponse:
    _require_show_all_admin(current_user, show_all)
    items = [
        ToolCategoryItem(value=value, label=label)
        for value, label in list_tool_categories(
            session,
            viewer_user_id=current_user.id if current_user is not None else None,
            show_all=show_all,
        )
    ]
    return ToolCategoryListResponse(items=items)


@router.get(
    "/missions/aerial",
    response_model=AerialMissionListResponse,
)
def get_aerial_missions(
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
    action_key: str | None = Query(default=None),
) -> AerialMissionListResponse:
    missions = list_aerial_missions(
        session,
        user_id=int(current_user.id),
        action_key=action_key,
    )
    discovered = _discovered_site_ids_by_mission(
        session, [int(m.id) for m in missions if m.id is not None]
    )
    return AerialMissionListResponse(
        items=[
            _mission_item(
                session,
                m,
                discovered_site_ids=discovered.get(int(m.id), []),
            )
            for m in missions
        ]
    )


@router.post(
    "/missions/aerial/{mission_id}/cancel",
    response_model=AerialMissionResponse,
)
def post_cancel_aerial_mission(
    mission_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> AerialMissionResponse:
    mission = cancel_aerial_mission(
        session,
        user_id=int(current_user.id),
        mission_id=mission_id,
    )
    item = _mission_item(session, mission)
    return AerialMissionResponse(**item.model_dump())


@router.get(
    "/sessions/guidance/active",
    response_model=GuidanceSessionResponse,
)
def get_active_guidance(
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> GuidanceSessionResponse:
    row = get_active_guidance_session(session, user_id=int(current_user.id))
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No active guidance session",
        )
    return _guidance_session_response(session, row)


@router.post(
    "/sessions/guidance/cancel",
    response_model=GuidanceSessionResponse,
)
def post_cancel_guidance_session(
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> GuidanceSessionResponse:
    row = cancel_guidance_session(session, user_id=int(current_user.id))
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No active guidance session",
        )
    return _guidance_session_response(session, row)


@router.post("/{tool_id}/collect", response_model=ToolSummary)
def post_collect_tool(
    tool_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_admin_user),
) -> ToolSummary:
    tool, level = collect_tool_for_user(
        session,
        user_id=int(current_user.id),
        tool_id=tool_id,
    )
    return tool_to_summary(tool, level)


@router.post(
    "/{tool_id}/actions/aerial-mission",
    response_model=AerialMissionResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
def post_aerial_mission(
    tool_id: int,
    body: AerialMissionRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> AerialMissionResponse:
    mission = start_aerial_mission(
        session,
        user_id=int(current_user.id),
        tool_id=tool_id,
        route=[point.model_dump() for point in body.route],
        origin_lat=body.origin_lat,
        origin_lon=body.origin_lon,
    )
    item = _mission_item(session, mission)
    return AerialMissionResponse(**item.model_dump())


@router.post(
    "/{tool_id}/actions/guidance-session",
    response_model=GuidanceSessionResponse,
    status_code=status.HTTP_201_CREATED,
)
def post_guidance_session(
    tool_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> GuidanceSessionResponse:
    row = start_guidance_session(
        session,
        user_id=int(current_user.id),
        tool_id=tool_id,
    )
    return _guidance_session_response(session, row)


@router.get("/{tool_id}", response_model=ToolSummary)
def get_tool(
    tool_id: int,
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_optional_current_user),
) -> ToolSummary:
    row, level = get_tool_by_id(
        session,
        tool_id,
        viewer_user_id=current_user.id if current_user is not None else None,
    )
    return tool_to_summary(row, level)
