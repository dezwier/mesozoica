"""Lifetime battery against tool_session rows."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from sqlmodel import Session, col, select

from app.core.exceptions import ValidationError
from app.models.tool import Tool
from app.models.tool_session import (
    AERIAL_ACTION_KEYS,
    LIVE_STATUSES,
    SESSION_STATUS_ACTIVE,
    SESSION_STATUS_PENDING,
    ToolSession,
)
from app.models.tool_type import ToolType
from app.features.tools.application.catalog.params import effective_params_for_instance


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def total_duration_s_for_instance(tool_type: ToolType, instance: Tool) -> int:
    params = effective_params_for_instance(tool_type, instance)
    minutes = params.get("duration_minutes") or 0
    return max(0, int(float(minutes) * 60))


def _parse_iso(value: Any) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.replace(tzinfo=None) if value.tzinfo else value
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00")).replace(
                tzinfo=None
            )
        except ValueError:
            return None
    return None


def _session_charge_s(row: ToolSession, *, now: datetime) -> int:
    if row.used_duration_s is not None:
        return max(0, int(row.used_duration_s))

    if row.action_key in AERIAL_ACTION_KEYS:
        state = row.state_json or {}
        flight_duration_s = int(state.get("flight_duration_s") or 0)
        started = _parse_iso(state.get("flight_started_at"))
        if row.status == SESSION_STATUS_PENDING:
            return max(0, flight_duration_s)
        if row.status == SESSION_STATUS_ACTIVE and started is not None:
            elapsed = max(0, int((now - started).total_seconds()))
            return min(elapsed, max(0, flight_duration_s))
        if started is None:
            return 0
        end = row.ended_at or _parse_iso(state.get("flight_ends_at")) or row.updated_at
        return max(0, int((end - started).total_seconds()))

    # Timed overlays
    if row.status in LIVE_STATUSES and row.expires_at is not None:
        allocated = max(0, int((row.expires_at - row.started_at).total_seconds()))
        elapsed = max(0, int((now - row.started_at).total_seconds()))
        return min(elapsed, allocated)
    end = row.ended_at or row.expires_at or row.updated_at
    return max(0, int((end - row.started_at).total_seconds()))


def used_duration_s_for_tool(
    session: Session,
    *,
    tool_id: int,
    now: datetime | None = None,
) -> int:
    clock = now or _utcnow()
    rows = session.exec(
        select(ToolSession).where(col(ToolSession.tool_id) == tool_id)
    ).all()
    return sum(_session_charge_s(row, now=clock) for row in rows)


def remaining_duration_s(
    session: Session,
    *,
    tool_type: ToolType,
    instance: Tool,
    now: datetime | None = None,
) -> int:
    total = total_duration_s_for_instance(tool_type, instance)
    used = used_duration_s_for_tool(
        session, tool_id=int(instance.id), now=now
    )
    return max(0, total - used)


def allocate_remaining_for_start(
    session: Session,
    *,
    tool_type: ToolType,
    instance: Tool,
    min_duration_minutes: int | None = None,
    now: datetime | None = None,
) -> int:
    clock = now or _utcnow()
    remaining = remaining_duration_s(
        session, tool_type=tool_type, instance=instance, now=clock
    )
    if remaining <= 0:
        raise ValidationError("No duration left on this tool card")
    if min_duration_minutes is not None:
        min_s = int(min_duration_minutes) * 60
        if remaining < min_s:
            raise ValidationError(
                f"Need at least {min_duration_minutes} minutes left on this tool card"
            )
    return remaining


def remaining_minutes_for_route(
    session: Session,
    *,
    tool_type: ToolType,
    instance: Tool,
    now: datetime | None = None,
) -> float:
    return remaining_duration_s(
        session, tool_type=tool_type, instance=instance, now=now
    ) / 60.0
