"""Admin collect helper: add a tool card to the current user's collection."""

from __future__ import annotations

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError
from app.models.tool import Tool
from app.models.user_tool import UserTool


def collect_tool_for_user(
    session: Session,
    *,
    user_id: int,
    tool_id: int,
) -> tuple[Tool, int]:
    """Ensure ``user_tool`` exists for ``(user_id, tool_id)`` at level 1.

    Idempotent: if already owned, returns the existing level unchanged.
    """
    tool = session.get(Tool, tool_id)
    if tool is None:
        raise NotFoundError(f"Tool {tool_id} not found")

    existing = session.exec(
        select(UserTool).where(
            col(UserTool.user_id) == user_id,
            col(UserTool.tool_id) == tool_id,
        )
    ).first()
    if existing is not None:
        return tool, int(existing.level)

    row = UserTool(user_id=user_id, tool_id=tool_id, level=1)
    session.add(row)
    session.commit()
    session.refresh(row)
    return tool, int(row.level)


def ownership_levels_for_tools(
    session: Session,
    *,
    user_id: int,
    tool_ids: list[int],
) -> dict[int, int]:
    """Map tool_id → level for the given user among ``tool_ids``."""
    if not tool_ids:
        return {}
    rows = session.exec(
        select(UserTool).where(
            col(UserTool.user_id) == user_id,
            col(UserTool.tool_id).in_(tool_ids),
        )
    ).all()
    return {int(row.tool_id): int(row.level) for row in rows}
