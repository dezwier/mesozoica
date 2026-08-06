"""Discard a tool inventory occurrence for the acting user."""

from __future__ import annotations

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError
from app.models.tool import Tool
from app.models.user_tool import UserTool
from app.features.tools.application.actions.tool_session.lifecycle import (
    cancel_live_sessions_for_tool,
)


def discard_tool_for_user(
    session: Session,
    *,
    tool_id: int,
    user_id: int,
) -> None:
    """Delete the caller's ``user_tool`` rows for a tool occurrence.

    Also cancels any live ``tool_session`` for that user+tool so the HUD
    cannot keep a discarded tool active. Idempotent when the caller has no
    links. The tool occurrence row is kept.
    """
    tool = session.get(Tool, tool_id)
    if tool is None:
        raise NotFoundError(f"Tool {tool_id} not found")

    cancel_live_sessions_for_tool(
        session, user_id=user_id, tool_id=tool_id
    )

    rows = session.exec(
        select(UserTool).where(
            col(UserTool.user_id) == user_id,
            col(UserTool.tool_id) == tool_id,
        )
    ).all()
    for row in rows:
        session.delete(row)
    if rows:
        session.commit()
