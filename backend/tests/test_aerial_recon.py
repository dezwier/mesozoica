"""Tests for Aerial Recon tool action missions."""

from __future__ import annotations

import json
from datetime import datetime, timedelta

from sqlmodel import Session, select

from app.core.game_config import get_game_config
from app.core.security import create_access_token
from app.models.data_source import DATA_SOURCE_FIELD
from app.models.field_ensure_job import FieldEnsureJob
from app.models.site import Site
from app.models.tool import Tool
from app.models.tool_mission import (
    ACTION_KEY_AERIAL_RECON,
    MISSION_STATUS_CANCELLED,
    MISSION_STATUS_DONE,
    MISSION_STATUS_ENSURING,
    MISSION_STATUS_FLYING,
    ToolMission,
)
from app.models.tool_mission_event import (
    EVENT_STATUS_DONE,
    EVENT_STATUS_MISS,
    EVENT_STATUS_PENDING,
    EVENT_STATUS_SKIPPED,
    ToolMissionEvent,
)
from app.models.user import User
from app.models.user_tool import UserTool
from app.services.tool_action_service.aerial_recon import (
    cancel_aerial_recon_mission,
    process_due_mission_events,
    promote_ensuring_missions,
    start_aerial_recon_mission,
)


def _auth_headers(user: User) -> dict[str, str]:
    token = create_access_token({"sub": str(user.id)})
    return {"Authorization": f"Bearer {token}"}


