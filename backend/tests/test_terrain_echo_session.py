"""Tests for Terrain Echo timed sessions."""

from __future__ import annotations

from datetime import datetime, timedelta

from sqlmodel import Session, select

from app.core.game_config import get_game_config
from app.core.security import create_access_token
from app.models.terrain_echo_session import (
    ACTION_KEY_TERRAIN_ECHO,
    SESSION_STATUS_ACTIVE,
    SESSION_STATUS_CANCELLED,
    SESSION_STATUS_EXPIRED,
    TerrainEchoSession,
)
from app.models.orbit_survey_session import OrbitSurveySession
from app.models.tool import Tool
from app.models.tool_type import ToolType
from app.models.user import User
from app.models.user_tool import USER_TOOL_ACTION_OWNED, UserTool
from app.services.tool_action_service.orbit_survey_session import (
    get_active_orbit_survey_session,
    start_orbit_survey_session,
)
from app.services.tool_action_service.terrain_echo_session import (
    get_active_terrain_echo_session,
    start_terrain_echo_session,
)


def _auth_headers(user: User) -> dict[str, str]:
    token = create_access_token({"sub": str(user.id)})
    return {"Authorization": f"Bearer {token}"}


def _user(session: Session, *, username: str = "echo") -> User:
    user = User(
        username=username,
        email=f"{username}@example.com",
        password="x",
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    return user


def _tool(
    session: Session,
    *,
    name: str,
    action: str = "Ping",
) -> ToolType:
    tool = ToolType(
        name=name,
        category="1 site_discovery",
        scientific_tool="radar remote sensing",
        description="test",
        rarity=1,
        action=action,
    )
    session.add(tool)
    session.commit()
    session.refresh(tool)
    return tool


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


def test_tool_actions_yaml_loads_terrain_echo_knobs() -> None:
    get_game_config.cache_clear()
    cfg = get_game_config().tool_actions.terrain_echo
    assert cfg.duration_minutes == 5
    assert cfg.accuracy == 0.0
    assert cfg.range_m == 20.0
    assert cfg.min_range_m == 20.0
    assert cfg.max_range_m == 200.0
    assert cfg.ring_increment_m == 20.0
    assert cfg.sweep_period_s == 4.0


def test_start_terrain_echo_session_snapshots_and_replaces(
    client, session: Session
) -> None:
    user = _user(session)
    echo = _tool(session, name="Terrain Echo")
    _grant(session, user_id=int(user.id), tool_id=int(echo.id))
    headers = _auth_headers(user)

    first = client.post(
        f"/api/v1/tools/{echo.id}/actions/terrain-echo-session",
        headers=headers,
    )
    assert first.status_code == 201, first.text
    body = first.json()
    assert body["action_key"] == ACTION_KEY_TERRAIN_ECHO
    assert body["status"] == SESSION_STATUS_ACTIVE
    assert body["duration_minutes"] == 5
    assert body["accuracy"] == 0.0
    assert body["range_m"] == 20.0
    assert "degrees" not in body

    second = client.post(
        f"/api/v1/tools/{echo.id}/actions/terrain-echo-session",
        headers=headers,
    )
    assert second.status_code == 201, second.text
    rows = session.exec(select(TerrainEchoSession)).all()
    assert len(rows) == 2
    statuses = {r.status for r in rows}
    assert SESSION_STATUS_CANCELLED in statuses
    assert SESSION_STATUS_ACTIVE in statuses


def test_cancel_and_restore_terrain_echo(client, session: Session) -> None:
    user = _user(session)
    echo = _tool(session, name="Terrain Echo")
    _grant(session, user_id=int(user.id), tool_id=int(echo.id))
    headers = _auth_headers(user)

    started = client.post(
        f"/api/v1/tools/{echo.id}/actions/terrain-echo-session",
        headers=headers,
    )
    assert started.status_code == 201

    active = client.get(
        "/api/v1/tools/sessions/terrain-echo/active",
        headers=headers,
    )
    assert active.status_code == 200
    assert active.json()["status"] == SESSION_STATUS_ACTIVE

    cancelled = client.post(
        "/api/v1/tools/sessions/terrain-echo/cancel",
        headers=headers,
    )
    assert cancelled.status_code == 200
    assert cancelled.json()["status"] == SESSION_STATUS_CANCELLED

    missing = client.get(
        "/api/v1/tools/sessions/terrain-echo/active",
        headers=headers,
    )
    assert missing.status_code == 404


def test_expired_terrain_echo_session_ignored(session: Session) -> None:
    user = _user(session)
    echo = _tool(session, name="Terrain Echo")
    instance = _grant(session, user_id=int(user.id), tool_id=int(echo.id))
    now = datetime.utcnow()
    session.add(
        TerrainEchoSession(
            user_id=int(user.id),
            tool_id=int(instance.id),
            action_key=ACTION_KEY_TERRAIN_ECHO,
            status=SESSION_STATUS_ACTIVE,
            duration_minutes=5,
            accuracy=0.0,
            range_m=20.0,
            started_at=now - timedelta(minutes=10),
            expires_at=now - timedelta(minutes=1),
            created_at=now - timedelta(minutes=10),
            updated_at=now - timedelta(minutes=10),
        )
    )
    session.commit()
    assert get_active_terrain_echo_session(session, user_id=int(user.id)) is None
    row = session.exec(select(TerrainEchoSession)).one()
    assert row.status == SESSION_STATUS_EXPIRED


def test_mutual_cancel_with_orbit_survey(session: Session) -> None:
    user = _user(session)
    echo = _tool(session, name="Terrain Echo")
    orbit = _tool(session, name="Orbit Survey", action="Scan")
    _grant(session, user_id=int(user.id), tool_id=int(echo.id))
    _grant(session, user_id=int(user.id), tool_id=int(orbit.id))

    start_orbit_survey_session(
        session, user_id=int(user.id), tool_id=int(orbit.id)
    )
    assert get_active_orbit_survey_session(session, user_id=int(user.id)) is not None

    start_terrain_echo_session(
        session, user_id=int(user.id), tool_id=int(echo.id)
    )
    assert get_active_terrain_echo_session(session, user_id=int(user.id)) is not None
    assert get_active_orbit_survey_session(session, user_id=int(user.id)) is None
    assert any(
        r.status == SESSION_STATUS_CANCELLED
        for r in session.exec(select(OrbitSurveySession)).all()
    )
