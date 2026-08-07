"""Tests for aerial tool sessions (recon + scout)."""

from __future__ import annotations

from datetime import datetime, timedelta

from sqlmodel import Session, select

from app.core.game_config import get_game_config
from app.core.security import create_access_token
from app.models.data_source import DATA_SOURCE_FIELD
from app.models.field_ensure_job import FieldEnsureJob
from app.models.site import Site
from app.models.tool import Tool
from app.models.tool_type import ToolType
from app.models.tool_session import (
    ACTION_KEY_AERIAL_RECON,
    ACTION_KEY_AERIAL_SCOUT,
    SESSION_STATUS_ACTIVE,
    SESSION_STATUS_CANCELLED,
    SESSION_STATUS_COMPLETED,
    SESSION_STATUS_PENDING,
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
from app.models.user import User
from app.models.user_tool import USER_TOOL_ACTION_OWNED, UserTool
from app.services.tool_action_service.tool_session import (
    cancel_aerial_session,
    process_due_events,
    promote_pending_sessions,
    start_aerial_session,
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


def _aerial_tool(
    session: Session,
    *,
    name: str = "Aerial Recon",
    scientific_tool: str = "helicopter",
    rarity: int = 5,
    action: str = "Deploy",
) -> ToolType:
    tool = ToolType(
        name=name,
        category="1 field_survey",
        scientific_tool=scientific_tool,
        description="Aerial loop",
        rarity=rarity,
        action=action,
    )
    session.add(tool)
    session.commit()
    session.refresh(tool)
    return tool


def _scout_tool(session: Session) -> ToolType:
    return _aerial_tool(
        session,
        name="Aerial Scout",
        scientific_tool="drone",
        rarity=2,
        action="Launch",
    )


def _grant(session: Session, *, user_id: int, tool_id: int) -> Tool:
    instance = Tool(tool_type_id=tool_id, level=1)
    session.add(instance)
    session.flush()
    session.add(
        UserTool(
            user_id=user_id,
            tool_id=int(instance.id),
            action=USER_TOOL_ACTION_OWNED,
        )
    )
    session.commit()
    session.refresh(instance)
    return instance


def _square_route(origin_lat: float, origin_lon: float, *, delta: float = 0.01):
    """Small closed-ish loop (~few km) starting/ending at origin."""
    return [
        {"lat": origin_lat, "lon": origin_lon},
        {"lat": origin_lat + delta, "lon": origin_lon},
        {"lat": origin_lat + delta, "lon": origin_lon + delta},
        {"lat": origin_lat, "lon": origin_lon + delta},
        {"lat": origin_lat, "lon": origin_lon},
    ]


def _start_url(tool_id: int) -> str:
    return f"/api/v1/tools/{tool_id}/sessions"


def test_aerial_session_rejects_unowned(client, session: Session):
    tool = _aerial_tool(session)
    user = _user(session)
    origin_lat, origin_lon = 40.0, -100.0
    response = client.post(
        _start_url(int(tool.id)),
        headers=_auth_headers(user),
        json={
            "route": _square_route(origin_lat, origin_lon),
            "origin_lat": origin_lat,
            "origin_lon": origin_lon,
        },
    )
    assert response.status_code == 400
    assert "own" in response.json()["detail"].lower()


def test_aerial_session_rejects_open_loop(client, session: Session):
    tool = _aerial_tool(session)
    user = _user(session)
    _grant(session, user_id=int(user.id), tool_id=int(tool.id))
    origin_lat, origin_lon = 40.0, -100.0
    route = _square_route(origin_lat, origin_lon, delta=0.005)
    # End ~200 m away — outside 75 m tolerance, still under max route length.
    route[-1] = {"lat": origin_lat + 0.002, "lon": origin_lon}
    response = client.post(
        _start_url(int(tool.id)),
        headers=_auth_headers(user),
        json={
            "route": route,
            "origin_lat": origin_lat,
            "origin_lon": origin_lon,
        },
    )
    assert response.status_code == 400
    assert "start and end" in response.json()["detail"].lower()


def test_aerial_session_rejects_overlong_route(client, session: Session):
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
        _start_url(int(tool.id)),
        headers=_auth_headers(user),
        json={
            "route": route,
            "origin_lat": origin_lat,
            "origin_lon": origin_lon,
        },
    )
    assert response.status_code == 400
    assert "maximum" in response.json()["detail"].lower()


def test_aerial_session_accepts_and_enqueues_ensure(client, session: Session):
    tool = _aerial_tool(session)
    user = _user(session)
    _grant(session, user_id=int(user.id), tool_id=int(tool.id))
    origin_lat, origin_lon = 40.0, -100.0
    response = client.post(
        _start_url(int(tool.id)),
        headers=_auth_headers(user),
        json={
            "route": _square_route(origin_lat, origin_lon),
            "origin_lat": origin_lat,
            "origin_lon": origin_lon,
        },
    )
    assert response.status_code == 202
    body = response.json()
    assert body["status"] == SESSION_STATUS_PENDING
    assert body["session_id"] > 0
    assert body["action_key"] == ACTION_KEY_AERIAL_RECON
    state = body["state"]
    params = body["params"]
    assert state["route_length_km"] > 0
    assert state["flight_duration_s"] > 0
    assert len(state["route"]) >= 3
    expected_s = max(1, int(round(state["route_length_km"] / 50.0 * 3600.0)))
    assert state["flight_duration_s"] == expected_s

    rows = list(session.exec(select(ToolSession)).all())
    assert len(rows) == 1
    assert rows[0].action_key == ACTION_KEY_AERIAL_RECON
    assert rows[0].state_json["flight_duration_s"] == expected_s
    cfg = get_game_config().tool_actions.aerial_recon
    assert params["flight_speed_kmh"] == cfg.flight_speed_kmh
    assert params["max_route_km"] == cfg.max_route_km
    assert params["flight_discovery_chance"] == cfg.flight_discovery_chance
    assert params["flight_discovery_distance_m"] == cfg.flight_discovery_distance_m
    job_ids = rows[0].state_json.get("ensure_job_ids") or []
    assert len(job_ids) >= 1
    jobs = list(session.exec(select(FieldEnsureJob)).all())
    assert len(jobs) >= 1


def test_aerial_scout_accepts_with_scout_config(client, session: Session):
    tool = _scout_tool(session)
    user = _user(session)
    _grant(session, user_id=int(user.id), tool_id=int(tool.id))
    origin_lat, origin_lon = 40.0, -100.0
    response = client.post(
        _start_url(int(tool.id)),
        headers=_auth_headers(user),
        json={
            "route": _square_route(origin_lat, origin_lon, delta=0.005),
            "origin_lat": origin_lat,
            "origin_lon": origin_lon,
        },
    )
    assert response.status_code == 202
    body = response.json()
    assert body["action_key"] == ACTION_KEY_AERIAL_SCOUT
    cfg = get_game_config().tool_actions.aerial_scout
    params = body["params"]
    state = body["state"]
    assert params["flight_speed_kmh"] == cfg.flight_speed_kmh
    assert params["max_route_km"] == cfg.max_route_km
    assert params["flight_discovery_chance"] == cfg.flight_discovery_chance
    assert (
        params["flight_discovery_distance_m"] == cfg.flight_discovery_distance_m
    )
    expected_s = max(
        1, int(round(state["route_length_km"] / cfg.flight_speed_kmh * 3600.0))
    )
    assert state["flight_duration_s"] == expected_s


def test_list_active_aerial_sessions(client, session: Session):
    tool = _aerial_tool(session)
    user = _user(session)
    other = _user(session, username="other")
    _grant(session, user_id=int(user.id), tool_id=int(tool.id))
    _grant(session, user_id=int(other.id), tool_id=int(tool.id))
    origin_lat, origin_lon = 40.0, -100.0
    route = _square_route(origin_lat, origin_lon)

    created = client.post(
        _start_url(int(tool.id)),
        headers=_auth_headers(user),
        json={
            "route": route,
            "origin_lat": origin_lat,
            "origin_lon": origin_lon,
        },
    )
    assert created.status_code == 202
    session_id = created.json()["session_id"]

    other_resp = client.post(
        _start_url(int(tool.id)),
        headers=_auth_headers(other),
        json={
            "route": route,
            "origin_lat": origin_lat,
            "origin_lon": origin_lon,
        },
    )
    assert other_resp.status_code == 202

    listed = client.get(
        "/api/v1/tools/sessions/active",
        headers=_auth_headers(user),
        params={"action_key": ACTION_KEY_AERIAL_RECON},
    )
    assert listed.status_code == 200
    items = listed.json()["items"]
    assert len(items) == 1
    assert items[0]["session_id"] == session_id
    assert items[0]["status"] == SESSION_STATUS_PENDING
    assert items[0]["action_key"] == ACTION_KEY_AERIAL_RECON
    assert len(items[0]["state"]["route"]) >= 3
    assert items[0]["events_summary"]["discovered_site_ids"] == []

    unauth = client.get("/api/v1/tools/sessions/active")
    assert unauth.status_code in (401, 403)


def test_list_aerial_session_includes_discovered_site_ids(client, session: Session):
    tool = _aerial_tool(session)
    user = _user(session)
    _grant(session, user_id=int(user.id), tool_id=int(tool.id))
    origin_lat, origin_lon = 40.0, -100.0
    route = _square_route(origin_lat, origin_lon)

    created = client.post(
        _start_url(int(tool.id)),
        headers=_auth_headers(user),
        json={
            "route": route,
            "origin_lat": origin_lat,
            "origin_lon": origin_lon,
        },
    )
    assert created.status_code == 202
    session_id = created.json()["session_id"]
    assert created.json()["events_summary"]["discovered_site_ids"] == []

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
        ToolSessionEvent(
            session_id=session_id,
            event_type=EVENT_TYPE_DISCOVER_SITE,
            site_id=9301,
            due_at=now - timedelta(seconds=10),
            status=EVENT_STATUS_DONE,
            lat=origin_lat,
            lon=origin_lon,
            payload_json={"distance_along_km": 0.0},
            processed_at=now,
        )
    )
    session.add(
        ToolSessionEvent(
            session_id=session_id,
            event_type=EVENT_TYPE_DISCOVER_SITE,
            site_id=9302,
            due_at=now - timedelta(seconds=5),
            status=EVENT_STATUS_MISS,
            lat=origin_lat + 0.01,
            lon=origin_lon,
            payload_json={"distance_along_km": 1.0},
            processed_at=now,
        )
    )
    session.commit()

    listed = client.get(
        "/api/v1/tools/sessions/active",
        headers=_auth_headers(user),
        params={"action_key": ACTION_KEY_AERIAL_RECON},
    )
    assert listed.status_code == 200
    items = listed.json()["items"]
    assert len(items) == 1
    assert items[0]["events_summary"]["discovered_site_ids"] == [9301]


