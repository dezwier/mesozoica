"""Tests for Terrain Echo timed sessions."""

from __future__ import annotations

from datetime import datetime, timedelta

import pytest
from sqlmodel import Session, select

from app.core.exceptions import ValidationError
from app.core.game_config import get_game_config
from app.core.security import create_access_token
from app.models.tool import Tool
from app.models.tool_session import (
    ACTION_KEY_ORBIT_SURVEY,
    ACTION_KEY_TERRAIN_ECHO,
    SESSION_STATUS_ACTIVE,
    SESSION_STATUS_CANCELLED,
    SESSION_STATUS_COMPLETED,
    ToolSession,
)
from app.models.tool_type import ToolType
from app.models.user import User
from app.models.user_tool import USER_TOOL_ACTION_OWNED, UserTool
from app.services.tool_action_service.tool_session import (
    get_active_timed_session,
    start_timed_session,
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


def _grant(
    session: Session,
    *,
    user_id: int,
    tool_id: int,
    params_json: dict | None = None,
) -> Tool:
    instance = Tool(
        tool_type_id=tool_id,
        level=1,
        params_json=params_json,
    )
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
        f"/api/v1/tools/{echo.id}/sessions",
        headers=headers,
    )
    assert first.status_code in (201, 202), first.text
    body = first.json()
    assert body["action_key"] == ACTION_KEY_TERRAIN_ECHO
    assert body["status"] == SESSION_STATUS_ACTIVE
    assert body["params"]["duration_minutes"] == 5
    assert body["params"]["accuracy"] == 0.0
    assert body["params"]["range_m"] == 20.0
    assert "degrees" not in body["params"]

    second = client.post(
        f"/api/v1/tools/{echo.id}/sessions",
        headers=headers,
    )
    assert second.status_code == 400
    assert "Terrain Echo is already in use" in second.json()["detail"]
    rows = session.exec(select(ToolSession)).all()
    assert len(rows) == 1
    assert rows[0].status == SESSION_STATUS_ACTIVE


def test_cancel_and_restore_terrain_echo(client, session: Session) -> None:
    user = _user(session)
    echo = _tool(session, name="Terrain Echo")
    _grant(session, user_id=int(user.id), tool_id=int(echo.id))
    headers = _auth_headers(user)

    started = client.post(
        f"/api/v1/tools/{echo.id}/sessions",
        headers=headers,
    )
    assert started.status_code in (201, 202)
    session_id = started.json()["session_id"]

    active = client.get(
        "/api/v1/tools/sessions/active",
        headers=headers,
        params={"action_key": ACTION_KEY_TERRAIN_ECHO},
    )
    assert active.status_code == 200
    assert len(active.json()["items"]) == 1
    assert active.json()["items"][0]["status"] == SESSION_STATUS_ACTIVE

    cancelled = client.post(
        f"/api/v1/tools/sessions/{session_id}/cancel",
        headers=headers,
    )
    assert cancelled.status_code == 200
    assert cancelled.json()["status"] == SESSION_STATUS_CANCELLED

    missing = client.get(
        "/api/v1/tools/sessions/active",
        headers=headers,
        params={"action_key": ACTION_KEY_TERRAIN_ECHO},
    )
    assert missing.status_code == 200
    assert missing.json()["items"] == []


def test_expired_terrain_echo_session_ignored(session: Session) -> None:
    user = _user(session)
    echo = _tool(session, name="Terrain Echo")
    instance = _grant(session, user_id=int(user.id), tool_id=int(echo.id))
    now = datetime.utcnow()
    session.add(
        ToolSession(
            user_id=int(user.id),
            tool_id=int(instance.id),
            action_key=ACTION_KEY_TERRAIN_ECHO,
            status=SESSION_STATUS_ACTIVE,
            started_at=now - timedelta(minutes=10),
            expires_at=now - timedelta(minutes=1),
            params_json={
                "duration_minutes": 5,
                "accuracy": 0.0,
                "range_m": 20.0,
            },
            state_json={},
            created_at=now - timedelta(minutes=10),
            updated_at=now - timedelta(minutes=10),
        )
    )
    session.commit()
    assert (
        get_active_timed_session(
            session,
            user_id=int(user.id),
            action_keys=(ACTION_KEY_TERRAIN_ECHO,),
        )
        is None
    )
    row = session.exec(select(ToolSession)).one()
    assert row.status == SESSION_STATUS_COMPLETED


def test_start_terrain_echo_uses_partial_remaining_battery(
    client, session: Session
) -> None:
    """Terrain Echo must start on whatever time is left (< catalog min)."""
    get_game_config.cache_clear()
    user = _user(session, username="echo_partial")
    echo = _tool(session, name="Terrain Echo")
    instance = _grant(
        session,
        user_id=int(user.id),
        tool_id=int(echo.id),
        params_json={"duration_minutes": 5},
    )
    now = datetime.utcnow()
    session.add(
        ToolSession(
            user_id=int(user.id),
            tool_id=int(instance.id),
            action_key=ACTION_KEY_TERRAIN_ECHO,
            status=SESSION_STATUS_COMPLETED,
            started_at=now - timedelta(minutes=4),
            expires_at=now - timedelta(minutes=2),
            ended_at=now - timedelta(minutes=2),
            used_duration_s=3 * 60,
            params_json={"duration_minutes": 5, "accuracy": 0.0, "range_m": 20.0},
            state_json={},
            created_at=now - timedelta(minutes=4),
            updated_at=now - timedelta(minutes=2),
        )
    )
    session.commit()
    headers = _auth_headers(user)

    started = client.post(
        f"/api/v1/tools/{echo.id}/sessions",
        headers=headers,
    )
    assert started.status_code in (201, 202), started.text
    body = started.json()
    assert body["action_key"] == ACTION_KEY_TERRAIN_ECHO
    assert body["status"] == SESSION_STATUS_ACTIVE
    # ~2 minutes left → ceil to minutes in params
    assert body["params"]["duration_minutes"] == 2


def test_rejects_when_orbit_survey_already_in_use(session: Session) -> None:
    user = _user(session)
    echo = _tool(session, name="Terrain Echo")
    orbit = _tool(session, name="Orbit Survey", action="Scan")
    _grant(session, user_id=int(user.id), tool_id=int(echo.id))
    _grant(session, user_id=int(user.id), tool_id=int(orbit.id))

    start_timed_session(
        session, user_id=int(user.id), tool_id=int(orbit.id)
    )
    assert (
        get_active_timed_session(
            session,
            user_id=int(user.id),
            action_keys=(ACTION_KEY_ORBIT_SURVEY,),
        )
        is not None
    )

    with pytest.raises(ValidationError, match="Orbit Survey is already in use"):
        start_timed_session(
            session, user_id=int(user.id), tool_id=int(echo.id)
        )
    assert (
        get_active_timed_session(
            session,
            user_id=int(user.id),
            action_keys=(ACTION_KEY_ORBIT_SURVEY,),
        )
        is not None
    )
    assert (
        get_active_timed_session(
            session,
            user_id=int(user.id),
            action_keys=(ACTION_KEY_TERRAIN_ECHO,),
        )
        is None
    )
