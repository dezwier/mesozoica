"""Tool read endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlmodel import Session

from app.core.database import get_session
from app.core.exceptions import ValidationError
from app.schemas.tool import ToolCategoryItem, ToolCategoryListResponse, ToolListResponse, ToolSummary
from app.services.tool_service import get_tool_by_id, list_tool_categories, list_tools

router = APIRouter(prefix="/tools", tags=["tools"])


@router.get("", response_model=ToolListResponse)
def get_tools(
    session: Session = Depends(get_session),
    limit: int = Query(default=200, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    sort: str = Query(default="category"),
    seed: str | None = Query(default=None),
    q: str | None = Query(default=None),
    category: list[str] | None = Query(default=None),
    has_custom_image: bool = Query(default=False),
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
    )
    items = [ToolSummary.model_validate(row) for row in rows]
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
) -> ToolCategoryListResponse:
    items = [
        ToolCategoryItem(value=value, label=label)
        for value, label in list_tool_categories(session)
    ]
    return ToolCategoryListResponse(items=items)


@router.get("/{tool_id}", response_model=ToolSummary)
def get_tool(
    tool_id: int,
    session: Session = Depends(get_session),
) -> ToolSummary:
    row = get_tool_by_id(session, tool_id)
    return ToolSummary.model_validate(row)
