"""Tests for Formation Map timed rock-type square sessions."""

from __future__ import annotations

from sqlmodel import Session, select

from app.core.game_config import get_game_config
from app.core.security import create_access_token
from app.models.formation_map_session import (
    ACTION_KEY_FORMATION_MAP,
    SESSION_STATUS_ACTIVE,
    SESSION_STATUS_CANCELLED,
    FormationMapSession,
)
from app.models.orbit_survey_session import OrbitSurveySession
from app.models.tool import Tool
from app.models.tool_type import ToolType
from app.models.user import User
from app.models.user_tool import USER_TOOL_ACTION_OWNED, UserTool
from app.services.tool_action_service.formation_map_session import (
    get_active_formation_map_session,
    start_formation_map_session,
)
from app.services.tool_action_service.orbit_survey_session import (
    get_active_orbit_survey_session,
    start_orbit_survey_session,
)
from app.services.tool_action_service.survey_grid import snap_to_cell_center


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
    cfg = get_game_config().tool_actions.formation_map
    assert cfg.duration_minutes == 10
    assert cfg.accuracy == 0.75
    assert cfg.wideness_m == 200.0
    assert cfg.resolved_wideness_m() == 200.0
    assert cfg.range_fade == 0.0
    colors = get_game_config().rock_type_colors
    assert colors.for_rock_type("sandstone") == (0xD4, 0xA0, 0x17)
    assert colors.for_rock_type("unknown_xyz") == (0x88, 0x88, 0x88)


def test_start_formation_map_snaps_center_once(client, session: Session) -> None:
    get_game_config.cache_clear()
    user = _user(session)
    fmap = _tool(session, name="Formation Map", action="Read")
    instance = _grant(session, user_id=int(user.id), tool_id=int(fmap.id))
    headers = _auth_headers(user)

    lat, lon = 50.8503, 4.3517
    expected = snap_to_cell_center(lat, lon, cell_size_m=200.0)

    first = client.post(
        f"/api/v1/tools/{fmap.id}/actions/formation-map-session",
        headers=headers,
        json={"lat": lat, "lon": lon},
    )
    assert first.status_code == 201, first.text
    body = first.json()
    assert body["action_key"] == ACTION_KEY_FORMATION_MAP
    assert body["wideness_m"] == 200.0
    assert abs(body["center_lat"] - expected[0]) < 1e-6
    assert abs(body["center_lon"] - expected[1]) < 1e-6

    session.refresh(instance)
    assert instance.params_json is not None
    assert abs(float(instance.params_json["center_lat"]) - expected[0]) < 1e-6
    assert abs(float(instance.params_json["center_lon"]) - expected[1]) < 1e-6

    # Far away GPS must not move the locked center.
    second = client.post(
        f"/api/v1/tools/{fmap.id}/actions/formation-map-session",
        headers=headers,
        json={"lat": 0.0, "lon": 0.0},
    )
    assert second.status_code == 201, second.text
    body2 = second.json()
    assert abs(body2["center_lat"] - expected[0]) < 1e-6
    assert abs(body2["center_lon"] - expected[1]) < 1e-6

    rows = session.exec(select(FormationMapSession)).all()
    assert len(rows) == 2
    assert sum(1 for r in rows if r.status == SESSION_STATUS_CANCELLED) == 1
    assert sum(1 for r in rows if r.status == SESSION_STATUS_ACTIVE) == 1


def test_mutual_cancel_with_orbit_survey(session: Session) -> None:
    get_game_config.cache_clear()
    user = _user(session, username="fmap_mutex")
    fmap = _tool(session, name="Formation Map")
    orbit = _tool(session, name="Orbit Survey", action="Scan")
    _grant(session, user_id=int(user.id), tool_id=int(fmap.id))
    _grant(session, user_id=int(user.id), tool_id=int(orbit.id))

    start_orbit_survey_session(
        session, user_id=int(user.id), tool_id=int(orbit.id)
    )
    assert get_active_orbit_survey_session(session, user_id=int(user.id)) is not None

    start_formation_map_session(
        session,
        user_id=int(user.id),
        tool_id=int(fmap.id),
        lat=50.85,
        lon=4.35,
    )
    assert get_active_formation_map_session(session, user_id=int(user.id)) is not None
    assert get_active_orbit_survey_session(session, user_id=int(user.id)) is None
    assert any(
        r.status == SESSION_STATUS_CANCELLED
        for r in session.exec(select(OrbitSurveySession)).all()
    )
