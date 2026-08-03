"""Close-out and cancel helpers for tool sessions."""

from __future__ import annotations

from datetime import datetime, timezone

from sqlmodel import Session, col, select

from app.core.exceptions import ValidationError
from app.models.tool_session import (
    AERIAL_ACTION_KEYS,
    LIVE_STATUSES,
    SESSION_STATUS_ACTIVE,
    SESSION_STATUS_CANCELLED,
    SESSION_STATUS_COMPLETED,
    STOP_REASON_EXHAUSTED,
    STOP_REASON_MANUAL,
    TIMED_OVERLAY_ACTION_KEYS,
    ToolSession,
)


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def close_session(
    row: ToolSession,
    *,
    now: datetime,
    stop_reason: str,
) -> None:
    if row.used_duration_s is not None:
        return

    from app.services.tool_action_service.tool_session.budget import _parse_iso

    state = row.state_json or {}
    is_aerial = row.action_key in AERIAL_ACTION_KEYS

    if stop_reason == STOP_REASON_MANUAL:
        end = now
        if is_aerial:
            flight_started = _parse_iso(state.get("flight_started_at"))
            if flight_started is None:
                elapsed = 0
            else:
                elapsed = max(0, int((end - flight_started).total_seconds()))
        else:
            elapsed = max(0, int((end - row.started_at).total_seconds()))
    else:
        # Exhausted / failed natural close.
        if is_aerial:
            elapsed = max(0, int(state.get("flight_duration_s") or 0))
            end = row.ended_at or _parse_iso(state.get("flight_ends_at")) or now
        elif row.expires_at is not None:
            end = row.expires_at if row.expires_at <= now else now
            elapsed = max(
                0, int((row.expires_at - row.started_at).total_seconds())
            )
        else:
            end = now
            elapsed = max(0, int((end - row.started_at).total_seconds()))

    row.ended_at = end
    row.used_duration_s = elapsed
    row.stop_reason = stop_reason
    row.updated_at = now


def expire_if_needed(session: Session, row: ToolSession) -> ToolSession:
    if row.status != SESSION_STATUS_ACTIVE:
        return row
    if row.expires_at is None or row.expires_at > _utcnow():
        return row
    now = _utcnow()
    from app.services.tool_action_service.disguise_session import (
        clear_disguiser_link_for_session,
    )

    clear_disguiser_link_for_session(session, row)
    row.status = SESSION_STATUS_COMPLETED
    close_session(row, now=now, stop_reason=STOP_REASON_EXHAUSTED)
    session.add(row)
    session.commit()
    session.refresh(row)
    return row


def cancel_live_timed_sessions(session: Session, *, user_id: int) -> None:
    """Cancel all live timed overlay sessions (legacy helper / tests)."""
    now = _utcnow()
    rows = session.exec(
        select(ToolSession).where(
            col(ToolSession.user_id) == user_id,
            col(ToolSession.action_key).in_(TIMED_OVERLAY_ACTION_KEYS),
            col(ToolSession.status).in_(LIVE_STATUSES),
        )
    ).all()
    from app.services.tool_action_service.disguise_session import (
        clear_disguiser_link_for_session,
    )

    for row in rows:
        clear_disguiser_link_for_session(session, row)
        row.status = SESSION_STATUS_CANCELLED
        close_session(row, now=now, stop_reason=STOP_REASON_MANUAL)
        session.add(row)
    if rows:
        session.commit()


def cancel_live_sessions_for_tool(
    session: Session,
    *,
    user_id: int,
    tool_id: int,
) -> None:
    """Cancel every live session for a user+tool occurrence (discard path)."""
    now = _utcnow()
    rows = list(
        session.exec(
            select(ToolSession).where(
                col(ToolSession.user_id) == user_id,
                col(ToolSession.tool_id) == tool_id,
                col(ToolSession.status).in_(LIVE_STATUSES),
            )
        ).all()
    )
    if not rows:
        return

    from app.models.tool_session_event import (
        EVENT_STATUS_PENDING,
        EVENT_STATUS_SKIPPED,
        ToolSessionEvent,
    )

    for row in rows:
        if row.action_key in AERIAL_ACTION_KEYS:
            pending = list(
                session.exec(
                    select(ToolSessionEvent).where(
                        col(ToolSessionEvent.session_id) == row.id,
                        col(ToolSessionEvent.status) == EVENT_STATUS_PENDING,
                    )
                ).all()
            )
            for event in pending:
                event.status = EVENT_STATUS_SKIPPED
                session.add(event)
        from app.services.tool_action_service.disguise_session import (
            clear_disguiser_link_for_session,
        )

        clear_disguiser_link_for_session(session, row)
        row.status = SESSION_STATUS_CANCELLED
        close_session(row, now=now, stop_reason=STOP_REASON_MANUAL)
        session.add(row)
    session.commit()


def _tool_display_name(session: Session, *, instance_id: int) -> str:
    from app.models.tool import Tool
    from app.models.tool_type import ToolType

    instance = session.get(Tool, instance_id)
    if instance is None:
        return "Another tool"
    tool_type = session.get(ToolType, int(instance.tool_type_id))
    if tool_type is None or not tool_type.name:
        return "Another tool"
    return str(tool_type.name)


def ensure_exclusive_tool_session(
    session: Session,
    *,
    user_id: int,
    instance_id: int,
) -> None:
    """Enforce one live tool card at a time.

    Any live session (including this same card) raises with that card's name.
    """
    rows = list(
        session.exec(
            select(ToolSession).where(
                col(ToolSession.user_id) == user_id,
                col(ToolSession.status).in_(LIVE_STATUSES),
            )
        ).all()
    )
    for row in rows:
        refreshed = expire_if_needed(session, row)
        if refreshed.status not in LIVE_STATUSES:
            continue
        name = _tool_display_name(session, instance_id=int(refreshed.tool_id))
        raise ValidationError(f"{name} is already in use")
