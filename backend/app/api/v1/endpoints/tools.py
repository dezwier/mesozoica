"""Tool read, collect, and action endpoints."""

from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlmodel import Session

from app.core.database import get_session
from app.core.exceptions import ValidationError
from app.core.security import get_current_admin_user, get_current_user, get_optional_current_user
from app.models.tool import Tool
from app.models.tool_mission import ToolMission
from app.models.user import User
from app.schemas.tool import ToolCategoryItem, ToolCategoryListResponse, ToolListResponse, ToolSummary
from app.services.tool_action_service import (
    list_aerial_recon_missions,
    mission_route_dicts,
    start_aerial_recon_mission,
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


class AerialReconRequest(BaseModel):
    route: list[RoutePointBody] = Field(min_length=3)
    origin_lat: float
    origin_lon: float


class AerialReconMissionItem(BaseModel):
    mission_id: int
    status: str
    route: list[RoutePointBody]
    route_length_km: float
    flight_duration_s: int
    flight_started_at: datetime | None = None
    flight_ends_at: datetime | None = None
    created_at: datetime
    tool_id: int
    tool_image_url: str | None = None


class AerialReconMissionListResponse(BaseModel):
    items: list[AerialReconMissionItem]


class AerialReconResponse(BaseModel):
    mission_id: int
    status: str
    route: list[RoutePointBody]
    route_length_km: float
    flight_duration_s: int
    flight_started_at: datetime | None = None
    flight_ends_at: datetime | None = None
    created_at: datetime
    tool_id: int
    tool_image_url: str | None = None


def _tool_image_url(session: Session, tool_id: int) -> str | None:
    tool = session.get(Tool, tool_id)
    return tool.main_image_url if tool is not None else None


def _mission_item(session: Session, mission: ToolMission) -> AerialReconMissionItem:
    return AerialReconMissionItem(
        mission_id=int(mission.id),
        status=mission.status,
        route=[RoutePointBody(**p) for p in mission_route_dicts(mission)],
        route_length_km=mission.route_length_km,
        flight_duration_s=mission.flight_duration_s,
        flight_started_at=mission.flight_started_at,
        flight_ends_at=mission.flight_ends_at,
        created_at=mission.created_at,
        tool_id=mission.tool_id,
        tool_image_url=_tool_image_url(session, mission.tool_id),
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
    "/missions/aerial-recon",
    response_model=AerialReconMissionListResponse,
)
def get_aerial_recon_missions(
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> AerialReconMissionListResponse:
    missions = list_aerial_recon_missions(session, user_id=int(current_user.id))
    return AerialReconMissionListResponse(
        items=[_mission_item(session, m) for m in missions]
    )


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
    "/{tool_id}/actions/aerial-recon",
    response_model=AerialReconResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
def post_aerial_recon(
    tool_id: int,
    body: AerialReconRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> AerialReconResponse:
    mission = start_aerial_recon_mission(
        session,
        user_id=int(current_user.id),
        tool_id=tool_id,
        route=[point.model_dump() for point in body.route],
        origin_lat=body.origin_lat,
        origin_lon=body.origin_lon,
    )
    item = _mission_item(session, mission)
    return AerialReconResponse(**item.model_dump())


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
