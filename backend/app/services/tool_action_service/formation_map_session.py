"""Formation Map sessions: timed rock-type square mosaic overlay."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError, ValidationError
from app.core.game_config import get_game_config
from app.models.formation_map_session import (
    ACTION_KEY_FORMATION_MAP,
    SESSION_STATUS_ACTIVE,
    SESSION_STATUS_CANCELLED,
    SESSION_STATUS_EXPIRED,
    FormationMapSession,
)
from app.models.tool_type import ToolType
from app.models.user_tool import USER_TOOL_ACTION_DEPLOYED, UserTool
from app.services.field_service.field_ensure_queue import enqueue_field_site_ensure
from app.services.tool_action_service.guidance_session import (
    cancel_active_guidance_sessions,
)
from app.services.site_common.survey_grid import (
    footprint_for_center,
    snap_to_cell_center,
    snap_wideness_m,
)
from app.services.tool_service.collect import resolve_owned_tool_selection

TOOL_NAME_FORMATION_MAP = "Formation Map"


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _expire_if_needed(session: Session, row: FormationMapSession) -> FormationMapSession:
    if row.status != SESSION_STATUS_ACTIVE:
        return row
    if row.expires_at <= _utcnow():
        row.status = SESSION_STATUS_EXPIRED
        row.updated_at = _utcnow()
        session.add(row)
        session.commit()
        session.refresh(row)
    return row


def get_active_formation_map_session(
    session: Session,
    *,
    user_id: int,
) -> FormationMapSession | None:
    row = session.exec(
        select(FormationMapSession)
        .where(
            col(FormationMapSession.user_id) == user_id,
            col(FormationMapSession.status) == SESSION_STATUS_ACTIVE,
        )
        .order_by(col(FormationMapSession.started_at).desc())
    ).first()
    if row is None:
        return None
    row = _expire_if_needed(session, row)
    if row.status != SESSION_STATUS_ACTIVE:
        return None
    return row


def cancel_active_formation_map_sessions(
    session: Session,
    *,
    user_id: int,
) -> None:
    now = _utcnow()
    rows = session.exec(
        select(FormationMapSession).where(
            col(FormationMapSession.user_id) == user_id,
            col(FormationMapSession.status) == SESSION_STATUS_ACTIVE,
        )
    ).all()
    for row in rows:
        row.status = SESSION_STATUS_CANCELLED
        row.cancelled_at = now
        row.updated_at = now
        session.add(row)
    if rows:
        session.commit()


def start_formation_map_session(
    session: Session,
    *,
    user_id: int,
    tool_id: int,
    lat: float | None = None,
    lon: float | None = None,
) -> FormationMapSession:
    """Validate ownership, snap/persist center on first use, snapshot knobs."""
    selected = resolve_owned_tool_selection(session, user_id=user_id, tool_id=tool_id)
    if selected is None:
        tool_type = session.get(ToolType, tool_id)
        if tool_type is None:
            raise NotFoundError(f"Tool {tool_id} not found")
        if tool_type.name != TOOL_NAME_FORMATION_MAP:
            raise ValidationError("This action is only available for Formation Map")
        raise ValidationError("You must own Formation Map to use it")
    tool_type, instance = selected
    if tool_type.name != TOOL_NAME_FORMATION_MAP:
        raise ValidationError("This action is only available for Formation Map")

    game = get_game_config()
    cfg = game.tool_actions.formation_map
    inst_p = dict(instance.params_json or {})

    # Same fixed world grid as field-site density (never a separate FM grid).
    cell_size = float(game.site_generation.lazy.cell_size_m)
    wideness = snap_wideness_m(
        float(inst_p.get("wideness_m", cfg.wideness_m)),
        cell_size_m=cell_size,
        min_wideness_m=float(inst_p.get("min_wideness_m", cfg.min_wideness_m)),
        max_wideness_m=float(inst_p.get("max_wideness_m", cfg.max_wideness_m)),
    )

    center_lat = inst_p.get("center_lat")
    center_lon = inst_p.get("center_lon")
    if center_lat is None or center_lon is None:
        if lat is None or lon is None:
            raise ValidationError(
                "GPS coordinates are required to place a new Formation Map"
            )
        center_lat, center_lon = snap_to_cell_center(
            float(lat), float(lon), cell_size_m=cell_size
        )
        inst_p["center_lat"] = float(center_lat)
        inst_p["center_lon"] = float(center_lon)
        inst_p["wideness_m"] = float(wideness)
        inst_p["cell_size_m"] = float(cell_size)
        instance.params_json = inst_p
        session.add(instance)
    else:
        center_lat = float(center_lat)
        center_lon = float(center_lon)
        # Normalize stored center onto the shared density grid.
        center_lat, center_lon = snap_to_cell_center(
            center_lat, center_lon, cell_size_m=cell_size
        )
        inst_p["cell_size_m"] = float(cell_size)
        instance.params_json = inst_p
        session.add(instance)

    footprint = footprint_for_center(
        float(center_lat),
        float(center_lon),
        wideness_m=wideness,
        cell_size_m=cell_size,
    )

    # Top up every density cell covered by the map (deduped by cell_key).
    for cell_lat, cell_lon in footprint.cell_centers():
        enqueue_field_site_ensure(
            session,
            lat=cell_lat,
            lon=cell_lon,
            reason=ACTION_KEY_FORMATION_MAP,
        )

    cancel_active_formation_map_sessions(session, user_id=user_id)
    # Late import avoids cycle with orbit_survey_session.
    from app.services.tool_action_service.orbit_survey_session import (
        cancel_active_orbit_survey_sessions,
    )

    cancel_active_orbit_survey_sessions(session, user_id=user_id)
    cancel_active_guidance_sessions(session, user_id=user_id)
    from app.services.tool_action_service.terrain_echo_session import (
        cancel_active_terrain_echo_sessions,
    )

    cancel_active_terrain_echo_sessions(session, user_id=user_id)

    now = _utcnow()
    eff_duration = int(inst_p.get("duration_minutes", cfg.duration_minutes))
    row = FormationMapSession(
        user_id=user_id,
        tool_id=int(instance.id),
        action_key=ACTION_KEY_FORMATION_MAP,
        status=SESSION_STATUS_ACTIVE,
        duration_minutes=eff_duration,
        accuracy=float(inst_p.get("accuracy", cfg.accuracy)),
        wideness_m=float(footprint.wideness_m),
        cell_size_m=float(cell_size),
        center_lat=float(footprint.center_lat),
        center_lon=float(footprint.center_lon),
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


def cancel_formation_map_session(
    session: Session,
    *,
    user_id: int,
    session_id: int | None = None,
) -> FormationMapSession | None:
    if session_id is not None:
        row = session.get(FormationMapSession, session_id)
        if row is None or int(row.user_id) != user_id:
            raise NotFoundError(f"Formation map session {session_id} not found")
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

    row = get_active_formation_map_session(session, user_id=user_id)
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
