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
from app.models.tool import Tool
from app.models.user_tool import UserTool
from app.services.site_service.geo_utils import haversine_km
from app.services.site_service.nearby import list_discoverable_sites_in_radius
from app.services.tool_action_service.guidance_kinds import (
    config_for_action_key,
    kind_for_tool_name,
)


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
    """Validate ownership, replace any prior session, snapshot YAML knobs."""
    tool = session.get(Tool, tool_id)
    if tool is None:
        raise NotFoundError(f"Tool {tool_id} not found")
    kind = kind_for_tool_name(tool.name)
    cfg = config_for_action_key(kind.action_key)

    owned = session.exec(
        select(UserTool).where(
            col(UserTool.user_id) == user_id,
            col(UserTool.tool_id) == tool_id,
        )
    ).first()
    if owned is None:
        raise ValidationError(f"You must own {kind.display_label} to use it")

    cancel_active_guidance_sessions(session, user_id=user_id)

    now = _utcnow()
    discovery_chance = (
        float(cfg.discovery_chance)
        if kind.has_discovery_boost and cfg.discovery_chance is not None
        else None
    )
    direction_exactness = (
        cfg.resolved_direction_exactness() if kind.show_needle else None
    )
    distance_exactness = (
        cfg.resolved_distance_exactness() if kind.show_distance else None
    )
    row = GuidanceSession(
        user_id=user_id,
        tool_id=tool_id,
        action_key=kind.action_key,
        status=SESSION_STATUS_ACTIVE,
        discovery_chance=discovery_chance,
        direction_exactness=direction_exactness,
        distance_exactness=distance_exactness,
        duration_minutes=int(cfg.duration_minutes),
        started_at=now,
        expires_at=now + timedelta(minutes=int(cfg.duration_minutes)),
        created_at=now,
        updated_at=now,
    )
    session.add(row)
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
