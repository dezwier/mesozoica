"""Tests for Formation Map timed rock-type square sessions."""

from __future__ import annotations

import pytest
from sqlmodel import Session, select

from app.core.exceptions import ValidationError
from app.core.game_config import get_game_config
from app.core.security import create_access_token
from app.models.field_ensure_job import FieldEnsureJob
from app.models.tool import Tool
from app.models.tool_session import (
    ACTION_KEY_FORMATION_MAP,
    ACTION_KEY_ORBIT_SURVEY,
    SESSION_STATUS_ACTIVE,
    SESSION_STATUS_CANCELLED,
    ToolSession,
)
from app.models.tool_type import ToolType
from app.models.user import User
from app.models.user_tool import USER_TOOL_ACTION_OWNED, UserTool
from app.services.site_common.survey_grid import snap_to_cell_center
from app.services.tool_action_service.tool_session import (
    get_active_timed_session,
    start_formation_session,
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
        category="1 site_discovery",
        scientific_tool="geological map",
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


def test_tool_actions_yaml_loads_formation_map_knobs() -> None:
    get_game_config.cache_clear()
    game = get_game_config()
    cfg = game.tool_actions.formation_map
    assert cfg.duration_minutes == 10
    assert cfg.accuracy == 0.75
    assert cfg.cell_size_m == game.site_generation.lazy.cell_size_m == 500.0
    assert cfg.wideness_m == 500.0
    assert cfg.resolved_wideness_m() == 500.0
    assert cfg.range_fade == 0.0
    colors = game.rock_type_colors
    assert colors.for_rock_type("sandstone") == (0xD4, 0xA0, 0x17)
    assert colors.for_rock_type("unknown_xyz") == (0x88, 0x88, 0x88)


def test_start_formation_map_snaps_center_once(client, session: Session) -> None:
    get_game_config.cache_clear()
    user = _user(session)
    fmap = _tool(session, name="Formation Map", action="Read")
    instance = _grant(session, user_id=int(user.id), tool_id=int(fmap.id))
    headers = _auth_headers(user)

    lat, lon = 50.8503, 4.3517
    cell_m = get_game_config().site_generation.lazy.cell_size_m
    expected = snap_to_cell_center(lat, lon, cell_size_m=cell_m)

    first = client.post(
        f"/api/v1/tools/{fmap.id}/sessions",
        headers=headers,
        json={"lat": lat, "lon": lon},
    )
    assert first.status_code in (201, 202), first.text
    body = first.json()
    assert body["action_key"] == ACTION_KEY_FORMATION_MAP
    assert body["params"]["wideness_m"] == 500.0
    assert body["params"]["cell_size_m"] == cell_m
    assert abs(body["params"]["center_lat"] - expected[0]) < 1e-6
    assert abs(body["params"]["center_lon"] - expected[1]) < 1e-6

    session.refresh(instance)
    assert instance.params_json is not None
    assert abs(float(instance.params_json["center_lat"]) - expected[0]) < 1e-6
    assert abs(float(instance.params_json["center_lon"]) - expected[1]) < 1e-6

    # Far away GPS must not move the locked center after stop + restart.
    cancelled = client.post(
        f"/api/v1/tools/sessions/{body['session_id']}/cancel",
        headers=headers,
    )
    assert cancelled.status_code == 200

    second = client.post(
        f"/api/v1/tools/{fmap.id}/sessions",
        headers=headers,
        json={"lat": 0.0, "lon": 0.0},
    )
    assert second.status_code in (201, 202), second.text
    body2 = second.json()
    assert abs(body2["params"]["center_lat"] - expected[0]) < 1e-6
    assert abs(body2["params"]["center_lon"] - expected[1]) < 1e-6

    rows = session.exec(select(ToolSession)).all()
    assert len(rows) == 2
    assert sum(1 for r in rows if r.status == SESSION_STATUS_CANCELLED) == 1
    assert sum(1 for r in rows if r.status == SESSION_STATUS_ACTIVE) == 1

    jobs = list(session.exec(select(FieldEnsureJob)).all())
    assert len(jobs) == 1
    assert jobs[0].reason == ACTION_KEY_FORMATION_MAP


def test_rejects_when_orbit_survey_already_in_use(session: Session) -> None:
    get_game_config.cache_clear()
    user = _user(session, username="fmap_mutex")
    fmap = _tool(session, name="Formation Map")
    orbit = _tool(session, name="Orbit Survey", action="Scan")
    _grant(session, user_id=int(user.id), tool_id=int(fmap.id))
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
        start_formation_session(
            session,
            user_id=int(user.id),
            tool_id=int(fmap.id),
            lat=50.85,
            lon=4.35,
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
            action_keys=(ACTION_KEY_FORMATION_MAP,),
        )
        is None
    )
