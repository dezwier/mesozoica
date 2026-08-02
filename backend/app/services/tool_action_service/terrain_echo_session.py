"""Terrain Echo sessions: timed vintage radar overlay."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError, ValidationError
from app.core.game_config import get_game_config
from app.models.terrain_echo_session import (
    ACTION_KEY_TERRAIN_ECHO,
    SESSION_STATUS_ACTIVE,
    SESSION_STATUS_CANCELLED,
    SESSION_STATUS_EXPIRED,
    TerrainEchoSession,
)
from app.models.tool_type import ToolType
from app.models.user_tool import USER_TOOL_ACTION_DEPLOYED, UserTool
from app.services.tool_action_service.guidance_session import (
    cancel_active_guidance_sessions,
)
from app.services.tool_service.collect import resolve_owned_tool_selection

TOOL_NAME_TERRAIN_ECHO = "Terrain Echo"


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _expire_if_needed(session: Session, row: TerrainEchoSession) -> TerrainEchoSession:
    if row.status != SESSION_STATUS_ACTIVE:
        return row
    if row.expires_at <= _utcnow():
        row.status = SESSION_STATUS_EXPIRED
        row.updated_at = _utcnow()
        session.add(row)
        session.commit()
        session.refresh(row)
    return row


def get_active_terrain_echo_session(
    session: Session,
    *,
    user_id: int,
) -> TerrainEchoSession | None:
    """Return the user's active (non-expired) terrain echo session, if any."""
    row = session.exec(
        select(TerrainEchoSession)
        .where(
            col(TerrainEchoSession.user_id) == user_id,
            col(TerrainEchoSession.status) == SESSION_STATUS_ACTIVE,
        )
        .order_by(col(TerrainEchoSession.started_at).desc())
    ).first()
    if row is None:
        return None
    row = _expire_if_needed(session, row)
    if row.status != SESSION_STATUS_ACTIVE:
        return None
    return row


def cancel_active_terrain_echo_sessions(
    session: Session,
    *,
    user_id: int,
) -> None:
    now = _utcnow()
    rows = session.exec(
        select(TerrainEchoSession).where(
            col(TerrainEchoSession.user_id) == user_id,
            col(TerrainEchoSession.status) == SESSION_STATUS_ACTIVE,
        )
    ).all()
    for row in rows:
        row.status = SESSION_STATUS_CANCELLED
        row.cancelled_at = now
        row.updated_at = now
        session.add(row)
    if rows:
        session.commit()


def start_terrain_echo_session(
    session: Session,
    *,
    user_id: int,
    tool_id: int,
) -> TerrainEchoSession:
    """Validate ownership, replace any prior session, snapshot YAML knobs.

    ``tool_id`` is the catalog tool_type id (API-stable). The session row stores
    the owned tool instance id.
    """
    selected = resolve_owned_tool_selection(session, user_id=user_id, tool_id=tool_id)
    if selected is None:
        tool_type = session.get(ToolType, tool_id)
        if tool_type is None:
            raise NotFoundError(f"Tool {tool_id} not found")
        if tool_type.name != TOOL_NAME_TERRAIN_ECHO:
            raise ValidationError("This action is only available for Terrain Echo")
        raise ValidationError("You must own Terrain Echo to use it")
    tool_type, instance = selected
    if tool_type.name != TOOL_NAME_TERRAIN_ECHO:
        raise ValidationError("This action is only available for Terrain Echo")

    cfg = get_game_config().tool_actions.terrain_echo

    cancel_active_terrain_echo_sessions(session, user_id=user_id)
    cancel_active_guidance_sessions(session, user_id=user_id)
    from app.services.tool_action_service.formation_map_session import (
        cancel_active_formation_map_sessions,
    )
    from app.services.tool_action_service.orbit_survey_session import (
        cancel_active_orbit_survey_sessions,
    )

    cancel_active_orbit_survey_sessions(session, user_id=user_id)
    cancel_active_formation_map_sessions(session, user_id=user_id)

    inst_p = instance.params_json or {}
    now = _utcnow()
    eff_duration = int(inst_p.get("duration_minutes", cfg.duration_minutes))
    row = TerrainEchoSession(
        user_id=user_id,
        tool_id=int(instance.id),
        action_key=ACTION_KEY_TERRAIN_ECHO,
        status=SESSION_STATUS_ACTIVE,
        duration_minutes=eff_duration,
        degrees=float(inst_p.get("degrees", cfg.degrees)),
        accuracy=float(inst_p.get("accuracy", cfg.accuracy)),
        range_m=float(inst_p.get("range_m", cfg.range_m)),
        started_at=now,
        expires_at=now + timedelta(minutes=eff_duration),
        created_at=now,
        updated_at=now,
    )
    session.add(row)
    session.add(
        UserTool(
            user_id=user_id,
            tool_id=int(instance.id),
            timestamp=datetime.now(timezone.utc),
            action=USER_TOOL_ACTION_DEPLOYED,
        )
    )
    session.commit()
    session.refresh(row)
    return row


def cancel_terrain_echo_session(
    session: Session,
    *,
    user_id: int,
    session_id: int | None = None,
) -> TerrainEchoSession | None:
    """Cancel the active session (or a specific session_id owned by the user)."""
    if session_id is not None:
        row = session.get(TerrainEchoSession, session_id)
        if row is None or int(row.user_id) != user_id:
            raise NotFoundError(f"Terrain echo session {session_id} not found")
        row = _expire_if_needed(session, row)
        if row.status == SESSION_STATUS_ACTIVE:
            now = _utcnow()
            row.status = SESSION_STATUS_CANCELLED
            row.cancelled_at = now
            row.updated_at = now
            session.add(row)
            session.commit()
            session.refresh(row)
        return row

    row = get_active_terrain_echo_session(session, user_id=user_id)
    if row is None:
        return None
    now = _utcnow()
    row.status = SESSION_STATUS_CANCELLED
    row.cancelled_at = now
    row.updated_at = now
    session.add(row)
    session.commit()
    session.refresh(row)
    return row
