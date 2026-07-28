"""Admin collect helper: spawn a tool instance and record ownership."""

from __future__ import annotations

from datetime import datetime, timezone

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError
from app.models.tool import Tool
from app.models.tool_type import ToolType
from app.models.user_tool import USER_TOOL_ACTION_OWNED, UserTool


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _owned_instance_for_type(
    session: Session,
    *,
    user_id: int,
    tool_type_id: int,
) -> Tool | None:
    """Return the user's owned instance for a type (highest level, then newest)."""
    rows = session.exec(
        select(Tool)
        .join(UserTool, col(UserTool.tool_id) == col(Tool.id))
        .where(
            col(UserTool.user_id) == user_id,
            col(UserTool.action) == USER_TOOL_ACTION_OWNED,
            col(Tool.tool_type_id) == tool_type_id,
        )
        .order_by(col(Tool.level).desc(), col(Tool.spawn_date).desc())
    ).all()
    return rows[0] if rows else None


def collect_tool_for_user(
    session: Session,
    *,
    user_id: int,
    tool_id: int,
) -> tuple[ToolType, int]:
    """Ensure the user owns an instance of catalog ``tool_id`` (tool_type id).

    Idempotent: if already owned, returns the existing instance level unchanged.
    """
    tool_type = session.get(ToolType, tool_id)
    if tool_type is None:
        raise NotFoundError(f"Tool {tool_id} not found")

    existing = _owned_instance_for_type(
        session, user_id=user_id, tool_type_id=tool_id
    )
    if existing is not None:
        return tool_type, int(existing.level)

    now = _utc_now()
    instance = Tool(tool_type_id=tool_id, spawn_date=now, level=1)
    session.add(instance)
    session.flush()
    session.add(
        UserTool(
            user_id=user_id,
            tool_id=int(instance.id),
            timestamp=now,
            action=USER_TOOL_ACTION_OWNED,
        )
    )
    session.commit()
    session.refresh(instance)
    return tool_type, int(instance.level)


def ownership_levels_for_tool_types(
    session: Session,
    *,
    user_id: int,
    tool_type_ids: list[int],
) -> dict[int, int]:
    """Map tool_type_id → level for the given user among ``tool_type_ids``.

    When multiple instances exist for a type, the highest level wins.
    """
    if not tool_type_ids:
        return {}
    rows = session.exec(
        select(Tool.tool_type_id, Tool.level)
        .join(UserTool, col(UserTool.tool_id) == col(Tool.id))
        .where(
            col(UserTool.user_id) == user_id,
            col(UserTool.action) == USER_TOOL_ACTION_OWNED,
            col(Tool.tool_type_id).in_(tool_type_ids),
        )
    ).all()
    levels: dict[int, int] = {}
    for tool_type_id, level in rows:
        tid = int(tool_type_id)
        lvl = int(level)
        if tid not in levels or lvl > levels[tid]:
            levels[tid] = lvl
    return levels


def resolve_owned_instance(
    session: Session,
    *,
    user_id: int,
    tool_type_id: int,
) -> Tool | None:
    """Public helper: owned instance for a catalog tool type, if any."""
    return _owned_instance_for_type(
        session, user_id=user_id, tool_type_id=tool_type_id
    )


# Back-compat alias used by older call sites / tests.
ownership_levels_for_tools = ownership_levels_for_tool_types
