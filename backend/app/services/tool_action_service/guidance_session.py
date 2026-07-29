"""Site-guidance sessions: timed overlays + nearest-site discovery boost."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError, ValidationError
from app.core.game_config import get_game_config
from app.models.guidance_session import (
    SESSION_STATUS_ACTIVE,
    SESSION_STATUS_CANCELLED,
    SESSION_STATUS_EXPIRED,
    GuidanceSession,
)
from app.models.tool_type import ToolType
from app.models.user_tool import USER_TOOL_ACTION_DEPLOYED, UserTool
from app.services.site_service.geo_utils import haversine_km
from app.services.site_service.nearby import list_discoverable_sites_in_radius
from app.services.tool_action_service.guidance_kinds import (
    config_for_action_key,
    kind_for_tool_name,
)
from app.services.tool_service.collect import resolve_owned_tool_selection

def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _expire_if_needed(session: Session, row: GuidanceSession) -> GuidanceSession:
    if row.status != SESSION_STATUS_ACTIVE:
        return row
    if row.expires_at <= _utcnow():
        row.status = SESSION_STATUS_EXPIRED
        row.updated_at = _utcnow()
        session.add(row)
        session.commit()
        session.refresh(row)
    return row


def get_active_guidance_session(
    session: Session,
    *,
    user_id: int,
) -> GuidanceSession | None:
    """Return the user's active (non-expired) guidance session, if any."""
    row = session.exec(
        select(GuidanceSession)
        .where(
            col(GuidanceSession.user_id) == user_id,
            col(GuidanceSession.status) == SESSION_STATUS_ACTIVE,
        )
        .order_by(col(GuidanceSession.started_at).desc())
    ).first()
    if row is None:
        return None
    row = _expire_if_needed(session, row)
    if row.status != SESSION_STATUS_ACTIVE:
        return None
    return row


def cancel_active_guidance_sessions(
    session: Session,
    *,
    user_id: int,
) -> None:
    now = _utcnow()
    rows = session.exec(
        select(GuidanceSession).where(
            col(GuidanceSession.user_id) == user_id,
            col(GuidanceSession.status) == SESSION_STATUS_ACTIVE,
        )
    ).all()
    for row in rows:
        row.status = SESSION_STATUS_CANCELLED
        row.cancelled_at = now
        row.updated_at = now
        session.add(row)
    if rows:
        session.commit()


def start_guidance_session(
    session: Session,
    *,
    user_id: int,
    tool_id: int,
) -> GuidanceSession:
    """Validate ownership, replace any prior session, snapshot YAML knobs.

    ``tool_id`` is the catalog tool_type id (API-stable). The session row stores
    the owned tool instance id.
    """
    selected = resolve_owned_tool_selection(session, user_id=user_id, tool_id=tool_id)
    if selected is None:
        tool_type = session.get(ToolType, tool_id)
        if tool_type is None:
            raise NotFoundError(f"Tool {tool_id} not found")
        kind = kind_for_tool_name(tool_type.name)
        raise ValidationError(f"You must own {kind.display_label} to use it")
    tool_type, instance = selected
    kind = kind_for_tool_name(tool_type.name)
    cfg = config_for_action_key(kind.action_key)

    cancel_active_guidance_sessions(session, user_id=user_id)
    # Mutual exclusivity with Formation Map (competing map HUDs).
    from app.services.tool_action_service.formation_map_session import (
        cancel_active_formation_map_sessions,
    )

    cancel_active_formation_map_sessions(session, user_id=user_id)

    inst_p = instance.params_json or {}
    now = _utcnow()
    raw_chance = inst_p.get("discovery_chance", cfg.discovery_chance)
    discovery_chance = (
        float(raw_chance)
        if kind.has_discovery_boost and raw_chance is not None
        else None
    )
    # Keep parity with `GuidanceActionConfig.resolved_*_exactness()`, but with
    # instance-level overrides taking precedence.
    direction_raw = (
        inst_p.get("direction_exactness")
        if inst_p.get("direction_exactness") is not None
        else inst_p.get("exactness")
    )
    distance_raw = (
        inst_p.get("distance_exactness")
        if inst_p.get("distance_exactness") is not None
        else inst_p.get("exactness")
    )
    direction_exactness = (
        float(direction_raw)
        if kind.show_needle and direction_raw is not None
        else (
            float(cfg.resolved_direction_exactness())
            if kind.show_needle
            else None
        )
    )
    distance_exactness = (
        float(distance_raw)
        if kind.show_distance and distance_raw is not None
        else (
            float(cfg.resolved_distance_exactness())
            if kind.show_distance
            else None
        )
    )
    eff_duration = int(inst_p.get("duration_minutes", cfg.duration_minutes))
    row = GuidanceSession(
        user_id=user_id,
        tool_id=int(instance.id),
        action_key=kind.action_key,
        status=SESSION_STATUS_ACTIVE,
        discovery_chance=discovery_chance,
        direction_exactness=direction_exactness,
        distance_exactness=distance_exactness,
        duration_minutes=eff_duration,
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


def cancel_guidance_session(
    session: Session,
    *,
    user_id: int,
    session_id: int | None = None,
) -> GuidanceSession | None:
    """Cancel the active session (or a specific session_id owned by the user)."""
    if session_id is not None:
        row = session.get(GuidanceSession, session_id)
        if row is None or int(row.user_id) != user_id:
            raise NotFoundError(f"Guidance session {session_id} not found")
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

    row = get_active_guidance_session(session, user_id=user_id)
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


def nearest_discoverable_site_id(
    session: Session,
    *,
    user_id: int,
    lat: float,
    lon: float,
) -> int | None:
    """Id of the nearest still-discoverable field site, or None."""
    radius_km = float(get_game_config().site_discovery.client.cache_radius_km)
    rows = list_discoverable_sites_in_radius(
        session,
        lat=lat,
        lon=lon,
        radius_km=radius_km,
        user_id=user_id,
    )
    best_id: int | None = None
    best_km = float("inf")
    for row in rows:
        site = row.site
        if site.latitude is None or site.longitude is None:
            continue
        dist = haversine_km(
            lat, lon, float(site.latitude), float(site.longitude)
        )
        if dist < best_km:
            best_km = dist
            best_id = int(site.site_id)
    return best_id
