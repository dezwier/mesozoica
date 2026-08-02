"""Close-out and cancel helpers for tool sessions."""

from __future__ import annotations

from datetime import datetime, timezone

from sqlmodel import Session, col, select

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
    row.status = SESSION_STATUS_COMPLETED
    close_session(row, now=now, stop_reason=STOP_REASON_EXHAUSTED)
    session.add(row)
    session.commit()
    session.refresh(row)
    return row


def cancel_live_timed_sessions(session: Session, *, user_id: int) -> None:
    """Cancel all live timed overlay sessions for mutual exclusivity."""
    now = _utcnow()
    rows = session.exec(
        select(ToolSession).where(
            col(ToolSession.user_id) == user_id,
            col(ToolSession.action_key).in_(TIMED_OVERLAY_ACTION_KEYS),
            col(ToolSession.status).in_(LIVE_STATUSES),
        )
    ).all()
    for row in rows:
        row.status = SESSION_STATUS_CANCELLED
        close_session(row, now=now, stop_reason=STOP_REASON_MANUAL)
        session.add(row)
    if rows:
        session.commit()
