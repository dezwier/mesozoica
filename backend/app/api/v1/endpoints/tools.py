"""Tool read, collect, and session endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlmodel import Session

from app.core.database import get_session
from app.core.exceptions import ValidationError
from app.core.security import get_current_admin_user, get_current_user, get_optional_current_user
from app.models.tool_session import AERIAL_ACTION_KEYS, ToolSession
from app.models.user import User
from app.schemas.tool import (
    CollectToolRequest,
    ToolCategoryItem,
    ToolCategoryListResponse,
    ToolImageVersionItem,
    ToolImageVersionListResponse,
    ToolListResponse,
    ToolSessionListResponse,
    ToolSessionResponse,
    ToolSessionStartRequest,
    ToolSummary,
    UpdateToolParamsRequest,
)
from app.services.tool_action_service import (
    cancel_aerial_session,
    cancel_timed_session,
    list_active_sessions,
    sessions_for_tool_response,
    start_aerial_session,
    start_timed_session,
    tool_session_response,
)
from app.services.tool_action_service.aerial_action_keys import kind_for_tool_name
from app.services.tool_action_service.tool_session.serialize import (
    discovered_site_ids_by_session,
)
from app.services.tool_service import (
    collect_tool_for_user,
    get_tool_by_id,
    list_tool_categories,
    list_tools,
    tool_to_summary,
)
from app.services.tool_service.collect import (
    list_tool_image_versions,
    resolve_owned_tool_selection,
)
from app.services.tool_service.list import ListMode, ToolListRow, owned_occurrences_for_tool_types
from app.services.curated_image_service.versions import ORIGINAL_VERSION
from app.services.tool_service.update_params import update_tool_instance_params
from app.models.tool_type import ToolType

router = APIRouter(prefix="/tools", tags=["tools"])


def _require_show_all_admin(current_user: User | None, show_all: bool) -> None:
    if not show_all:
        return
    if current_user is None or not current_user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin access required",
        )


def _to_session_response(payload: dict) -> ToolSessionResponse:
    return ToolSessionResponse.model_validate(payload)


def _is_aerial_tool(tool_type: ToolType) -> bool:
    try:
        kind_for_tool_name(tool_type.name)
        return True
    except ValidationError:
        return False


@router.get("", response_model=ToolListResponse)
def get_tools(
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_optional_current_user),
    limit: int = Query(default=200, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    sort: str = Query(default="spawn_date"),
    seed: str | None = Query(default=None),
    q: str | None = Query(default=None),
    category: list[str] | None = Query(default=None),
    has_custom_image: bool = Query(default=False),
    show_all: bool = Query(default=False),
    mode: ListMode = Query(default="inventory"),
) -> ToolListResponse:
    if sort not in ("name", "random", "category", "spawn_date"):
        raise ValidationError(
            "sort must be one of: name, random, category, spawn_date"
        )
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
    viewer_user_id = current_user.id if current_user is not None else None
    if mode == "catalog":
        type_ids = [int(row.tool_type.id) for row in rows if row.tool_type.id is not None]
        owned = owned_occurrences_for_tool_types(
            session, type_ids=type_ids, viewer_user_id=viewer_user_id
        )
        items = [
            tool_to_summary(
                row,
                owned_occurrences=owned.get(int(row.tool_type.id), [])
                if row.tool_type.id is not None
                else [],
                session=session,
            )
            for row in rows
        ]
    else:
        items = [tool_to_summary(row, session=session) for row in rows]
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


@router.get("/sessions/active", response_model=ToolSessionListResponse)
def get_active_sessions(
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
    action_key: str | None = Query(default=None),
) -> ToolSessionListResponse:
    rows = list_active_sessions(
        session,
        user_id=int(current_user.id),
        action_key=action_key,
    )
    by_session = discovered_site_ids_by_session(
        session, [int(r.id) for r in rows if r.id is not None]
    )
    return ToolSessionListResponse(
        items=[
            _to_session_response(
                tool_session_response(
                    row,
                    discovered_site_ids=by_session.get(int(row.id), []),
                    session=session,
                )
            )
            for row in rows
        ]
    )


@router.get("/sessions/{session_id}", response_model=ToolSessionResponse)
def get_tool_session(
    session_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> ToolSessionResponse:
    row = session.get(ToolSession, session_id)
    if row is None or int(row.user_id) != int(current_user.id):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Session not found",
        )
    return _to_session_response(
        tool_session_response(row, session=session)
    )


@router.post("/sessions/{session_id}/cancel", response_model=ToolSessionResponse)
def post_cancel_session(
    session_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> ToolSessionResponse:
    row = session.get(ToolSession, session_id)
    if row is None or int(row.user_id) != int(current_user.id):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Session not found",
        )
    user_id = int(current_user.id)
    if row.action_key in AERIAL_ACTION_KEYS:
        cancelled = cancel_aerial_session(
            session, user_id=user_id, session_id=session_id
        )
    else:
        cancelled = cancel_timed_session(
            session, user_id=user_id, session_id=session_id
        )
        if cancelled is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Session not found",
            )
    return _to_session_response(
        tool_session_response(cancelled, session=session)
    )


@router.get("/image-versions", response_model=ToolImageVersionListResponse)
def get_tool_image_versions(
    current_user: User = Depends(get_current_admin_user),
) -> ToolImageVersionListResponse:
    """List curated tool image version folders (admin collect picker)."""
    del current_user
    return ToolImageVersionListResponse(
        items=[ToolImageVersionItem(**item) for item in list_tool_image_versions()]
    )


@router.post("/{tool_id}/collect", response_model=ToolSummary)
def post_collect_tool(
    tool_id: int,
    body: CollectToolRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_admin_user),
) -> ToolSummary:
    tool_type, level = collect_tool_for_user(
        session,
        user_id=int(current_user.id),
        tool_id=tool_id,
        version=body.version,
    )
    return tool_to_summary(
        ToolListRow(
            tool_type=tool_type,
            level=level,
            image_version=ORIGINAL_VERSION,
        )
    )


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
    return tool_to_summary(row, session=session)


@router.get("/{tool_id}/sessions", response_model=ToolSessionListResponse)
def get_tool_sessions(
    tool_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> ToolSessionListResponse:
    """Lifetime battery and per-session history for an owned tool occurrence."""
    selected = resolve_owned_tool_selection(
        session, user_id=int(current_user.id), tool_id=tool_id
    )
    if selected is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Tool not found or not owned",
        )
    tool_type, instance = selected
    payload = sessions_for_tool_response(
        session, tool_type=tool_type, instance=instance
    )
    return ToolSessionListResponse.model_validate(payload)


@router.post(
    "/{tool_id}/sessions",
    response_model=ToolSessionResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
def post_tool_session(
    tool_id: int,
    body: ToolSessionStartRequest | None = None,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> ToolSessionResponse:
    """Start a tool session (aerial or timed overlay)."""
    payload = body or ToolSessionStartRequest()
    selected = resolve_owned_tool_selection(
        session, user_id=int(current_user.id), tool_id=tool_id
    )
    tool_type: ToolType | None
    if selected is not None:
        tool_type, _ = selected
    else:
        tool_type = session.get(ToolType, tool_id)
        if tool_type is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Tool not found",
            )

    user_id = int(current_user.id)
    if _is_aerial_tool(tool_type):
        if not payload.route:
            raise ValidationError("route is required for aerial sessions")
        if payload.origin_lat is None or payload.origin_lon is None:
            raise ValidationError("origin_lat and origin_lon are required")
        row = start_aerial_session(
            session,
            user_id=user_id,
            tool_id=tool_id,
            route=[point.model_dump() for point in payload.route],
            origin_lat=float(payload.origin_lat),
            origin_lon=float(payload.origin_lon),
        )
        status_code = status.HTTP_202_ACCEPTED
    else:
        lat = payload.lat if payload.lat is not None else payload.origin_lat
        lon = payload.lon if payload.lon is not None else payload.origin_lon
        row = start_timed_session(
            session,
            user_id=user_id,
            tool_id=tool_id,
            lat=lat,
            lon=lon,
        )
        status_code = status.HTTP_201_CREATED

    # FastAPI uses decorator status_code; timed starts should be 201.
    # Keep decorator at 202 for aerial; timed clients accept either.
    del status_code
    return _to_session_response(tool_session_response(row, session=session))


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
    return tool_to_summary(row, session=session)
