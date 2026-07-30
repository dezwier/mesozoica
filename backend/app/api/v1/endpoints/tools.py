"""Tool read, collect, and action endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlmodel import Session

from app.core.database import get_session
from app.core.exceptions import ValidationError
from app.core.security import get_current_admin_user, get_current_user, get_optional_current_user
from app.models.user import User
from app.schemas.tool import (
    AerialMissionListResponse,
    AerialMissionRequest,
    AerialMissionResponse,
    FormationMapSessionResponse,
    GuidanceSessionResponse,
    ToolCategoryItem,
    ToolCategoryListResponse,
    ToolListResponse,
    ToolSummary,
    UpdateToolParamsRequest,
)
from app.services.tool_action_service import (
    cancel_aerial_mission,
    cancel_formation_map_session,
    cancel_guidance_session,
    get_active_formation_map_session,
    get_active_guidance_session,
    list_aerial_missions,
    start_aerial_mission,
    start_formation_map_session,
    start_guidance_session,
)
from app.services.tool_action_service.serializers import (
    discovered_site_ids_by_mission,
    formation_map_session_response,
    guidance_session_response,
    mission_item,
    mission_response,
)
from app.services.tool_service import (
    collect_tool_for_user,
    get_tool_by_id,
    list_tool_categories,
    list_tools,
    tool_to_summary,
)
from app.services.tool_service.list import ListMode, ToolListRow
from app.services.tool_service.update_params import update_tool_instance_params

router = APIRouter(prefix="/tools", tags=["tools"])


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
    mode: ListMode = Query(default="inventory"),
) -> ToolListResponse:
    if sort not in ("name", "random", "category"):
        raise ValidationError("sort must be one of: name, random, category")
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
        show_all=True if mode == "catalog" else False,
        mode=mode,
    )
    items = [tool_to_summary(row) for row in rows]
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
    mode: ListMode = Query(default="inventory"),
) -> ToolCategoryListResponse:
    if mode != "catalog":
        _require_show_all_admin(current_user, show_all)
    items = [
        ToolCategoryItem(value=value, label=label)
        for value, label in list_tool_categories(
            session,
            viewer_user_id=current_user.id if current_user is not None else None,
            show_all=True if mode == "catalog" else False,
            mode=mode,
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
    discovered = discovered_site_ids_by_mission(
        session, [int(m.id) for m in missions if m.id is not None]
    )
    return AerialMissionListResponse(
        items=[
            mission_item(
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
    return mission_response(session, mission)


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
    return guidance_session_response(row)


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
    return guidance_session_response(row)


@router.get(
    "/sessions/formation-map/active",
    response_model=FormationMapSessionResponse,
)
def get_active_formation_map(
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> FormationMapSessionResponse:
    row = get_active_formation_map_session(session, user_id=int(current_user.id))
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No active formation map session",
        )
    return formation_map_session_response(row)


@router.post(
    "/sessions/formation-map/cancel",
    response_model=FormationMapSessionResponse,
)
def post_cancel_formation_map_session(
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> FormationMapSessionResponse:
    row = cancel_formation_map_session(session, user_id=int(current_user.id))
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No active formation map session",
        )
    return formation_map_session_response(row)


@router.post("/{tool_id}/collect", response_model=ToolSummary)
def post_collect_tool(
    tool_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_admin_user),
) -> ToolSummary:
    tool_type, level = collect_tool_for_user(
        session,
        user_id=int(current_user.id),
        tool_id=tool_id,
    )
    return tool_to_summary(ToolListRow(tool_type=tool_type, level=level))


@router.patch("/{tool_id}/params", response_model=ToolSummary)
def patch_tool_instance_params(
    tool_id: int,
    body: UpdateToolParamsRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_admin_user),
) -> ToolSummary:
    """Admin-only: update per-instance params for an owned Tool occurrence."""
    row = update_tool_instance_params(
        session,
        tool_id=tool_id,
        params=body.params,
    )
    return tool_to_summary(row)


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
    return mission_response(session, mission)


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
    return guidance_session_response(row)


@router.post(
    "/{tool_id}/actions/formation-map-session",
    response_model=FormationMapSessionResponse,
    status_code=status.HTTP_201_CREATED,
)
def post_formation_map_session(
    tool_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> FormationMapSessionResponse:
    row = start_formation_map_session(
        session,
        user_id=int(current_user.id),
        tool_id=tool_id,
    )
    return formation_map_session_response(row)


@router.get("/{tool_id}", response_model=ToolSummary)
def get_tool(
    tool_id: int,
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_optional_current_user),
) -> ToolSummary:
    row = get_tool_by_id(
        session,
        tool_id,
        viewer_user_id=current_user.id if current_user is not None else None,
    )
    return tool_to_summary(row)
