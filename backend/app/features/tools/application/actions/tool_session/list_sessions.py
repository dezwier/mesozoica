"""List tool sessions for a card or active sessions for a user."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from sqlmodel import Session, col, select

from app.models.tool import Tool
from app.models.tool_session import LIVE_STATUSES, ToolSession
from app.models.tool_type import ToolType
from app.models.user_tool import (
    USER_TOOL_ACTION_DEPLOYED,
    USER_TOOL_ACTION_USED,
    UserTool,
)
from app.features.tools.application.actions.tool_session.budget import (
    remaining_duration_s,
    total_duration_s_for_instance,
    used_duration_s_for_tool,
)
from app.features.tools.application.actions.tool_session.lifecycle import expire_if_needed
from app.features.tools.application.actions.tool_session.serialize import (
    discovered_site_ids_by_session,
    tool_session_response,
)

# Usage is represented by tool_session rows; skip these user_tool mirrors.
_USAGE_USER_TOOL_ACTIONS = frozenset(
    {USER_TOOL_ACTION_DEPLOYED, USER_TOOL_ACTION_USED}
)


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _naive_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value
    return value.astimezone(timezone.utc).replace(tzinfo=None)


def list_sessions_for_tool(
    session: Session,
    *,
    tool_id: int,
) -> list[ToolSession]:
    """All sessions for a tool occurrence, newest first."""
    return list(
        session.exec(
            select(ToolSession)
            .where(col(ToolSession.tool_id) == tool_id)
            .order_by(col(ToolSession.started_at).desc())
        ).all()
    )


def list_role_events_for_tool(
    session: Session,
    *,
    tool_id: int,
) -> list[UserTool]:
    """Role-change user_tool rows for a tool occurrence (excludes use mirrors)."""
    rows = session.exec(
        select(UserTool)
        .where(col(UserTool.tool_id) == tool_id)
        .order_by(col(UserTool.timestamp).desc())
    ).all()
    return [row for row in rows if row.action not in _USAGE_USER_TOOL_ACTIONS]


def list_active_sessions(
    session: Session,
    *,
    user_id: int,
    action_key: str | None = None,
) -> list[ToolSession]:
    """Live sessions for [user_id], optionally filtered by action_key."""
    query = select(ToolSession).where(
        col(ToolSession.user_id) == user_id,
        col(ToolSession.status).in_(LIVE_STATUSES),
    )
    if action_key is not None:
        query = query.where(col(ToolSession.action_key) == action_key)
    rows = list(
        session.exec(query.order_by(col(ToolSession.started_at).desc())).all()
    )
    live: list[ToolSession] = []
    for row in rows:
        refreshed = expire_if_needed(session, row)
        if refreshed.status in LIVE_STATUSES:
            live.append(refreshed)
    return live


def sessions_for_tool_response(
    session: Session,
    *,
    tool_type: ToolType,
    instance: Tool,
) -> dict[str, Any]:
    """History + battery totals for GET /tools/{id}/sessions."""
    now = _utcnow()
    total = total_duration_s_for_instance(tool_type, instance)
    used = used_duration_s_for_tool(
        session, tool_id=int(instance.id), now=now
    )
    remaining = remaining_duration_s(
        session, tool_type=tool_type, instance=instance, now=now
    )
    rows = list_sessions_for_tool(session, tool_id=int(instance.id))
    by_session = discovered_site_ids_by_session(
        session, [int(r.id) for r in rows if r.id is not None]
    )
    session_items = [
        tool_session_response(
            row,
            discovered_site_ids=by_session.get(int(row.id), []),
            session=session,
        )
        for row in rows
    ]

    history: list[dict[str, Any]] = []
    for row, payload in zip(rows, session_items, strict=True):
        history.append(
            {
                "kind": "session",
                "at": row.started_at,
                "session": payload,
                "role": None,
            }
        )
    for role in list_role_events_for_tool(session, tool_id=int(instance.id)):
        history.append(
            {
                "kind": "role",
                "at": _naive_utc(role.timestamp),
                "session": None,
                "role": {
                    "action": role.action,
                    "at": _naive_utc(role.timestamp),
                },
            }
        )
    history.sort(key=lambda entry: entry["at"], reverse=True)

    return {
        "tool_id": int(instance.id),
        "total_duration_s": total,
        "used_duration_s": used,
        "remaining_duration_s": remaining,
        "items": session_items,
        "history": history,
    }
