"""Aerial tool sessions: route loop → ensure along path → timed discoveries."""

from __future__ import annotations

import logging
import random
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError, ValidationError
from app.shared.data_sources import DATA_SOURCE_FIELD
from app.models.field_ensure_job import FieldEnsureJob
from app.models.site import Site
from app.models.tool_session import (
    AERIAL_ACTION_KEYS,
    LIVE_STATUSES,
    SESSION_STATUS_ACTIVE,
    SESSION_STATUS_CANCELLED,
    SESSION_STATUS_COMPLETED,
    SESSION_STATUS_FAILED,
    SESSION_STATUS_PENDING,
    STOP_REASON_EXHAUSTED,
    STOP_REASON_FAILED,
    STOP_REASON_MANUAL,
    ToolSession,
)
from app.models.tool_session_event import (
    EVENT_STATUS_DONE,
    EVENT_STATUS_MISS,
    EVENT_STATUS_PENDING,
    EVENT_STATUS_SKIPPED,
    EVENT_TYPE_DISCOVER_SITE,
    ToolSessionEvent,
)
from app.models.tool_type import ToolType
from app.models.user_site import USER_SITE_ROLE_DISCOVERER, UserSite
from app.models.user_tool import USER_TOOL_ACTION_DEPLOYED, UserTool
from app.features.field.public import (
    STATUS_PENDING,
    STATUS_RUNNING,
    enqueue_field_site_ensure,
)
from app.features.field.public import FieldSiteLazyConfig
from app.shared.geography.geo_utils import haversine_km
from app.features.tools.application.actions.aerial_action_keys import (
    config_for_action_key,
    is_aerial_action_key,
    kind_for_action_key,
    kind_for_tool_name,
)
from app.features.tools.application.actions.discover_session import discover_site_from_aerial
from app.features.tools.application.actions.route_geometry import (
    RoutePoint,
    cells_along_route,
    point_to_route_distance_km,
    prefix_up_to_fraction,
    route_length_km,
)
from app.features.tools.application.actions.tool_session.budget import (
    allocate_remaining_for_start,
    remaining_minutes_for_route,
    _parse_iso,
)
from app.features.tools.application.actions.tool_session.lifecycle import (
    close_session,
    ensure_exclusive_tool_session,
)
from app.features.tools.application.catalog.collect import resolve_owned_tool_selection

logger = logging.getLogger("tool_session.aerial")


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _max_route_km(
    *,
    flight_speed_kmh: float,
    remaining_minutes: float,
) -> float:
    """Max loop length from remaining battery minutes × speed."""
    return float(flight_speed_kmh) * max(0.0, float(remaining_minutes)) / 60.0


def _parse_route(raw: list[dict[str, Any]]) -> list[RoutePoint]:
    if not isinstance(raw, list) or len(raw) < 3:
        raise ValidationError("Route must include at least 3 points")
    points: list[RoutePoint] = []
    for i, item in enumerate(raw):
        if not isinstance(item, dict):
            raise ValidationError(f"Route point {i} must be an object")
        try:
            lat = float(item["lat"])
            lon = float(item["lon"])
        except (KeyError, TypeError, ValueError) as exc:
            raise ValidationError(f"Route point {i} needs lat/lon") from exc
        if not (-90.0 <= lat <= 90.0 and -180.0 <= lon <= 180.0):
            raise ValidationError(f"Route point {i} has invalid coordinates")
        points.append(RoutePoint(lat=lat, lon=lon))
    return points


def _state(row: ToolSession) -> dict[str, Any]:
    return dict(row.state_json or {})


def _params(row: ToolSession) -> dict[str, Any]:
    return dict(row.params_json or {})


def _set_state(row: ToolSession, state: dict[str, Any]) -> None:
    row.state_json = state


def load_route(row: ToolSession) -> list[RoutePoint]:
    raw = _state(row).get("route") or []
    return [RoutePoint(lat=float(p["lat"]), lon=float(p["lon"])) for p in raw]