def test_promote_schedules_events_in_route_order(session: Session):
    tool = _aerial_tool(session)
    user = _user(session)
    _grant(session, user_id=int(user.id), tool_id=int(tool.id))
    origin_lat, origin_lon = 40.0, -100.0
    route = _square_route(origin_lat, origin_lon, delta=0.02)
    row = start_aerial_session(
        session,
        user_id=int(user.id),
        tool_id=int(tool.id),
        route=route,
        origin_lat=origin_lat,
        origin_lon=origin_lon,
    )

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

    for job in session.exec(select(FieldEnsureJob)).all():
        job.status = "done"
        session.add(job)
    session.commit()

    promoted = promote_pending_sessions(session)
    assert promoted == 1
    session.refresh(row)
    assert row.status == SESSION_STATUS_ACTIVE

    events = list(
        session.exec(
            select(ToolSessionEvent).where(
                ToolSessionEvent.session_id == row.id
            )
        ).all()
    )
    events.sort(key=lambda e: float(e.payload_json.get("distance_along_km", 0)))
    assert len(events) >= 2
    assert events[0].site_id == 9001
    assert events[-1].site_id == 9002
    assert events[0].due_at <= events[-1].due_at


def test_due_events_discover_and_miss(session: Session):
    tool = _aerial_tool(session)
    user = _user(session)
    instance = _grant(session, user_id=int(user.id), tool_id=int(tool.id))
    now = datetime.utcnow()
    row = ToolSession(
        user_id=int(user.id),
        tool_id=int(instance.id),
        action_key=ACTION_KEY_AERIAL_RECON,
        status=SESSION_STATUS_ACTIVE,
        started_at=now - timedelta(minutes=1),
        params_json={
            "flight_speed_kmh": 50.0,
            "max_route_km": 50.0,
            "discovery_chance": 0.5,
            "visibility_distance_m": 100.0,
        },
        state_json={
            "route": [{"lat": 40.0, "lon": -100.0}, {"lat": 40.01, "lon": -100.0}],
            "route_length_km": 1.0,
            "flight_duration_s": 60,
            "flight_started_at": (now - timedelta(minutes=1)).isoformat(),
            "flight_ends_at": (now + timedelta(hours=1)).isoformat(),
            "ensure_job_ids": [],
        },
        created_at=now,
        updated_at=now,
    )
    session.add(row)
    session.commit()
    session.refresh(row)

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
        ToolSessionEvent(
            session_id=int(row.id),
            event_type=EVENT_TYPE_DISCOVER_SITE,
            site_id=9101,
            due_at=now - timedelta(seconds=5),
            status=EVENT_STATUS_PENDING,
            lat=40.0,
            lon=-100.0,
            payload_json={"distance_along_km": 0.0},
        )
    )
    session.add(
        ToolSessionEvent(
            session_id=int(row.id),
            event_type=EVENT_TYPE_DISCOVER_SITE,
            site_id=9102,
            due_at=now - timedelta(seconds=1),
            status=EVENT_STATUS_PENDING,
            lat=40.005,
            lon=-100.0,
            payload_json={"distance_along_km": 0.5},
        )
    )
    session.commit()

    class _SeqRng:
        def __init__(self, values: list[float]):
            self._values = list(values)

        def random(self) -> float:
            return self._values.pop(0)

    processed = process_due_events(session, rng=_SeqRng([0.0, 0.99]))
    assert processed == 2
    events = {
        e.site_id: e
        for e in session.exec(select(ToolSessionEvent)).all()
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


def test_game_config_loads_aerial_session():
    get_game_config.cache_clear()
    recon = get_game_config().tool_actions.aerial_recon
    assert recon.duration_minutes == 60
    assert recon.flight_speed_kmh == 50
    assert recon.max_route_km == 50
    assert 0 < recon.flight_discovery_chance <= 1
    scout = get_game_config().tool_actions.aerial_scout
    assert scout.duration_minutes == 10
    assert scout.flight_speed_kmh == 35
    assert scout.max_route_km == 35.0 * 10 / 60
    assert 0 < scout.flight_discovery_chance <= 1
    assert scout.flight_discovery_distance_m == 50


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
    from app.services.site_common.geo_utils import haversine_km

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


def test_cells_along_route_covers_crossed_squares():
    from app.services.site_common.survey_grid import cell_indices
    from app.services.tool_action_service.route_geometry import (
        RoutePoint,
        cells_along_route,
        route_length_km,
    )

    route = [
        RoutePoint(40.0, -100.0),
        RoutePoint(40.1, -100.0),
    ]
    cell_m = 500.0
    cells = cells_along_route(route, cell_size_m=cell_m)
    assert len(cells) >= int(route_length_km(route) * 1000 / cell_m) - 1

    keys = {
        cell_indices(p.lat, p.lon, cell_size_m=cell_m) for p in cells
    }
    assert len(keys) == len(cells)
    start_key = cell_indices(route[0].lat, route[0].lon, cell_size_m=cell_m)
    end_key = cell_indices(route[1].lat, route[1].lon, cell_size_m=cell_m)
    assert start_key in keys
    assert end_key in keys


def test_cancel_active_truncates_and_skips_pending(client, session: Session):
    tool = _aerial_tool(session)
    user = _user(session)
    instance = _grant(session, user_id=int(user.id), tool_id=int(tool.id))
    now = datetime.utcnow()
    full_route = _square_route(40.0, -100.0, delta=0.02)
    row = ToolSession(
        user_id=int(user.id),
        tool_id=int(instance.id),
        action_key=ACTION_KEY_AERIAL_RECON,
        status=SESSION_STATUS_ACTIVE,
        started_at=now - timedelta(seconds=40),
        params_json={
            "flight_speed_kmh": 50.0,
            "max_route_km": 50.0,
            "discovery_chance": 0.5,
            "visibility_distance_m": 100.0,
        },
        state_json={
            "route": full_route,
            "route_length_km": 8.0,
            "flight_duration_s": 100,
            "flight_started_at": (now - timedelta(seconds=40)).isoformat(),
            "flight_ends_at": (now + timedelta(seconds=60)).isoformat(),
            "ensure_job_ids": [],
        },
        created_at=now - timedelta(seconds=40),
        updated_at=now - timedelta(seconds=40),
    )
    session.add(row)
    session.commit()
    session.refresh(row)

    session.add(
        ToolSessionEvent(
            session_id=int(row.id),
            event_type=EVENT_TYPE_DISCOVER_SITE,
            site_id=9201,
            due_at=now - timedelta(seconds=10),
            status=EVENT_STATUS_DONE,
            lat=40.0,
            lon=-100.0,
            payload_json={"distance_along_km": 0.0},
            processed_at=now - timedelta(seconds=10),
        )
    )
    session.add(
        ToolSessionEvent(
            session_id=int(row.id),
            event_type=EVENT_TYPE_DISCOVER_SITE,
            site_id=9202,
            due_at=now + timedelta(seconds=30),
            status=EVENT_STATUS_PENDING,
            lat=40.02,
            lon=-100.0,
            payload_json={"distance_along_km": 4.0},
        )
    )
    session.commit()

    original_len = float(row.state_json["route_length_km"])
    response = client.post(
        f"/api/v1/tools/sessions/{row.id}/cancel",
        headers=_auth_headers(user),
    )
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == SESSION_STATUS_CANCELLED
    assert body["state"]["route_length_km"] < original_len
    assert len(body["state"]["route"]) >= 2
    assert body["state"]["route"][0]["lat"] == full_route[0]["lat"]

    session.refresh(row)
    assert row.status == SESSION_STATUS_CANCELLED
    events = {
        e.site_id: e
        for e in session.exec(select(ToolSessionEvent)).all()
    }
    assert events[9201].status == EVENT_STATUS_DONE
    assert events[9202].status == EVENT_STATUS_SKIPPED


def test_cancel_completed_rejected(client, session: Session):
    tool = _aerial_tool(session)
    user = _user(session)
    instance = _grant(session, user_id=int(user.id), tool_id=int(tool.id))
    now = datetime.utcnow()
    row = ToolSession(
        user_id=int(user.id),
        tool_id=int(instance.id),
        action_key=ACTION_KEY_AERIAL_RECON,
        status=SESSION_STATUS_COMPLETED,
        started_at=now - timedelta(minutes=5),
        ended_at=now - timedelta(minutes=1),
        used_duration_s=60,
        params_json={},
        state_json={
            "route": _square_route(40.0, -100.0),
            "route_length_km": 4.0,
            "flight_duration_s": 60,
            "flight_started_at": (now - timedelta(minutes=5)).isoformat(),
            "flight_ends_at": (now - timedelta(minutes=1)).isoformat(),
        },
        created_at=now - timedelta(minutes=5),
        updated_at=now - timedelta(minutes=1),
    )
    session.add(row)
    session.commit()
    session.refresh(row)

    response = client.post(
        f"/api/v1/tools/sessions/{row.id}/cancel",
        headers=_auth_headers(user),
    )
    assert response.status_code == 400
    assert "in-progress" in response.json()["detail"].lower()


def test_new_session_allowed_after_cancel(client, session: Session):
    tool = _aerial_tool(session)
    user = _user(session)
    _grant(session, user_id=int(user.id), tool_id=int(tool.id))
    origin_lat, origin_lon = 40.0, -100.0
    route = _square_route(origin_lat, origin_lon)

    first = client.post(
        _start_url(int(tool.id)),
        headers=_auth_headers(user),
        json={
            "route": route,
            "origin_lat": origin_lat,
            "origin_lon": origin_lon,
        },
    )
    assert first.status_code == 202
    session_id = first.json()["session_id"]

    blocked = client.post(
        _start_url(int(tool.id)),
        headers=_auth_headers(user),
        json={
            "route": route,
            "origin_lat": origin_lat,
            "origin_lon": origin_lon,
        },
    )
    assert blocked.status_code == 400

    cancelled = client.post(
        f"/api/v1/tools/sessions/{session_id}/cancel",
        headers=_auth_headers(user),
    )
    assert cancelled.status_code == 200
    assert cancelled.json()["status"] == SESSION_STATUS_CANCELLED

    second = client.post(
        _start_url(int(tool.id)),
        headers=_auth_headers(user),
        json={
            "route": route,
            "origin_lat": origin_lat,
            "origin_lon": origin_lon,
        },
    )
    assert second.status_code == 202
    assert second.json()["session_id"] != session_id


def test_cancel_service_pending_truncates_to_start(session: Session):
    tool = _aerial_tool(session)
    user = _user(session)
    _grant(session, user_id=int(user.id), tool_id=int(tool.id))
    origin_lat, origin_lon = 40.0, -100.0
    row = start_aerial_session(
        session,
        user_id=int(user.id),
        tool_id=int(tool.id),
        route=_square_route(origin_lat, origin_lon),
        origin_lat=origin_lat,
        origin_lon=origin_lon,
    )
    assert row.status == SESSION_STATUS_PENDING
    cancelled = cancel_aerial_session(
        session, user_id=int(user.id), session_id=int(row.id)
    )
    assert cancelled.status == SESSION_STATUS_CANCELLED
    route = cancelled.state_json["route"]
    assert len(route) == 1
    assert route[0]["lat"] == origin_lat
    assert cancelled.state_json["route_length_km"] == 0.0
