"""Serialize ToolSession rows into API response dicts."""

from __future__ import annotations

from typing import Any

from sqlmodel import Session, col, select

from app.models.tool_session import AERIAL_ACTION_KEYS, ToolSession
from app.models.tool_session_event import (
    EVENT_STATUS_DONE,
    EVENT_STATUS_MISS,
    EVENT_STATUS_PENDING,
    EVENT_TYPE_DISCOVER_SITE,
    ToolSessionEvent,
)


def discovered_site_ids_by_session(
    session: Session,
    session_ids: list[int],
) -> dict[int, list[int]]:
    """Site IDs from successful discover events, keyed by session_id."""
    if not session_ids:
        return {}
    rows = session.exec(
        select(ToolSessionEvent.session_id, ToolSessionEvent.site_id).where(
            col(ToolSessionEvent.session_id).in_(session_ids),
            col(ToolSessionEvent.event_type) == EVENT_TYPE_DISCOVER_SITE,
            col(ToolSessionEvent.status) == EVENT_STATUS_DONE,
            col(ToolSessionEvent.site_id).is_not(None),
        )
    ).all()
    by_session: dict[int, list[int]] = {sid: [] for sid in session_ids}
    for session_id, site_id in rows:
        if site_id is None:
            continue
        by_session.setdefault(int(session_id), []).append(int(site_id))
    return by_session


def _events_summary(
    session: Session | None,
    row: ToolSession,
    *,
    discovered_site_ids: list[int] | None,
) -> dict[str, Any]:
    site_ids = discovered_site_ids
    pending_count = 0
    miss_count = 0
    done_count = 0

    if session is not None and row.id is not None:
        events = list(
            session.exec(
                select(ToolSessionEvent).where(
                    col(ToolSessionEvent.session_id) == row.id,
                    col(ToolSessionEvent.event_type) == EVENT_TYPE_DISCOVER_SITE,
                )
            ).all()
        )
        if site_ids is None:
            site_ids = [
                int(e.site_id)
                for e in events
                if e.status == EVENT_STATUS_DONE and e.site_id is not None
            ]
        pending_count = sum(1 for e in events if e.status == EVENT_STATUS_PENDING)
        miss_count = sum(1 for e in events if e.status == EVENT_STATUS_MISS)
        done_count = sum(1 for e in events if e.status == EVENT_STATUS_DONE)
    elif site_ids is None:
        site_ids = []

    return {
        "discovered_site_ids": site_ids,
        "discovered_count": len(site_ids),
        "pending_count": pending_count,
        "miss_count": miss_count,
        "done_count": done_count,
    }


def tool_session_response(
    row: ToolSession,
    *,
    discovered_site_ids: list[int] | None = None,
    session: Session | None = None,
) -> dict[str, Any]:
    """Dict matching the ToolSession API schema."""
    is_aerial = row.action_key in AERIAL_ACTION_KEYS
    summary = (
        _events_summary(session, row, discovered_site_ids=discovered_site_ids)
        if is_aerial
        else {
            "discovered_site_ids": discovered_site_ids or [],
            "discovered_count": len(discovered_site_ids or []),
            "pending_count": 0,
            "miss_count": 0,
            "done_count": 0,
        }
    )
    return {
        "session_id": int(row.id),
        "tool_id": int(row.tool_id),
        "action_key": row.action_key,
        "status": row.status,
        "started_at": row.started_at,
        "expires_at": row.expires_at,
        "ended_at": row.ended_at,
        "used_duration_s": row.used_duration_s,
        "stop_reason": row.stop_reason,
        "params": dict(row.params_json or {}),
        "state": dict(row.state_json or {}),
        "events_summary": summary,
        "created_at": row.created_at,
        "updated_at": row.updated_at,
    }
