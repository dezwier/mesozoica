"""Tests for Formation Map timed sessions."""

from __future__ import annotations

from datetime import datetime, timedelta

from sqlmodel import Session, select

from app.core.game_config import get_game_config
from app.core.security import create_access_token
from app.models.formation_map_session import (
    ACTION_KEY_FORMATION_MAP,
    SESSION_STATUS_ACTIVE,
    SESSION_STATUS_CANCELLED,
    SESSION_STATUS_EXPIRED,
    FormationMapSession,
)
from app.models.guidance_session import (
    ACTION_KEY_GEO_COMPASS,
    SESSION_STATUS_ACTIVE as GUIDANCE_ACTIVE,
    SESSION_STATUS_CANCELLED as GUIDANCE_CANCELLED,
    GuidanceSession,
)
from app.models.tool import Tool
from app.models.tool_type import ToolType
from app.models.user import User
from app.models.user_tool import USER_TOOL_ACTION_OWNED, UserTool
from app.services.tool_action_service.formation_map_session import (
    get_active_formation_map_session,
    start_formation_map_session,
)
from app.services.tool_action_service.guidance_session import (
    get_active_guidance_session,
    start_guidance_session,
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
    cfg = get_game_config().tool_actions.formation_map
    assert cfg.duration_minutes == 10
    assert cfg.accuracy == 0.75
    assert cfg.range == 0.35
    assert cfg.min_range_m == 200.0
    assert cfg.max_range_m == 2000.0
    assert abs(cfg.resolved_range_m() - (200 + 0.35 * 1800)) < 1e-6
    assert cfg.base_alpha == 0.55
    assert cfg.range_fade == 0.85
    assert cfg.boundary_blur == 0.8
    assert cfg.colors.jurassic == (0xA8, 0xC9, 0xA0)
    assert cfg.colors.cretaceous == (0x8D, 0x6E, 0x63)
    assert cfg.colors.triassic == (0xDD, 0x85, 0x00)


def test_start_formation_map_session_snapshots_and_replaces(
    client, session: Session
) -> None:
    get_game_config.cache_clear()
    user = _user(session)
    fmap = _tool(session, name="Formation Map", action="Read")
    _grant(session, user_id=int(user.id), tool_id=int(fmap.id))
    headers = _auth_headers(user)

    first = client.post(
        f"/api/v1/tools/{fmap.id}/actions/formation-map-session",
        headers=headers,
    )
    assert first.status_code == 201, first.text
    body = first.json()
    assert body["action_key"] == ACTION_KEY_FORMATION_MAP
    assert body["accuracy"] == 0.75
    assert body["range"] == 0.35
    assert body["min_range_m"] == 200.0
    assert body["max_range_m"] == 2000.0
    assert body["duration_minutes"] == 10
    assert body["status"] == SESSION_STATUS_ACTIVE
    assert body["tool_id"] == fmap.id

    second = client.post(
        f"/api/v1/tools/{fmap.id}/actions/formation-map-session",
        headers=headers,
    )
    assert second.status_code == 201, second.text

    rows = session.exec(select(FormationMapSession)).all()
    assert len(rows) == 2
    cancelled = [r for r in rows if r.status == SESSION_STATUS_CANCELLED]
    active = [r for r in rows if r.status == SESSION_STATUS_ACTIVE]
    assert len(cancelled) == 1
    assert len(active) == 1


def test_cancel_and_restore_formation_map(client, session: Session) -> None:
    get_game_config.cache_clear()
    user = _user(session, username="fmap_cancel")
    fmap = _tool(session, name="Formation Map")
    _grant(session, user_id=int(user.id), tool_id=int(fmap.id))
    headers = _auth_headers(user)

    started = client.post(
        f"/api/v1/tools/{fmap.id}/actions/formation-map-session",
        headers=headers,
    )
    assert started.status_code == 201

    active = client.get(
        "/api/v1/tools/sessions/formation-map/active",
        headers=headers,
    )
    assert active.status_code == 200
    assert active.json()["status"] == SESSION_STATUS_ACTIVE

    cancelled = client.post(
        "/api/v1/tools/sessions/formation-map/cancel",
        headers=headers,
    )
    assert cancelled.status_code == 200
    assert cancelled.json()["status"] == SESSION_STATUS_CANCELLED

    missing = client.get(
        "/api/v1/tools/sessions/formation-map/active",
        headers=headers,
    )
    assert missing.status_code == 404


def test_expired_formation_map_session_ignored(session: Session) -> None:
    get_game_config.cache_clear()
    user = _user(session, username="fmap_expired")
    fmap = _tool(session, name="Formation Map")
    instance = _grant(session, user_id=int(user.id), tool_id=int(fmap.id))

    now = datetime.utcnow()
    session.add(
        FormationMapSession(
            user_id=int(user.id),
            tool_id=int(instance.id),
            action_key=ACTION_KEY_FORMATION_MAP,
            status=SESSION_STATUS_ACTIVE,
            duration_minutes=10,
            accuracy=0.75,
            range=0.35,
            min_range_m=200.0,
            max_range_m=2000.0,
            started_at=now - timedelta(minutes=20),
            expires_at=now - timedelta(minutes=5),
            created_at=now - timedelta(minutes=20),
            updated_at=now - timedelta(minutes=20),
        )
    )
    session.commit()

    assert get_active_formation_map_session(session, user_id=int(user.id)) is None
    row = session.exec(select(FormationMapSession)).one()
    assert row.status == SESSION_STATUS_EXPIRED


def test_mutual_cancel_with_guidance(session: Session) -> None:
    get_game_config.cache_clear()
    user = _user(session, username="fmap_mutex")
    fmap = _tool(session, name="Formation Map")
    compass = _tool(session, name="Geo Compass", action="Consult")
    _grant(session, user_id=int(user.id), tool_id=int(fmap.id))
    _grant(session, user_id=int(user.id), tool_id=int(compass.id))

    start_guidance_session(
        session, user_id=int(user.id), tool_id=int(compass.id)
    )
    assert get_active_guidance_session(session, user_id=int(user.id)) is not None

    start_formation_map_session(
        session, user_id=int(user.id), tool_id=int(fmap.id)
    )
    assert get_active_formation_map_session(session, user_id=int(user.id)) is not None
    assert get_active_guidance_session(session, user_id=int(user.id)) is None

    guidance_rows = session.exec(select(GuidanceSession)).all()
    assert any(r.status == GUIDANCE_CANCELLED for r in guidance_rows)
    assert all(
        r.status != GUIDANCE_ACTIVE or r.action_key != ACTION_KEY_GEO_COMPASS
        for r in guidance_rows
        if r.status == GUIDANCE_ACTIVE
    )
    assert not any(r.status == GUIDANCE_ACTIVE for r in guidance_rows)

    start_guidance_session(
        session, user_id=int(user.id), tool_id=int(compass.id)
    )
    assert get_active_guidance_session(session, user_id=int(user.id)) is not None
    assert get_active_formation_map_session(session, user_id=int(user.id)) is None
