"""Tests for Orbit Survey timed sessions."""

from __future__ import annotations

from datetime import datetime, timedelta

import pytest
from sqlmodel import Session, select

from app.core.exceptions import ValidationError
from app.core.game_config import get_game_config
from app.core.security import create_access_token
from app.models.tool import Tool
from app.models.tool_session import (
    ACTION_KEY_GEO_COMPASS,
    ACTION_KEY_ORBIT_SURVEY,
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


def _user(session: Session, *, username: str = "fmap") -> User:
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
    action: str = "Read",
) -> ToolType:
    tool = ToolType(
        name=name,
        category="1 field_survey",
        scientific_tool="satellite imagery",
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


def test_tool_actions_yaml_loads_orbit_survey_knobs() -> None:
    get_game_config.cache_clear()
    cfg = get_game_config().tool_actions.orbit_survey
    assert cfg.duration_minutes == 10
    assert cfg.accuracy == 0.75
    assert cfg.range == 0.35
    assert cfg.min_range_m == 200.0
    assert cfg.max_range_m == 2000.0
    assert abs(cfg.resolved_range_m() - (200 + 0.35 * 1800)) < 1e-6
    assert cfg.base_alpha == 0.48
    assert cfg.range_fade == 0.85
    assert cfg.boundary_blur == 1.0
    colors = get_game_config().period_colors
    assert colors.orbit_survey.jurassic == (0x35, 0x68, 0x48)
    assert colors.orbit_survey.cretaceous == (0xA8, 0x6B, 0x45)
    assert colors.orbit_survey.triassic == (0xDD, 0x85, 0x00)
    assert colors.site_markers.cretaceous == (0x8D, 0x6E, 0x63)
    assert colors.site_markers.jurassic == (0x4F, 0x8F, 0x68)
    assert colors.site_markers.triassic == (0xDD, 0x85, 0x00)


def test_start_orbit_survey_session_snapshots_and_replaces(
    client, session: Session
) -> None:
    get_game_config.cache_clear()
    user = _user(session)
    fmap = _tool(session, name="Orbit Survey", action="Scan")
    instance = _grant(session, user_id=int(user.id), tool_id=int(fmap.id))
    headers = _auth_headers(user)

    first = client.post(
        f"/api/v1/tools/{fmap.id}/sessions",
        headers=headers,
    )
    assert first.status_code in (201, 202), first.text
    body = first.json()
    assert body["action_key"] == ACTION_KEY_ORBIT_SURVEY
    assert body["params"]["accuracy"] == 0.75
    assert body["params"]["range"] == 0.35
    assert body["params"]["min_range_m"] == 200.0
    assert body["params"]["max_range_m"] == 2000.0
    assert body["params"]["duration_minutes"] == 10
    assert body["status"] == SESSION_STATUS_ACTIVE
    assert body["tool_id"] == instance.id

    second = client.post(
        f"/api/v1/tools/{fmap.id}/sessions",
        headers=headers,
    )
    assert second.status_code == 400
    assert "Orbit Survey is already in use" in second.json()["detail"]

    rows = session.exec(select(ToolSession)).all()
    assert len(rows) == 1
    assert rows[0].status == SESSION_STATUS_ACTIVE


def test_cancel_and_restore_orbit_survey(client, session: Session) -> None:
    get_game_config.cache_clear()
    user = _user(session, username="fmap_cancel")
    fmap = _tool(session, name="Orbit Survey")
    _grant(session, user_id=int(user.id), tool_id=int(fmap.id))
    headers = _auth_headers(user)

    started = client.post(
        f"/api/v1/tools/{fmap.id}/sessions",
        headers=headers,
    )
    assert started.status_code in (201, 202)
    session_id = started.json()["session_id"]

    active = client.get(
        "/api/v1/tools/sessions/active",
        headers=headers,
        params={"action_key": ACTION_KEY_ORBIT_SURVEY},
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
        params={"action_key": ACTION_KEY_ORBIT_SURVEY},
    )
    assert missing.status_code == 200
    assert missing.json()["items"] == []


def test_expired_orbit_survey_session_ignored(session: Session) -> None:
    get_game_config.cache_clear()
    user = _user(session, username="fmap_expired")
    fmap = _tool(session, name="Orbit Survey")
    instance = _grant(session, user_id=int(user.id), tool_id=int(fmap.id))

    now = datetime.utcnow()
    session.add(
        ToolSession(
            user_id=int(user.id),
            tool_id=int(instance.id),
            action_key=ACTION_KEY_ORBIT_SURVEY,
            status=SESSION_STATUS_ACTIVE,
            started_at=now - timedelta(minutes=20),
            expires_at=now - timedelta(minutes=5),
            params_json={
                "duration_minutes": 10,
                "accuracy": 0.75,
                "range": 0.35,
                "min_range_m": 200.0,
                "max_range_m": 2000.0,
            },
            state_json={},
            created_at=now - timedelta(minutes=20),
            updated_at=now - timedelta(minutes=20),
        )
    )
    session.commit()

    assert (
        get_active_timed_session(
            session,
            user_id=int(user.id),
            action_keys=(ACTION_KEY_ORBIT_SURVEY,),
        )
        is None
    )
    row = session.exec(select(ToolSession)).one()
    assert row.status == SESSION_STATUS_COMPLETED


def test_rejects_when_guidance_already_in_use(session: Session) -> None:
    get_game_config.cache_clear()
    user = _user(session, username="fmap_mutex")
    fmap = _tool(session, name="Orbit Survey")
    compass = _tool(session, name="Geo Compass", action="Consult")
    _grant(session, user_id=int(user.id), tool_id=int(fmap.id))
    _grant(session, user_id=int(user.id), tool_id=int(compass.id))

    start_timed_session(
        session, user_id=int(user.id), tool_id=int(compass.id)
    )
    assert get_active_timed_session(session, user_id=int(user.id)) is not None

    with pytest.raises(ValidationError, match="Geo Compass is already in use"):
        start_timed_session(
            session, user_id=int(user.id), tool_id=int(fmap.id)
        )
    assert (
        get_active_timed_session(
            session,
            user_id=int(user.id),
            action_keys=(ACTION_KEY_GEO_COMPASS,),
        )
        is not None
    )
    assert (
        get_active_timed_session(
            session,
            user_id=int(user.id),
            action_keys=(ACTION_KEY_ORBIT_SURVEY,),
        )
        is None
    )