def session_route_dicts(row: ToolSession) -> list[dict[str, float]]:
    return [{"lat": p.lat, "lon": p.lon} for p in load_route(row)]


def flight_started_at(row: ToolSession) -> datetime | None:
    return _parse_iso(_state(row).get("flight_started_at"))


def flight_ends_at(row: ToolSession) -> datetime | None:
    return _parse_iso(_state(row).get("flight_ends_at"))


def flight_duration_s(row: ToolSession) -> int:
    return int(_state(row).get("flight_duration_s") or 0)


def route_length_km_of(row: ToolSession) -> float:
    return float(_state(row).get("route_length_km") or 0.0)


def start_aerial_session(
    session: Session,
    *,
    user_id: int,
    tool_id: int,
    route: list[dict[str, Any]],
    origin_lat: float,
    origin_lon: float,
) -> ToolSession:
    """Validate ownership + route, enqueue ensures, create pending session.

    ``tool_id`` is the catalog tool_type id (API-stable). The session row stores
    the owned tool instance id.
    """
    selected = resolve_owned_tool_selection(session, user_id=user_id, tool_id=tool_id)
    if selected is None:
        tool_type = session.get(ToolType, tool_id)
        if tool_type is None:
            raise NotFoundError(f"Tool {tool_id} not found")
        kind = kind_for_tool_name(tool_type.name)
        raise ValidationError(f"You must own {kind.display_label} to deploy it")
    tool_type, instance = selected
    kind = kind_for_tool_name(tool_type.name)
    action_key = kind.action_key

    ensure_exclusive_tool_session(
        session, user_id=user_id, instance_id=int(instance.id)
    )

    cfg = config_for_action_key(action_key)
    inst_p = instance.params_json or {}
    points = _parse_route(route)
    length_km = route_length_km(points)
    eff_speed = float(inst_p.get("flight_speed_kmh", cfg.flight_speed_kmh))
    allocate_remaining_for_start(session, tool_type=tool_type, instance=instance)
    remaining_minutes = remaining_minutes_for_route(
        session, tool_type=tool_type, instance=instance
    )
    eff_max_route = _max_route_km(
        flight_speed_kmh=eff_speed,
        remaining_minutes=remaining_minutes,
    )
    if length_km > eff_max_route:
        raise ValidationError(
            f"Loop is {length_km:.1f} km; maximum allowed is {eff_max_route:.0f} km"
        )

    tol_km = float(inst_p.get("loop_endpoint_tolerance_m", cfg.loop_endpoint_tolerance_m)) / 1000.0
    start_d = haversine_km(origin_lat, origin_lon, points[0].lat, points[0].lon)
    end_d = haversine_km(origin_lat, origin_lon, points[-1].lat, points[-1].lon)
    if start_d > tol_km or end_d > tol_km:
        raise ValidationError(
            "Loop must start and end at your current location"
        )

    lazy = FieldSiteLazyConfig.from_game_config()
    samples = cells_along_route(points, cell_size_m=lazy.cell_size_m)
    job_ids: list[int] = []
    for sample in samples:
        _, job_id = enqueue_field_site_ensure(
            session,
            lat=sample.lat,
            lon=sample.lon,
            reason=action_key,
        )
        if job_id is not None:
            job_ids.append(job_id)

    speed = max(eff_speed, 1e-6)
    duration_s = max(1, int(round(length_km / speed * 3600.0)))

    now = _utcnow()
    row = ToolSession(
        user_id=user_id,
        tool_id=int(instance.id),
        action_key=action_key,
        status=SESSION_STATUS_PENDING,
        started_at=now,
        expires_at=None,
        params_json={
            "flight_speed_kmh": eff_speed,
            "max_route_km": eff_max_route,
            "flight_discovery_chance": float(
                inst_p.get(
                    "flight_discovery_chance",
                    inst_p.get("discovery_chance", cfg.flight_discovery_chance),
                )
            ),
            "flight_discovery_distance_m": float(
                inst_p.get(
                    "flight_discovery_distance_m",
                    inst_p.get(
                        "visibility_distance_m", cfg.flight_discovery_distance_m
                    ),
                )
            ),
        },
        state_json={
            "route": [{"lat": p.lat, "lon": p.lon} for p in points],
            "route_length_km": length_km,
            "flight_duration_s": duration_s,
            "ensure_job_ids": job_ids,
        },
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
    logger.info(
        "%s session=%s pending jobs=%s length_km=%.2f",
        action_key,
        row.id,
        len(job_ids),
        length_km,
    )
    return row


def list_aerial_sessions(
    session: Session,
    *,
    user_id: int,
    action_key: str | None = None,
) -> list[ToolSession]:
    """Return aerial sessions for [user_id], newest first."""
    if action_key is not None:
        if not is_aerial_action_key(action_key):
            raise ValidationError(f"Unknown aerial action_key: {action_key}")
        keys: tuple[str, ...] = (action_key,)
    else:
        keys = AERIAL_ACTION_KEYS
    return list(
        session.exec(
            select(ToolSession)
            .where(
                col(ToolSession.user_id) == user_id,
                col(ToolSession.action_key).in_(keys),
            )
            .order_by(col(ToolSession.created_at).desc())
        ).all()
    )


def _flight_progress_fraction(
    row: ToolSession, *, now: datetime | None = None
) -> float:
    """Arc fraction 0..1 matching client / discovery scheduling."""
    if row.status == SESSION_STATUS_PENDING or flight_started_at(row) is None:
        return 0.0
    duration = flight_duration_s(row)
    if duration <= 0:
        return 1.0 if row.status in (
            SESSION_STATUS_COMPLETED,
            SESSION_STATUS_FAILED,
            SESSION_STATUS_CANCELLED,
        ) else 0.0
    clock = now if now is not None else _utcnow()
    started = flight_started_at(row)
    assert started is not None
    elapsed = (clock - started).total_seconds()
    return min(1.0, max(0.0, elapsed / duration))


def cancel_session(
    session: Session,
    *,
    user_id: int,
    session_id: int,
) -> ToolSession:
    """Abort a live aerial session: truncate route at craft, skip pending discoveries."""
    row = session.get(ToolSession, session_id)
    if (
        row is None
        or row.user_id != user_id
        or not is_aerial_action_key(row.action_key)
    ):
        raise NotFoundError(f"Aerial session {session_id} not found")
    label = kind_for_action_key(row.action_key).display_label
    if row.status not in LIVE_STATUSES:
        raise ValidationError(f"Only an in-progress {label} can be cancelled")

    now = _utcnow()
    frac = _flight_progress_fraction(row, now=now)
    route = load_route(row)
    truncated = prefix_up_to_fraction(route, frac)

    state = _state(row)
    state["route"] = [{"lat": p.lat, "lon": p.lon} for p in truncated]
    state["route_length_km"] = route_length_km(truncated)
    state["flight_ends_at"] = now.isoformat()
    _set_state(row, state)

    row.status = SESSION_STATUS_CANCELLED
    close_session(row, now=now, stop_reason=STOP_REASON_MANUAL)
    session.add(row)

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
        event.processed_at = now
        session.add(event)

    session.commit()
    session.refresh(row)
    logger.info(
        "%s session=%s cancelled frac=%.3f pending_skipped=%s",
        row.action_key,
        row.id,
        frac,
        len(pending),
    )
    return row


def _ensure_jobs_ready(session: Session, row: ToolSession) -> bool:
    """True when all linked ensure jobs are terminal (done/failed) or none exist."""
    job_ids = _state(row).get("ensure_job_ids") or []
    if not job_ids:
        return True

    pending = 0
    for job_id in job_ids:
        job = session.get(FieldEnsureJob, int(job_id))
        if job is None:
            continue
        if job.status in (STATUS_PENDING, STATUS_RUNNING):
            pending += 1
    return pending == 0


def _ensure_timed_out(row: ToolSession, timeout_s: int) -> bool:
    age = (_utcnow() - row.created_at).total_seconds()
    return age >= timeout_s


def promote_pending_sessions(session: Session) -> int:
    """Promote pending → active when ensures are ready (or timed out)."""
    rows = list(
        session.exec(
            select(ToolSession).where(
                col(ToolSession.action_key).in_(AERIAL_ACTION_KEYS),
                col(ToolSession.status) == SESSION_STATUS_PENDING,
            )
        ).all()
    )
    promoted = 0
    for row in rows:
        cfg = config_for_action_key(row.action_key)
        ready = _ensure_jobs_ready(session, row)
        timed_out = _ensure_timed_out(row, cfg.ensure_timeout_s)
        if not ready and not timed_out:
            continue
        try:
            _promote_to_active(session, row)
            promoted += 1
        except Exception as exc:
            logger.exception("Failed to promote session %s", row.id)
            now = _utcnow()
            state = _state(row)
            state["error_message"] = str(exc)[:2000]
            _set_state(row, state)
            row.status = SESSION_STATUS_FAILED
            close_session(row, now=now, stop_reason=STOP_REASON_FAILED)
            session.add(row)
            session.commit()
    return promoted


def _promote_to_active(session: Session, row: ToolSession) -> None:
    cfg = config_for_action_key(row.action_key)
    params = _params(row)
    route = load_route(row)
    length_km = max(route_length_km_of(row), 1e-6)
    distance_m = float(
        params.get(
            "flight_discovery_distance_m",
            params.get("visibility_distance_m", cfg.flight_discovery_distance_m),
        )
    )
    max_dist_km = distance_m / 1000.0
    duration_s = flight_duration_s(row)

    lats = [p.lat for p in route]
    lons = [p.lon for p in route]
    pad_deg = (max_dist_km / 111.0) + 0.01
    min_lat, max_lat = min(lats) - pad_deg, max(lats) + pad_deg
    min_lon, max_lon = min(lons) - pad_deg, max(lons) + pad_deg

    linked = select(col(UserSite.site_id)).where(
        col(UserSite.user_id) == row.user_id,
        col(UserSite.role) == USER_SITE_ROLE_DISCOVERER,
    )
    sites = list(
        session.exec(
            select(Site).where(
                col(Site.data_source) == DATA_SOURCE_FIELD,
                col(Site.latitude).is_not(None),
                col(Site.longitude).is_not(None),
                col(Site.latitude) >= min_lat,
                col(Site.latitude) <= max_lat,
                col(Site.longitude) >= min_lon,
                col(Site.longitude) <= max_lon,
                ~col(Site.site_id).in_(linked),
            )
        ).all()
    )

    candidates: list[tuple[float, RoutePoint, Site]] = []
    for site in sites:
        site_pt = RoutePoint(lat=float(site.latitude), lon=float(site.longitude))
        dist_km, along_km, closest = point_to_route_distance_km(site_pt, route)
        if dist_km <= max_dist_km:
            candidates.append((along_km, closest, site))

    candidates.sort(key=lambda item: item[0])

    now = _utcnow()
    ends = now + timedelta(seconds=duration_s)
    for along_km, closest, site in candidates:
        frac = min(1.0, max(0.0, along_km / length_km))
        due_at = now + timedelta(seconds=duration_s * frac)
        session.add(
            ToolSessionEvent(
                session_id=int(row.id),
                event_type=EVENT_TYPE_DISCOVER_SITE,
                site_id=int(site.site_id),
                due_at=due_at,
                status=EVENT_STATUS_PENDING,
                lat=closest.lat,
                lon=closest.lon,
                payload_json={"distance_along_km": along_km},
                created_at=now,
            )
        )

    state = _state(row)
    state["flight_started_at"] = now.isoformat()
    state["flight_ends_at"] = ends.isoformat()
    _set_state(row, state)
    row.status = SESSION_STATUS_ACTIVE
    row.updated_at = now
    session.add(row)
    session.commit()
    logger.info(
        "%s session=%s active events=%s",
        row.action_key,
        row.id,
        len(candidates),
    )


def process_due_events(
    session: Session,
    *,
    rng: random.Random | None = None,
    limit: int = 20,
) -> int:
    """Process due discover events; return count processed."""
    now = _utcnow()
    events = list(
        session.exec(
            select(ToolSessionEvent)
            .where(
                col(ToolSessionEvent.status) == EVENT_STATUS_PENDING,
                col(ToolSessionEvent.due_at) <= now,
                col(ToolSessionEvent.event_type) == EVENT_TYPE_DISCOVER_SITE,
            )
            .order_by(col(ToolSessionEvent.due_at))
            .limit(limit)
        ).all()
    )
    processed = 0
    for event in events:
        row = session.get(ToolSession, event.session_id)
        if (
            row is None
            or row.status != SESSION_STATUS_ACTIVE
            or not is_aerial_action_key(row.action_key)
        ):
            event.status = EVENT_STATUS_SKIPPED
            event.processed_at = now
            session.add(event)
            session.commit()
            processed += 1
            continue

        if event.site_id is None or event.lat is None or event.lon is None:
            event.status = EVENT_STATUS_SKIPPED
            event.processed_at = now
            session.add(event)
            session.commit()
            processed += 1
            continue

        cfg = config_for_action_key(row.action_key)
        params = _params(row)
        distance_m = float(
            params.get(
                "flight_discovery_distance_m",
                params.get(
                    "visibility_distance_m", cfg.flight_discovery_distance_m
                ),
            )
        )
        chance = float(
            params.get(
                "flight_discovery_chance",
                params.get("discovery_chance", cfg.flight_discovery_chance),
            )
        )

        try:
            result = discover_site_from_aerial(
                session,
                site_id=int(event.site_id),
                user_id=row.user_id,
                lat=float(event.lat),
                lon=float(event.lon),
                max_distance_m=distance_m * 2,
                discovery_chance=chance,
                how_discovered=row.action_key,
                session_id=int(row.id) if row.id is not None else None,
                rng=rng,
            )
            event.status = (
                EVENT_STATUS_MISS if result is None else EVENT_STATUS_DONE
            )
        except Exception as exc:
            logger.warning(
                "%s event=%s site=%s failed: %s",
                row.action_key,
                event.id,
                event.site_id,
                exc,
            )
            event.status = EVENT_STATUS_SKIPPED

        event.processed_at = _utcnow()
        session.add(event)
        session.commit()
        processed += 1

    _finalize_completed_sessions(session)
    return processed


def _finalize_completed_sessions(session: Session) -> None:
    now = _utcnow()
    rows = list(
        session.exec(
            select(ToolSession).where(
                col(ToolSession.action_key).in_(AERIAL_ACTION_KEYS),
                col(ToolSession.status) == SESSION_STATUS_ACTIVE,
            )
        ).all()
    )
    for row in rows:
        ends = flight_ends_at(row)
        if ends is None or ends > now:
            continue
        pending = session.exec(
            select(ToolSessionEvent).where(
                col(ToolSessionEvent.session_id) == row.id,
                col(ToolSessionEvent.status) == EVENT_STATUS_PENDING,
            )
        ).first()
        if pending is not None:
            continue
        row.status = SESSION_STATUS_COMPLETED
        close_session(row, now=now, stop_reason=STOP_REASON_EXHAUSTED)
        session.add(row)
        session.commit()


def process_tool_session_tick(
    session: Session,
    *,
    rng: random.Random | None = None,
) -> bool:
    """One worker tick: promote sessions and process due events. True if work done."""
    promoted = promote_pending_sessions(session)
    processed = process_due_events(session, rng=rng)
    return promoted > 0 or processed > 0
