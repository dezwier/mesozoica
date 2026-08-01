"""Aerial mission tool actions: route loop → ensure along path → timed discoveries."""

from __future__ import annotations

import json
import logging
import random
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError, ValidationError
from app.models.data_source import DATA_SOURCE_FIELD
from app.models.field_ensure_job import FieldEnsureJob
from app.models.site import Site
from app.models.tool_mission import (
    AERIAL_MISSION_ACTION_KEYS,
    MISSION_STATUS_CANCELLED,
    MISSION_STATUS_DONE,
    MISSION_STATUS_ENSURING,
    MISSION_STATUS_FAILED,
    MISSION_STATUS_FLYING,
    ToolMission,
)
from app.models.tool_mission_event import (
    EVENT_STATUS_DONE,
    EVENT_STATUS_MISS,
    EVENT_STATUS_PENDING,
    EVENT_STATUS_SKIPPED,
    EVENT_TYPE_DISCOVER_SITE,
    ToolMissionEvent,
)
from app.models.tool_type import ToolType
from app.models.user_site import USER_SITE_ROLE_DISCOVERER, UserSite
from app.models.user_tool import USER_TOOL_ACTION_DEPLOYED, UserTool
from app.services.field_service.field_ensure_queue import (
    STATUS_PENDING,
    STATUS_RUNNING,
    enqueue_field_site_ensure,
)
from app.services.field_service.field_generate import FieldSiteLazyConfig
from app.services.site_common.geo_utils import haversine_km
from app.services.tool_action_service.aerial_mission_kinds import (
    config_for_action_key,
    is_aerial_action_key,
    kind_for_action_key,
    kind_for_tool_name,
)
from app.services.tool_action_service.discover_aerial import discover_site_from_aerial
from app.services.tool_action_service.route_geometry import (
    RoutePoint,
    cells_along_route,
    point_to_route_distance_km,
    prefix_up_to_fraction,
    route_length_km,
)
from app.services.tool_service.collect import resolve_owned_tool_selection
logger = logging.getLogger("aerial_mission")

_ACTIVE_STATUSES = (MISSION_STATUS_ENSURING, MISSION_STATUS_FLYING)


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


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