def _user(session: Session, *, username: str = "pilot") -> User:
    user = User(
        username=username,
        email=f"{username}@example.com",
        password="x",
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    return user


def _aerial_tool(session: Session) -> Tool:
    tool = Tool(
        name="Aerial Recon",
        category="1 site_discovery",
        scientific_tool="helicopter",
        description="Scout loop",
        rarity=5,
        action="Deploy",
    )
    session.add(tool)
    session.commit()
    session.refresh(tool)
    return tool


def _grant(session: Session, *, user_id: int, tool_id: int) -> None:
    session.add(UserTool(user_id=user_id, tool_id=tool_id, level=1))
    session.commit()


def _square_route(origin_lat: float, origin_lon: float, *, delta: float = 0.01):
    """Small closed-ish loop (~few km) starting/ending at origin."""
    return [
        {"lat": origin_lat, "lon": origin_lon},
        {"lat": origin_lat + delta, "lon": origin_lon},
        {"lat": origin_lat + delta, "lon": origin_lon + delta},
        {"lat": origin_lat, "lon": origin_lon + delta},
        {"lat": origin_lat, "lon": origin_lon},
    ]


def test_aerial_recon_rejects_unowned(client, session: Session):
    tool = _aerial_tool(session)
    user = _user(session)
    origin_lat, origin_lon = 40.0, -100.0
    response = client.post(
        f"/api/v1/tools/{tool.id}/actions/aerial-recon",
        headers=_auth_headers(user),
        json={
            "route": _square_route(origin_lat, origin_lon),
            "origin_lat": origin_lat,
            "origin_lon": origin_lon,
        },
    )
    assert response.status_code == 400
    assert "own" in response.json()["detail"].lower()


def test_aerial_recon_rejects_open_loop(client, session: Session):
    tool = _aerial_tool(session)
    user = _user(session)
    _grant(session, user_id=int(user.id), tool_id=int(tool.id))
    origin_lat, origin_lon = 40.0, -100.0
    route = _square_route(origin_lat, origin_lon, delta=0.005)
    # End ~200 m away — outside 75 m tolerance, still under max route length.
    route[-1] = {"lat": origin_lat + 0.002, "lon": origin_lon}
    response = client.post(
        f"/api/v1/tools/{tool.id}/actions/aerial-recon",
        headers=_auth_headers(user),
        json={
            "route": route,
            "origin_lat": origin_lat,
            "origin_lon": origin_lon,
        },
    )
    assert response.status_code == 400
    assert "start and end" in response.json()["detail"].lower()


def test_aerial_recon_rejects_overlong_route(client, session: Session):
    tool = _aerial_tool(session)
    user = _user(session)
    _grant(session, user_id=int(user.id), tool_id=int(tool.id))
    origin_lat, origin_lon = 40.0, -100.0
    # ~111 km per degree lat → 2 deg ≈ 222 km > 100 km default max
    route = [
        {"lat": origin_lat, "lon": origin_lon},
        {"lat": origin_lat + 2.0, "lon": origin_lon},
        {"lat": origin_lat + 2.0, "lon": origin_lon + 0.01},
        {"lat": origin_lat, "lon": origin_lon},
    ]
    response = client.post(
        f"/api/v1/tools/{tool.id}/actions/aerial-recon",
        headers=_auth_headers(user),
        json={
            "route": route,
            "origin_lat": origin_lat,
            "origin_lon": origin_lon,
        },
    )
    assert response.status_code == 400
    assert "maximum" in response.json()["detail"].lower()


def test_aerial_recon_accepts_and_enqueues_ensure(client, session: Session):
    tool = _aerial_tool(session)
    user = _user(session)
    _grant(session, user_id=int(user.id), tool_id=int(tool.id))
    origin_lat, origin_lon = 40.0, -100.0
    response = client.post(
        f"/api/v1/tools/{tool.id}/actions/aerial-recon",
        headers=_auth_headers(user),
        json={
            "route": _square_route(origin_lat, origin_lon),
            "origin_lat": origin_lat,
            "origin_lon": origin_lon,
        },
    )
    assert response.status_code == 202
    body = response.json()
    assert body["status"] == MISSION_STATUS_ENSURING
    assert body["mission_id"] > 0
    assert body["route_length_km"] > 0
    assert body["flight_duration_s"] > 0
    assert len(body["route"]) >= 3
    # Duration from speed: length_km / 50 * 3600
    expected_s = max(1, int(round(body["route_length_km"] / 50.0 * 3600.0)))
    assert body["flight_duration_s"] == expected_s

    missions = list(session.exec(select(ToolMission)).all())
    assert len(missions) == 1
    assert missions[0].action_key == ACTION_KEY_AERIAL_RECON
    assert missions[0].flight_duration_s == expected_s
    job_ids = json.loads(missions[0].ensure_job_ids_json or "[]")
    assert len(job_ids) >= 1
    jobs = list(session.exec(select(FieldEnsureJob)).all())
    assert len(jobs) >= 1


def test_list_aerial_recon_missions(client, session: Session):
    tool = _aerial_tool(session)
    user = _user(session)
    other = _user(session, username="other")
    _grant(session, user_id=int(user.id), tool_id=int(tool.id))
    _grant(session, user_id=int(other.id), tool_id=int(tool.id))
    origin_lat, origin_lon = 40.0, -100.0
    route = _square_route(origin_lat, origin_lon)

    created = client.post(
        f"/api/v1/tools/{tool.id}/actions/aerial-recon",
        headers=_auth_headers(user),
        json={
            "route": route,
            "origin_lat": origin_lat,
            "origin_lon": origin_lon,
        },
    )
    assert created.status_code == 202
    mission_id = created.json()["mission_id"]

    # Other user's mission must not appear.
    other_resp = client.post(
        f"/api/v1/tools/{tool.id}/actions/aerial-recon",
        headers=_auth_headers(other),
        json={
            "route": route,
            "origin_lat": origin_lat,
            "origin_lon": origin_lon,
        },
    )
    assert other_resp.status_code == 202

    listed = client.get(
        "/api/v1/tools/missions/aerial-recon",
        headers=_auth_headers(user),
    )
    assert listed.status_code == 200
    items = listed.json()["items"]
    assert len(items) == 1
    assert items[0]["mission_id"] == mission_id
    assert items[0]["status"] == MISSION_STATUS_ENSURING
    assert len(items[0]["route"]) >= 3
    assert items[0]["tool_id"] == tool.id
    assert items[0]["discovered_site_ids"] == []

    unauth = client.get("/api/v1/tools/missions/aerial-recon")
    assert unauth.status_code in (401, 403)


def test_list_aerial_recon_includes_discovered_site_ids(client, session: Session):
    tool = _aerial_tool(session)
    user = _user(session)
    _grant(session, user_id=int(user.id), tool_id=int(tool.id))
    origin_lat, origin_lon = 40.0, -100.0
    route = _square_route(origin_lat, origin_lon)

    created = client.post(
        f"/api/v1/tools/{tool.id}/actions/aerial-recon",
        headers=_auth_headers(user),
        json={
            "route": route,
            "origin_lat": origin_lat,
            "origin_lon": origin_lon,
        },
    )
    assert created.status_code == 202
    mission_id = created.json()["mission_id"]
    assert created.json()["discovered_site_ids"] == []

    session.add(
        Site(
            site_id=9301,
            latitude=origin_lat,
            longitude=origin_lon,
            data_source=DATA_SOURCE_FIELD,
        )
    )
    session.add(
        Site(
            site_id=9302,
            latitude=origin_lat + 0.01,
            longitude=origin_lon,
            data_source=DATA_SOURCE_FIELD,
        )
    )
    session.commit()

    now = datetime.utcnow()
    session.add(
        ToolMissionEvent(
            mission_id=mission_id,
            event_type="discover_site",
            site_id=9301,
            due_at=now - timedelta(seconds=10),
            status=EVENT_STATUS_DONE,
            lat=origin_lat,
            lon=origin_lon,
            distance_along_km=0.0,
            processed_at=now,
        )
    )
    session.add(
        ToolMissionEvent(
            mission_id=mission_id,
            event_type="discover_site",
            site_id=9302,
            due_at=now - timedelta(seconds=5),
            status=EVENT_STATUS_MISS,
            lat=origin_lat + 0.01,
            lon=origin_lon,
            distance_along_km=1.0,
            processed_at=now,
        )
    )
    session.commit()

    listed = client.get(
        "/api/v1/tools/missions/aerial-recon",
        headers=_auth_headers(user),
    )
    assert listed.status_code == 200
    items = listed.json()["items"]
    assert len(items) == 1
    assert items[0]["discovered_site_ids"] == [9301]


def test_promote_schedules_events_in_route_order(session: Session):
    tool = _aerial_tool(session)
    user = _user(session)
    _grant(session, user_id=int(user.id), tool_id=int(tool.id))
    origin_lat, origin_lon = 40.0, -100.0
    route = _square_route(origin_lat, origin_lon, delta=0.02)
    mission = start_aerial_recon_mission(
        session,
        user_id=int(user.id),
        tool_id=int(tool.id),
        route=route,
        origin_lat=origin_lat,
        origin_lon=origin_lon,
    )

    # Sites near first leg and later corner.
    session.add(
        Site(
            site_id=9001,
            latitude=origin_lat + 0.005,
            longitude=origin_lon,
            data_source=DATA_SOURCE_FIELD,
        )
    )
    session.add(
        Site(
            site_id=9002,
            latitude=origin_lat + 0.02,
            longitude=origin_lon + 0.02,
            data_source=DATA_SOURCE_FIELD,
        )
    )
    session.commit()

    # Mark ensures done so promote does not wait.
    for job in session.exec(select(FieldEnsureJob)).all():
        job.status = "done"
        session.add(job)
    session.commit()

    promoted = promote_ensuring_missions(session)
    assert promoted == 1
    session.refresh(mission)
    assert mission.status == MISSION_STATUS_FLYING

    events = list(
        session.exec(
            select(ToolMissionEvent)
            .where(ToolMissionEvent.mission_id == mission.id)
            .order_by(ToolMissionEvent.distance_along_km)
        ).all()
    )
    assert len(events) >= 2
    assert events[0].site_id == 9001
    assert events[-1].site_id == 9002
    assert events[0].due_at <= events[-1].due_at


def test_due_events_discover_and_miss(session: Session):
    tool = _aerial_tool(session)
    user = _user(session)
    _grant(session, user_id=int(user.id), tool_id=int(tool.id))
    now = datetime.utcnow()
    mission = ToolMission(
        user_id=int(user.id),
        tool_id=int(tool.id),
        action_key=ACTION_KEY_AERIAL_RECON,
        status=MISSION_STATUS_FLYING,
        route_json=json.dumps(
            [{"lat": 40.0, "lon": -100.0}, {"lat": 40.01, "lon": -100.0}]
        ),
        route_length_km=1.0,
        flight_duration_s=60,
        flight_started_at=now - timedelta(minutes=1),
        flight_ends_at=now + timedelta(hours=1),
        created_at=now,
        updated_at=now,
    )
    session.add(mission)
    session.commit()
    session.refresh(mission)

    session.add(
        Site(
            site_id=9101,
            latitude=40.0,
            longitude=-100.0,
            data_source=DATA_SOURCE_FIELD,
        )
    )
    session.add(
        Site(
            site_id=9102,
            latitude=40.005,
            longitude=-100.0,
            data_source=DATA_SOURCE_FIELD,
        )
    )
    session.add(
        ToolMissionEvent(
            mission_id=int(mission.id),
            event_type="discover_site",
            site_id=9101,
            due_at=now - timedelta(seconds=5),
            status=EVENT_STATUS_PENDING,
            lat=40.0,
            lon=-100.0,
            distance_along_km=0.0,
        )
    )
    session.add(
        ToolMissionEvent(
            mission_id=int(mission.id),
            event_type="discover_site",
            site_id=9102,
            due_at=now - timedelta(seconds=1),
            status=EVENT_STATUS_PENDING,
            lat=40.005,
            lon=-100.0,
            distance_along_km=0.5,
        )
    )
    session.commit()

    # First always hits, second always misses.
    class _SeqRng:
        def __init__(self, values: list[float]):
            self._values = list(values)

        def random(self) -> float:
            return self._values.pop(0)

    processed = process_due_mission_events(
        session, rng=_SeqRng([0.0, 0.99])
    )
    assert processed == 2
    events = {
        e.site_id: e
        for e in session.exec(select(ToolMissionEvent)).all()
    }
    assert events[9101].status == EVENT_STATUS_DONE
    assert events[9102].status == EVENT_STATUS_MISS


def test_tool_summary_includes_action(client, session: Session):
    tool = _aerial_tool(session)
    admin = User(
        username="admin",
        email="admin@example.com",
        password="x",
        is_admin=True,
    )
    session.add(admin)
    session.commit()
    session.refresh(admin)

    response = client.get(
        f"/api/v1/tools/{tool.id}",
        headers=_auth_headers(admin),
    )
    assert response.status_code == 200
    assert response.json()["action"] == "Deploy"


def test_game_config_loads_aerial_recon():
    get_game_config.cache_clear()
    cfg = get_game_config().tool_actions.aerial_recon
    assert cfg.max_route_km == 100
    assert cfg.flight_speed_kmh == 50
    assert 0 < cfg.discovery_chance <= 1


def test_point_at_fraction_matches_discovery_timing():
    from app.services.tool_action_service.route_geometry import (
        RoutePoint,
        point_at_fraction,
        route_length_km,
    )

    route = [
        RoutePoint(40.0, -100.0),
        RoutePoint(40.1, -100.0),
        RoutePoint(40.1, -99.9),
    ]
    length = route_length_km(route)
    mid = point_at_fraction(route, 0.5)
    # Midpoint should be roughly halfway along arc.
    from app.services.site_service.geo_utils import haversine_km

    along = haversine_km(route[0].lat, route[0].lon, mid.lat, mid.lon)
    assert abs(along / length - 0.5) < 0.05


def test_prefix_up_to_fraction():
    from app.services.tool_action_service.route_geometry import (
        RoutePoint,
        prefix_up_to_fraction,
        route_length_km,
    )

    route = [
        RoutePoint(40.0, -100.0),
        RoutePoint(40.1, -100.0),
        RoutePoint(40.1, -99.9),
    ]
    assert prefix_up_to_fraction(route, 0.0) == [route[0]]
    assert prefix_up_to_fraction(route, 1.0) == route
    half = prefix_up_to_fraction(route, 0.5)
    assert half[0] == route[0]
    assert len(half) >= 2
    assert abs(route_length_km(half) / route_length_km(route) - 0.5) < 0.05


def test_cancel_flying_truncates_and_skips_pending(client, session: Session):
    tool = _aerial_tool(session)
    user = _user(session)
    _grant(session, user_id=int(user.id), tool_id=int(tool.id))
    now = datetime.utcnow()
    full_route = _square_route(40.0, -100.0, delta=0.02)
    mission = ToolMission(
        user_id=int(user.id),
        tool_id=int(tool.id),
        action_key=ACTION_KEY_AERIAL_RECON,
        status=MISSION_STATUS_FLYING,
        route_json=json.dumps(full_route),
        route_length_km=8.0,
        flight_duration_s=100,
        flight_started_at=now - timedelta(seconds=40),
        flight_ends_at=now + timedelta(seconds=60),
        created_at=now - timedelta(seconds=40),
        updated_at=now - timedelta(seconds=40),
    )
    session.add(mission)
    session.commit()
    session.refresh(mission)

    session.add(
        ToolMissionEvent(
            mission_id=int(mission.id),
            event_type="discover_site",
            site_id=9201,
            due_at=now - timedelta(seconds=10),
            status=EVENT_STATUS_DONE,
            lat=40.0,
            lon=-100.0,
            distance_along_km=0.0,
            processed_at=now - timedelta(seconds=10),
        )
    )
    session.add(
        ToolMissionEvent(
            mission_id=int(mission.id),
            event_type="discover_site",
            site_id=9202,
            due_at=now + timedelta(seconds=30),
            status=EVENT_STATUS_PENDING,
            lat=40.02,
            lon=-100.0,
            distance_along_km=4.0,
        )
    )
    session.commit()

    original_len = mission.route_length_km
    response = client.post(
        f"/api/v1/tools/missions/aerial-recon/{mission.id}/cancel",
        headers=_auth_headers(user),
    )
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == MISSION_STATUS_CANCELLED
    assert body["route_length_km"] < original_len
    assert len(body["route"]) >= 2
    assert body["route"][0]["lat"] == full_route[0]["lat"]

    session.refresh(mission)
    assert mission.status == MISSION_STATUS_CANCELLED
    events = {
        e.site_id: e
        for e in session.exec(select(ToolMissionEvent)).all()
    }
    assert events[9201].status == EVENT_STATUS_DONE
    assert events[9202].status == EVENT_STATUS_SKIPPED


def test_cancel_done_rejected(client, session: Session):
    tool = _aerial_tool(session)
    user = _user(session)
    _grant(session, user_id=int(user.id), tool_id=int(tool.id))
    now = datetime.utcnow()
    mission = ToolMission(
        user_id=int(user.id),
        tool_id=int(tool.id),
        action_key=ACTION_KEY_AERIAL_RECON,
        status=MISSION_STATUS_DONE,
        route_json=json.dumps(_square_route(40.0, -100.0)),
        route_length_km=4.0,
        flight_duration_s=60,
        flight_started_at=now - timedelta(minutes=5),
        flight_ends_at=now - timedelta(minutes=1),
        created_at=now - timedelta(minutes=5),
        updated_at=now - timedelta(minutes=1),
    )
    session.add(mission)
    session.commit()
    session.refresh(mission)

    response = client.post(
        f"/api/v1/tools/missions/aerial-recon/{mission.id}/cancel",
        headers=_auth_headers(user),
    )
    assert response.status_code == 400
    assert "in-progress" in response.json()["detail"].lower()


def test_new_mission_allowed_after_cancel(client, session: Session):
    tool = _aerial_tool(session)
    user = _user(session)
    _grant(session, user_id=int(user.id), tool_id=int(tool.id))
    origin_lat, origin_lon = 40.0, -100.0
    route = _square_route(origin_lat, origin_lon)

    first = client.post(
        f"/api/v1/tools/{tool.id}/actions/aerial-recon",
        headers=_auth_headers(user),
        json={
            "route": route,
            "origin_lat": origin_lat,
            "origin_lon": origin_lon,
        },
    )
    assert first.status_code == 202
    mission_id = first.json()["mission_id"]

    blocked = client.post(
        f"/api/v1/tools/{tool.id}/actions/aerial-recon",
        headers=_auth_headers(user),
        json={
            "route": route,
            "origin_lat": origin_lat,
            "origin_lon": origin_lon,
        },
    )
    assert blocked.status_code == 400

    cancelled = client.post(
        f"/api/v1/tools/missions/aerial-recon/{mission_id}/cancel",
        headers=_auth_headers(user),
    )
    assert cancelled.status_code == 200
    assert cancelled.json()["status"] == MISSION_STATUS_CANCELLED

    second = client.post(
        f"/api/v1/tools/{tool.id}/actions/aerial-recon",
        headers=_auth_headers(user),
        json={
            "route": route,
            "origin_lat": origin_lat,
            "origin_lon": origin_lon,
        },
    )
    assert second.status_code == 202
    assert second.json()["mission_id"] != mission_id


def test_cancel_service_ensuring_truncates_to_start(session: Session):
    tool = _aerial_tool(session)
    user = _user(session)
    _grant(session, user_id=int(user.id), tool_id=int(tool.id))
    origin_lat, origin_lon = 40.0, -100.0
    mission = start_aerial_recon_mission(
        session,
        user_id=int(user.id),
        tool_id=int(tool.id),
        route=_square_route(origin_lat, origin_lon),
        origin_lat=origin_lat,
        origin_lon=origin_lon,
    )
    assert mission.status == MISSION_STATUS_ENSURING
    cancelled = cancel_aerial_recon_mission(
        session, user_id=int(user.id), mission_id=int(mission.id)
    )
    assert cancelled.status == MISSION_STATUS_CANCELLED
    route = json.loads(cancelled.route_json)
    assert len(route) == 1
    assert route[0]["lat"] == origin_lat
    assert cancelled.route_length_km == 0.0
