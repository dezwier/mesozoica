"""Update per-instance tool params (admin)."""

from __future__ import annotations

from fastapi import HTTPException, status
from sqlmodel import Session

from app.models.tool import Tool
from app.models.tool_type import ToolType
from app.features.tools.application.catalog.list import ToolListRow
from app.features.tools.application.catalog.params import (
    base_params_for_tool_type,
    effective_params_for_instance,
)


def update_tool_instance_params(
    session: Session,
    *,
    tool_id: int,
    params: dict,
) -> ToolListRow:
    """Merge and persist params for an owned Tool occurrence."""
    instance = session.get(Tool, tool_id)
    if instance is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Tool instance not found",
        )
    tool_type = session.get(ToolType, int(instance.tool_type_id))
    if tool_type is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Tool type not found",
        )
    merged = dict(base_params_for_tool_type(tool_type))
    merged.update(params)
    instance.params_json = merged
    session.add(instance)
    session.commit()
    session.refresh(instance)
    return ToolListRow(
        tool_type=tool_type,
        level=int(instance.level),
        occurrence_id=int(instance.id),
        params=effective_params_for_instance(tool_type, instance),
    )
