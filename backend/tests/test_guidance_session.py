"""Tests for guidance sessions and nearest-site discovery boost."""

from __future__ import annotations

from datetime import datetime, timedelta
from decimal import Decimal

from sqlmodel import Session, select

from app.core.game_config import get_game_config
from app.core.security import create_access_token
from app.models.data_source import DATA_SOURCE_FIELD
from app.models.guidance_session import (
    ACTION_KEY_GEO_COMPASS,
    ACTION_KEY_PROXIMITY_SCANNER,
    SESSION_STATUS_ACTIVE,
    SESSION_STATUS_CANCELLED,
    GuidanceSession,
)
from app.models.site import Site
from app.models.site_type import SiteType
from app.models.tool import Tool
from app.models.user import User
from app.models.user_tool import UserTool
from app.services.site_service.discovery_params import resolve_site_discovery_params
from app.services.tool_action_service.guidance_session import (
    start_guidance_session,
)


def _auth_headers(user: User) -> dict[str, str]:
    token = create_access_token({"sub": str(user.id)})
    return {"Authorization": f"Bearer {token}"}


def _user(session: Session, *, username: str = "guide") -> User:
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
    action: str = "Consult",
) -> Tool:
    tool = Tool(
        name=name,
        category="1 site_discovery",
        scientific_tool="guidance",
        description="test",
        rarity=1,
        action=action,
    )
    session.add(tool)
    session.commit()
    session.refresh(tool)
    return tool


def _grant(session: Session, *, user_id: int, tool_id: int) -> None:
    session.add(UserTool(user_id=user_id, tool_id=tool_id, level=1))
    session.commit()


def _site(
    session: Session,
    *,
    site_id: int,
    lat: float,
    lon: float,
) -> Site:
    site_type = session.exec(select(SiteType)).first()
    if site_type is None:
        site_type = SiteType(period="cretaceous", rock_type="sandstone")
        session.add(site_type)
        session.commit()
        session.refresh(site_type)
    site = Site(
        site_id=site_id,
        latitude=Decimal(str(lat)),
        longitude=Decimal(str(lon)),
        rock_type="sandstone",
        period="cretaceous",
        site_type_id=site_type.id,
        data_source=DATA_SOURCE_FIELD,
    )
    session.add(site)
    session.commit()
    session.refresh(site)
    return site


def test_tool_actions_yaml_loads_guidance_knobs() -> None:
    get_game_config.cache_clear()
    cfg = get_game_config().tool_actions
    assert cfg.geo_compass.exactness == 0.0
    assert cfg.geo_compass.discovery_chance == 0.9
    assert cfg.geo_compass.duration_minutes == 15
    assert cfg.proximity_scanner.discovery_chance is None
    assert cfg.proximity_scanner.exactness == 0.0
    assert cfg.site_navigator.direction_exactness == 0.0
    assert cfg.site_navigator.distance_exactness == 0.0
    assert cfg.site_navigator.discovery_chance == 0.9


def test_start_guidance_session_snapshots_and_replaces(
    client, session: Session
) -> None:
    get_game_config.cache_clear()
    user = _user(session)
    compass = _tool(session, name="Geo Compass", action="Consult")
    scanner = _tool(session, name="Proximity Scanner", action="Track")
    _grant(session, user_id=int(user.id), tool_id=int(compass.id))
    _grant(session, user_id=int(user.id), tool_id=int(scanner.id))
    headers = _auth_headers(user)

    first = client.post(
        f"/api/v1/tools/{compass.id}/actions/guidance-session",
        headers=headers,
    )
    assert first.status_code == 201, first.text
    body = first.json()
    assert body["action_key"] == ACTION_KEY_GEO_COMPASS
    assert body["discovery_chance"] == 0.9
    assert body["direction_exactness"] == 0.0
    assert body["status"] == SESSION_STATUS_ACTIVE

    second = client.post(
        f"/api/v1/tools/{scanner.id}/actions/guidance-session",
        headers=headers,
    )
    assert second.status_code == 201, second.text
    body2 = second.json()
    assert body2["action_key"] == ACTION_KEY_PROXIMITY_SCANNER
    assert body2["discovery_chance"] is None
    assert body2["distance_exactness"] == 0.0

    rows = session.exec(select(GuidanceSession)).all()
    assert len(rows) == 2
    cancelled = [r for r in rows if r.status == SESSION_STATUS_CANCELLED]
    active = [r for r in rows if r.status == SESSION_STATUS_ACTIVE]
    assert len(cancelled) == 1
    assert len(active) == 1
    assert active[0].action_key == ACTION_KEY_PROXIMITY_SCANNER


def test_resolve_discovery_boost_only_for_nearest(
    session: Session,
) -> None:
    get_game_config.cache_clear()
    user = _user(session, username="boost")
    compass = _tool(session, name="Geo Compass")
    _grant(session, user_id=int(user.id), tool_id=int(compass.id))

    near = _site(session, site_id=92001, lat=40.0, lon=-100.0)
    far = _site(session, site_id=92002, lat=40.01, lon=-100.0)

    start_guidance_session(
        session, user_id=int(user.id), tool_id=int(compass.id)
    )
    baseline = get_game_config().site_discovery.discovery_chance

    near_params = resolve_site_discovery_params(
        session,
        user_id=int(user.id),
        site=near,
        lat=40.0,
        lon=-100.0,
    )
    assert near_params.discovery_chance == 0.9

    far_params = resolve_site_discovery_params(
        session,
        user_id=int(user.id),
        site=far,
        lat=40.0,
        lon=-100.0,
    )
    assert far_params.discovery_chance == baseline


def test_proximity_session_does_not_boost(session: Session) -> None:
    get_game_config.cache_clear()
    user = _user(session, username="prox")
    scanner = _tool(session, name="Proximity Scanner", action="Track")
    _grant(session, user_id=int(user.id), tool_id=int(scanner.id))
    site = _site(session, site_id=92011, lat=41.0, lon=-101.0)

    start_guidance_session(
        session, user_id=int(user.id), tool_id=int(scanner.id)
    )
    baseline = get_game_config().site_discovery.discovery_chance
    params = resolve_site_discovery_params(
        session,
        user_id=int(user.id),
        site=site,
        lat=41.0,
        lon=-101.0,
    )
    assert params.discovery_chance == baseline


def test_expired_session_ignored(session: Session) -> None:
    get_game_config.cache_clear()
    user = _user(session, username="expired")
    compass = _tool(session, name="Geo Compass")
    _grant(session, user_id=int(user.id), tool_id=int(compass.id))
    site = _site(session, site_id=92021, lat=42.0, lon=-102.0)

    now = datetime.utcnow()
    session.add(
        GuidanceSession(
            user_id=int(user.id),
            tool_id=int(compass.id),
            action_key=ACTION_KEY_GEO_COMPASS,
            status=SESSION_STATUS_ACTIVE,
            discovery_chance=0.9,
            direction_exactness=0.0,
            duration_minutes=15,
            started_at=now - timedelta(minutes=20),
            expires_at=now - timedelta(minutes=5),
            created_at=now - timedelta(minutes=20),
            updated_at=now - timedelta(minutes=20),
        )
    )
    session.commit()

    baseline = get_game_config().site_discovery.discovery_chance
    params = resolve_site_discovery_params(
        session,
        user_id=int(user.id),
        site=site,
        lat=42.0,
        lon=-102.0,
    )
    assert params.discovery_chance == baseline