def start_aerial_mission(
    session: Session,
    *,
    user_id: int,
    tool_id: int,
    route: list[dict[str, Any]],
    origin_lat: float,
    origin_lon: float,
) -> ToolMission:
    """Validate ownership + route, enqueue ensures, create ensuring mission.

    ``tool_id`` is the catalog tool_type id (API-stable). The mission row stores
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
    label = kind.display_label

    active = session.exec(
        select(ToolMission).where(
            col(ToolMission.user_id) == user_id,
            col(ToolMission.action_key) == action_key,
            col(ToolMission.status).in_(_ACTIVE_STATUSES),
        )
    ).first()
    if active is not None:
        raise ValidationError(f"An {label} mission is already in progress")

    cfg = config_for_action_key(action_key)
    inst_p = instance.params_json or {}
    points = _parse_route(route)
    length_km = route_length_km(points)
    eff_max_route = float(inst_p.get("max_route_km", cfg.max_route_km))
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

    # Top up every 500 m density square the full route crosses.
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

    eff_speed = float(inst_p.get("flight_speed_kmh", cfg.flight_speed_kmh))
    speed = max(eff_speed, 1e-6)
    flight_duration_s = max(1, int(round(length_km / speed * 3600.0)))

    now = _utcnow()
    mission = ToolMission(
        user_id=user_id,
        tool_id=int(instance.id),
        action_key=action_key,
        status=MISSION_STATUS_ENSURING,
        route_json=json.dumps(
            [{"lat": p.lat, "lon": p.lon} for p in points],
            separators=(",", ":"),
        ),
        route_length_km=length_km,
        flight_duration_s=flight_duration_s,
        flight_speed_kmh=eff_speed,
        max_route_km=eff_max_route,
        discovery_chance=float(inst_p.get("discovery_chance", cfg.discovery_chance)),
        discovery_distance_m=float(inst_p.get("discovery_distance_m", cfg.discovery_distance_m)),
        ensure_job_ids_json=json.dumps(job_ids),
        created_at=now,
        updated_at=now,
    )
    session.add(mission)
    session.add(
        UserTool(
            user_id=user_id,
            tool_id=int(instance.id),
            timestamp=datetime.now(timezone.utc),
            action=USER_TOOL_ACTION_DEPLOYED,
        )
    )
    session.commit()
    session.refresh(mission)
    logger.info(
        "%s mission=%s ensuring jobs=%s length_km=%.2f",
        action_key,
        mission.id,
        len(job_ids),
        length_km,
    )
    return mission


def _load_route(mission: ToolMission) -> list[RoutePoint]:
    raw = json.loads(mission.route_json)
    return [RoutePoint(lat=float(p["lat"]), lon=float(p["lon"])) for p in raw]


def list_aerial_missions(
    session: Session,
    *,
    user_id: int,
    action_key: str | None = None,
) -> list[ToolMission]:
    """Return aerial missions for [user_id], newest first.

    When [action_key] is set, filter to that kind; otherwise all aerial keys.
    """
    if action_key is not None:
        if not is_aerial_action_key(action_key):
            raise ValidationError(f"Unknown aerial action_key: {action_key}")
        keys: tuple[str, ...] = (action_key,)
    else:
        keys = AERIAL_MISSION_ACTION_KEYS
    return list(
        session.exec(
            select(ToolMission)
            .where(
                col(ToolMission.user_id) == user_id,
                col(ToolMission.action_key).in_(keys),
            )
            .order_by(col(ToolMission.created_at).desc())
        ).all()
    )


def mission_route_dicts(mission: ToolMission) -> list[dict[str, float]]:
    return [{"lat": p.lat, "lon": p.lon} for p in _load_route(mission)]


def _flight_progress_fraction(mission: ToolMission, *, now: datetime | None = None) -> float:
    """Arc fraction 0..1 matching client / discovery scheduling."""
    if mission.status == MISSION_STATUS_ENSURING or mission.flight_started_at is None:
        return 0.0
    duration = mission.flight_duration_s
    if duration <= 0:
        return 1.0 if mission.status in (
            MISSION_STATUS_DONE,
            MISSION_STATUS_FAILED,
            MISSION_STATUS_CANCELLED,
        ) else 0.0
    clock = now if now is not None else _utcnow()
    started = mission.flight_started_at
    elapsed = (clock - started).total_seconds()
    return min(1.0, max(0.0, elapsed / duration))


def cancel_aerial_mission(
    session: Session,
    *,
    user_id: int,
    mission_id: int,
) -> ToolMission:
    """Abort an active mission: truncate route at craft, skip pending discoveries."""
    mission = session.get(ToolMission, mission_id)
    if (
        mission is None
        or mission.user_id != user_id
        or not is_aerial_action_key(mission.action_key)
    ):
        raise NotFoundError(f"Aerial mission {mission_id} not found")
    label = kind_for_action_key(mission.action_key).display_label
    if mission.status not in _ACTIVE_STATUSES:
        raise ValidationError(f"Only an in-progress {label} can be cancelled")

    now = _utcnow()
    frac = _flight_progress_fraction(mission, now=now)
    route = _load_route(mission)
    truncated = prefix_up_to_fraction(route, frac)

    mission.route_json = json.dumps(
        [{"lat": p.lat, "lon": p.lon} for p in truncated],
        separators=(",", ":"),
    )
    mission.route_length_km = route_length_km(truncated)
    mission.status = MISSION_STATUS_CANCELLED
    mission.flight_ends_at = now
    mission.updated_at = now
    session.add(mission)

    pending = list(
        session.exec(
            select(ToolMissionEvent).where(
                col(ToolMissionEvent.mission_id) == mission.id,
                col(ToolMissionEvent.status) == EVENT_STATUS_PENDING,
            )
        ).all()
    )
    for event in pending:
        event.status = EVENT_STATUS_SKIPPED
        event.processed_at = now
        session.add(event)

    session.commit()
    session.refresh(mission)
    logger.info(
        "%s mission=%s cancelled frac=%.3f pending_skipped=%s",
        mission.action_key,
        mission.id,
        frac,
        len(pending),
    )
    return mission


def _ensure_jobs_ready(session: Session, mission: ToolMission) -> bool:
    """True when all linked ensure jobs are terminal (done/failed) or none exist."""
    if not mission.ensure_job_ids_json:
        return True
    try:
        job_ids = json.loads(mission.ensure_job_ids_json)
    except json.JSONDecodeError:
        return True
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


def _ensure_timed_out(mission: ToolMission, timeout_s: int) -> bool:
    age = (_utcnow() - mission.created_at).total_seconds()
    return age >= timeout_s


def promote_ensuring_missions(session: Session) -> int:
    """Promote ensuring → flying when ensures are ready (or timed out)."""
    missions = list(
        session.exec(
            select(ToolMission).where(
                col(ToolMission.action_key).in_(AERIAL_MISSION_ACTION_KEYS),
                col(ToolMission.status) == MISSION_STATUS_ENSURING,
            )
        ).all()
    )
    promoted = 0
    for mission in missions:
        cfg = config_for_action_key(mission.action_key)
        ready = _ensure_jobs_ready(session, mission)
        timed_out = _ensure_timed_out(mission, cfg.ensure_timeout_s)
        if not ready and not timed_out:
            continue
        try:
            _promote_to_flying(session, mission)
            promoted += 1
        except Exception as exc:
            logger.exception("Failed to promote mission %s", mission.id)
            mission.status = MISSION_STATUS_FAILED
            mission.error_message = str(exc)[:2000]
            mission.updated_at = _utcnow()
            session.add(mission)
            session.commit()
    return promoted


def _promote_to_flying(session: Session, mission: ToolMission) -> None:
    cfg = config_for_action_key(mission.action_key)
    route = _load_route(mission)
    length_km = max(mission.route_length_km, 1e-6)
    distance_m = (
        float(mission.discovery_distance_m)
        if mission.discovery_distance_m is not None
        else float(cfg.discovery_distance_m)
    )
    max_dist_km = distance_m / 1000.0

    # Bounding box around route with discovery buffer.
    lats = [p.lat for p in route]
    lons = [p.lon for p in route]
    # ~1 deg lat ≈ 111 km
    pad_deg = (max_dist_km / 111.0) + 0.01
    min_lat, max_lat = min(lats) - pad_deg, max(lats) + pad_deg
    min_lon, max_lon = min(lons) - pad_deg, max(lons) + pad_deg

    linked = select(col(UserSite.site_id)).where(
        col(UserSite.user_id) == mission.user_id,
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
    ends = now + timedelta(seconds=mission.flight_duration_s)
    for along_km, closest, site in candidates:
        frac = min(1.0, max(0.0, along_km / length_km))
        due_at = now + timedelta(seconds=mission.flight_duration_s * frac)
        session.add(
            ToolMissionEvent(
                mission_id=int(mission.id),
                event_type=EVENT_TYPE_DISCOVER_SITE,
                site_id=int(site.site_id),
                due_at=due_at,
                status=EVENT_STATUS_PENDING,
                lat=closest.lat,
                lon=closest.lon,
                distance_along_km=along_km,
                created_at=now,
            )
        )

    mission.status = MISSION_STATUS_FLYING
    mission.flight_started_at = now
    mission.flight_ends_at = ends
    mission.updated_at = now
    session.add(mission)
    session.commit()
    logger.info(
        "%s mission=%s flying events=%s",
        mission.action_key,
        mission.id,
        len(candidates),
    )


def process_due_mission_events(
    session: Session,
    *,
    rng: random.Random | None = None,
    limit: int = 20,
) -> int:
    """Process due discover events; return count processed."""
    now = _utcnow()
    events = list(
        session.exec(
            select(ToolMissionEvent)
            .where(
                col(ToolMissionEvent.status) == EVENT_STATUS_PENDING,
                col(ToolMissionEvent.due_at) <= now,
                col(ToolMissionEvent.event_type) == EVENT_TYPE_DISCOVER_SITE,
            )
            .order_by(col(ToolMissionEvent.due_at))
            .limit(limit)
        ).all()
    )
    processed = 0
    for event in events:
        mission = session.get(ToolMission, event.mission_id)
        if (
            mission is None
            or mission.status != MISSION_STATUS_FLYING
            or not is_aerial_action_key(mission.action_key)
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

        cfg = config_for_action_key(mission.action_key)
        distance_m = (
            float(mission.discovery_distance_m)
            if mission.discovery_distance_m is not None
            else float(cfg.discovery_distance_m)
        )
        chance = (
            float(mission.discovery_chance)
            if mission.discovery_chance is not None
            else float(cfg.discovery_chance)
        )

        try:
            result = discover_site_from_aerial(
                session,
                site_id=int(event.site_id),
                user_id=mission.user_id,
                lat=float(event.lat),
                lon=float(event.lon),
                max_distance_m=distance_m * 2,  # closest-on-path already filtered
                discovery_chance=chance,
                how_discovered=mission.action_key,
                mission_id=int(mission.id) if mission.id is not None else None,
                rng=rng,
            )
            event.status = (
                EVENT_STATUS_MISS if result is None else EVENT_STATUS_DONE
            )
        except Exception as exc:
            logger.warning(
                "%s event=%s site=%s failed: %s",
                mission.action_key,
                event.id,
                event.site_id,
                exc,
            )
            event.status = EVENT_STATUS_SKIPPED

        event.processed_at = _utcnow()
        session.add(event)
        session.commit()
        processed += 1

    _finalize_completed_missions(session)
    return processed


def _finalize_completed_missions(session: Session) -> None:
    now = _utcnow()
    missions = list(
        session.exec(
            select(ToolMission).where(
                col(ToolMission.action_key).in_(AERIAL_MISSION_ACTION_KEYS),
                col(ToolMission.status) == MISSION_STATUS_FLYING,
                col(ToolMission.flight_ends_at).is_not(None),
                col(ToolMission.flight_ends_at) <= now,
            )
        ).all()
    )
    for mission in missions:
        pending = session.exec(
            select(ToolMissionEvent).where(
                col(ToolMissionEvent.mission_id) == mission.id,
                col(ToolMissionEvent.status) == EVENT_STATUS_PENDING,
            )
        ).first()
        if pending is not None:
            continue
        mission.status = MISSION_STATUS_DONE
        mission.updated_at = now
        session.add(mission)
        session.commit()


def process_aerial_mission_tick(
    session: Session,
    *,
    rng: random.Random | None = None,
) -> bool:
    """One worker tick: promote missions and process due events. True if work done."""
    promoted = promote_ensuring_missions(session)
    processed = process_due_mission_events(session, rng=rng)
    return promoted > 0 or processed > 0
