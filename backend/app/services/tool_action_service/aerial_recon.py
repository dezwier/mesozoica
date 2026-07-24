"""Aerial Recon tool action: scout loop → ensure along path → timed discoveries."""

from __future__ import annotations

import json
import logging
import random
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError, ValidationError
from app.core.game_config import get_game_config
from app.models.data_source import DATA_SOURCE_FIELD
from app.models.field_ensure_job import FieldEnsureJob
from app.models.site import Site
from app.models.tool import Tool
from app.models.tool_mission import (
    ACTION_KEY_AERIAL_RECON,
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
from app.models.user_site import USER_SITE_ROLE_DISCOVERER, UserSite
from app.models.user_tool import UserTool
from app.services.site_service.field_ensure_queue import (
    STATUS_DONE,
    STATUS_PENDING,
    STATUS_RUNNING,
    enqueue_field_site_ensure,
)
from app.services.site_service.geo_utils import haversine_km
from app.services.tool_action_service.discover_aerial import discover_site_from_aerial
from app.services.tool_action_service.route_geometry import (
    RoutePoint,
    point_to_route_distance_km,
    prefix_up_to_fraction,
    route_length_km,
    sample_along_route,
)

logger = logging.getLogger("aerial_recon")

AERIAL_RECON_TOOL_NAME = "Aerial Recon"
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


def start_aerial_recon_mission(
    session: Session,
    *,
    user_id: int,
    tool_id: int,
    route: list[dict[str, Any]],
    origin_lat: float,
    origin_lon: float,
) -> ToolMission:
    """Validate ownership + route, enqueue ensures, create ensuring mission."""
    tool = session.get(Tool, tool_id)
    if tool is None:
        raise NotFoundError(f"Tool {tool_id} not found")
    if tool.name != AERIAL_RECON_TOOL_NAME:
        raise ValidationError("This action is only available for Aerial Recon")

    owned = session.exec(
        select(UserTool).where(
            col(UserTool.user_id) == user_id,
            col(UserTool.tool_id) == tool_id,
        )
    ).first()
    if owned is None:
        raise ValidationError("You must own Aerial Recon to deploy it")

    active = session.exec(
        select(ToolMission).where(
            col(ToolMission.user_id) == user_id,
            col(ToolMission.action_key) == ACTION_KEY_AERIAL_RECON,
            col(ToolMission.status).in_(_ACTIVE_STATUSES),
        )
    ).first()
    if active is not None:
        raise ValidationError("An Aerial Recon mission is already in progress")

    cfg = get_game_config().tool_actions.aerial_recon
    points = _parse_route(route)
    length_km = route_length_km(points)
    if length_km > cfg.max_route_km:
        raise ValidationError(
            f"Loop is {length_km:.1f} km; maximum allowed is {cfg.max_route_km:.0f} km"
        )

    tol_km = cfg.loop_endpoint_tolerance_m / 1000.0
    start_d = haversine_km(origin_lat, origin_lon, points[0].lat, points[0].lon)
    end_d = haversine_km(origin_lat, origin_lon, points[-1].lat, points[-1].lon)
    if start_d > tol_km or end_d > tol_km:
        raise ValidationError(
            "Loop must start and end at your current location"
        )

    samples = sample_along_route(points, spacing_km=cfg.ensure_sample_spacing_km)
    job_ids: list[int] = []
    for sample in samples:
        _, job_id = enqueue_field_site_ensure(
            session,
            lat=sample.lat,
            lon=sample.lon,
            reason="aerial_recon",
        )
        if job_id is not None:
            job_ids.append(job_id)

    speed = max(cfg.flight_speed_kmh, 1e-6)
    flight_duration_s = max(1, int(round(length_km / speed * 3600.0)))

    now = _utcnow()
    mission = ToolMission(
        user_id=user_id,
        tool_id=tool_id,
        action_key=ACTION_KEY_AERIAL_RECON,
        status=MISSION_STATUS_ENSURING,
        route_json=json.dumps(
            [{"lat": p.lat, "lon": p.lon} for p in points],
            separators=(",", ":"),
        ),
        route_length_km=length_km,
        flight_duration_s=flight_duration_s,
        flight_speed_kmh=cfg.flight_speed_kmh,
        max_route_km=cfg.max_route_km,
        discovery_chance=cfg.discovery_chance,
        discovery_distance_m=cfg.discovery_distance_m,
        ensure_job_ids_json=json.dumps(job_ids),
        created_at=now,
        updated_at=now,
    )
    session.add(mission)
    session.commit()
    session.refresh(mission)
    logger.info(
        "aerial_recon mission=%s ensuring jobs=%s length_km=%.2f",
        mission.id,
        len(job_ids),
        length_km,
    )
    return mission


def _load_route(mission: ToolMission) -> list[RoutePoint]:
    raw = json.loads(mission.route_json)
    return [RoutePoint(lat=float(p["lat"]), lon=float(p["lon"])) for p in raw]


def list_aerial_recon_missions(
    session: Session,
    *,
    user_id: int,
) -> list[ToolMission]:
    """Return all aerial recon missions for [user_id], newest first."""
    return list(
        session.exec(
            select(ToolMission)
            .where(
                col(ToolMission.user_id) == user_id,
                col(ToolMission.action_key) == ACTION_KEY_AERIAL_RECON,
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


def cancel_aerial_recon_mission(
    session: Session,
    *,
    user_id: int,
    mission_id: int,
) -> ToolMission:
    """Abort an active mission: truncate route at scout, skip pending discoveries."""
    mission = session.get(ToolMission, mission_id)
    if (
        mission is None
        or mission.user_id != user_id
        or mission.action_key != ACTION_KEY_AERIAL_RECON
    ):
        raise NotFoundError(f"Aerial Recon mission {mission_id} not found")
    if mission.status not in _ACTIVE_STATUSES:
        raise ValidationError("Only an in-progress Aerial Recon can be cancelled")

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
        "aerial_recon mission=%s cancelled frac=%.3f pending_skipped=%s",
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
    cfg = get_game_config().tool_actions.aerial_recon
    missions = list(
        session.exec(
            select(ToolMission).where(
                col(ToolMission.action_key) == ACTION_KEY_AERIAL_RECON,
                col(ToolMission.status) == MISSION_STATUS_ENSURING,
            )
        ).all()
    )
    promoted = 0
    for mission in missions:
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
    cfg = get_game_config().tool_actions.aerial_recon
    route = _load_route(mission)
    length_km = max(mission.route_length_km, 1e-6)
    max_dist_km = cfg.discovery_distance_m / 1000.0

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
        "aerial_recon mission=%s flying events=%s",
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
    cfg = get_game_config().tool_actions.aerial_recon
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
        if mission is None or mission.status != MISSION_STATUS_FLYING:
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
                mission_id=int(mission.id) if mission.id is not None else None,
                rng=rng,
            )
            event.status = (
                EVENT_STATUS_MISS if result is None else EVENT_STATUS_DONE
            )
        except Exception as exc:
            logger.warning(
                "aerial_recon event=%s site=%s failed: %s",
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


def process_aerial_recon_tick(
    session: Session,
    *,
    rng: random.Random | None = None,
) -> bool:
    """One worker tick: promote missions and process due events. True if work done."""
    promoted = promote_ensuring_missions(session)
    processed = process_due_mission_events(session, rng=rng)
    return promoted > 0 or processed > 0
