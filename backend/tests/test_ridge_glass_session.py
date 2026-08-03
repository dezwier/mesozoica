"""Tests for Ridge Glass timed sessions and global discovery buffs."""

from __future__ import annotations

from datetime import datetime, timedelta
from decimal import Decimal

import pytest
from sqlmodel import Session, select

from app.core.exceptions import ValidationError
from app.core.game_config import get_game_config
from app.core.security import create_access_token
from app.models.data_source import DATA_SOURCE_FIELD
from app.models.site import Site
from app.models.site_type import SiteType
from app.models.tool import Tool
from app.models.tool_session import (
    ACTION_KEY_ORBIT_SURVEY,
    ACTION_KEY_RIDGE_GLASS,
    SESSION_STATUS_ACTIVE,
    SESSION_STATUS_CANCELLED,
    SESSION_STATUS_COMPLETED,
    ToolSession,
)
from app.models.tool_type import ToolType
from app.models.user import User
from app.models.user_tool import USER_TOOL_ACTION_OWNED, UserTool
from app.services.site_common.discovery_params import resolve_site_discovery_params
from app.services.level_service.main_params import resolve_site_discovery_main_params
from app.services.tool_action_service.tool_session import (
    get_active_timed_session,
    start_timed_session,
)
from app.services.weather_service.service import WeatherSnapshot, cell_for
from app.services.weather_service.solar import period_at
from app.core.game_config import ParamModifier


def _stub_overcast_weather(monkeypatch: pytest.MonkeyPatch) -> None:
    """Avoid live Open-Meteo; overcast is identity for discovery multipliers."""

    def _fake(*, lat: float, lon: float) -> WeatherSnapshot:
        return WeatherSnapshot(
            weather_type="overcast",
            temperature_c=15.0,
            weather_time=period_at(latitude=lat, longitude=lon),
            observed_at=datetime.now(),
            cell=cell_for(lat, lon),
            wmo_code=3,
        )

    monkeypatch.setattr("app.services.weather_service.get_weather", _fake)


def _auth_headers(user: User) -> dict[str, str]:
    token = create_access_token({"sub": str(user.id)})
    return {"Authorization": f"Bearer {token}"}


def _user(session: Session, *, username: str = "ridge") -> User:
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
    action: str = "Scout",
) -> ToolType:
    tool = ToolType(
        name=name,
        category="4 fossil_detection",
        scientific_tool="binoculars",
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


def test_tool_actions_yaml_loads_ridge_glass_knobs() -> None:
    get_game_config.cache_clear()
    cfg = get_game_config().tool_actions.ridge_glass
    assert cfg.duration_minutes == 60
    vis = cfg.site_discovery_mod("visibility_distance_m")
    chance = cfg.site_discovery_mod("discovery_chance")
    assert vis == ParamModifier(op="multiply", value=1.3)
    assert chance == ParamModifier(op="multiply", value=1.3)
    assert cfg.added_visibility_range_m is None  # multiply, not add
    assert cfg.added_discovery_rate is None
    mods = cfg.modifies_main_params
    assert mods is not None
    assert mods.affects_skill("site_discovery")
    assert "visibility_distance_m" in mods.params_for("using", "site_discovery")
    assert "discovery_chance" in mods.params_for("using", "site_discovery")


def test_start_ridge_glass_session_snapshots_and_replaces(
    client, session: Session
) -> None:
    user = _user(session)
    ridge = _tool(session, name="Ridge Glass")
    _grant(session, user_id=int(user.id), tool_id=int(ridge.id))
    headers = _auth_headers(user)

    first = client.post(
        f"/api/v1/tools/{ridge.id}/sessions",
        headers=headers,
    )
    assert first.status_code in (201, 202), first.text
    body = first.json()
    assert body["action_key"] == ACTION_KEY_RIDGE_GLASS
    assert body["status"] == SESSION_STATUS_ACTIVE
    assert body["params"]["duration_minutes"] == 60
    mods = body["params"]["modifies_main_params"]["using"]["site_discovery"]
    assert mods["visibility_distance_m"] == {"op": "multiply", "value": 1.3}
    assert mods["discovery_chance"] == {"op": "multiply", "value": 1.3}

    second = client.post(
        f"/api/v1/tools/{ridge.id}/sessions",
        headers=headers,
    )
    assert second.status_code == 400
    assert "Ridge Glass is already in use" in second.json()["detail"]
    rows = session.exec(select(ToolSession)).all()
    assert len(rows) == 1
    assert rows[0].status == SESSION_STATUS_ACTIVE


def test_cancel_and_restore_ridge_glass(client, session: Session) -> None:
    user = _user(session)
    ridge = _tool(session, name="Ridge Glass")
    _grant(session, user_id=int(user.id), tool_id=int(ridge.id))
    headers = _auth_headers(user)

    started = client.post(
        f"/api/v1/tools/{ridge.id}/sessions",
        headers=headers,
    )
    assert started.status_code in (201, 202)
    session_id = started.json()["session_id"]

    active = client.get(
        "/api/v1/tools/sessions/active",
        headers=headers,
        params={"action_key": ACTION_KEY_RIDGE_GLASS},
    )
    assert active.status_code == 200
    assert len(active.json()["items"]) == 1

    cancelled = client.post(
        f"/api/v1/tools/sessions/{session_id}/cancel",
        headers=headers,
    )
    assert cancelled.status_code == 200
    assert cancelled.json()["status"] == SESSION_STATUS_CANCELLED

    missing = client.get(
        "/api/v1/tools/sessions/active",
        headers=headers,
        params={"action_key": ACTION_KEY_RIDGE_GLASS},
    )
    assert missing.status_code == 200
    assert missing.json()["items"] == []


def test_ridge_glass_boosts_all_sites_globally(
    session: Session, monkeypatch: pytest.MonkeyPatch
) -> None:
    get_game_config.cache_clear()
    _stub_overcast_weather(monkeypatch)
    user = _user(session, username="boost")
    ridge = _tool(session, name="Ridge Glass")
    _grant(session, user_id=int(user.id), tool_id=int(ridge.id))

    near = _site(session, site_id=93001, lat=40.0, lon=-100.0)
    far = _site(session, site_id=93002, lat=40.01, lon=-100.0)

    start_timed_session(session, user_id=int(user.id), tool_id=int(ridge.id))
    weather_time = period_at(latitude=40.0, longitude=-100.0)
    ridge_cfg = get_game_config().tool_actions.ridge_glass
    assert ridge_cfg.modifies_main_params is not None
    tool_mods = ridge_cfg.modifies_main_params.params_for(
        "using", "site_discovery"
    )
    expected = resolve_site_discovery_main_params(
        skill_level=1,
        weather_time=weather_time,
        weather_type="overcast",
        tool_mods=tool_mods,
    )
    expected_visibility = expected["visibility_distance_m"]
    expected_chance = expected["discovery_chance"]

    near_params = resolve_site_discovery_params(
        session,
        user_id=int(user.id),
        site=near,
        lat=40.0,
        lon=-100.0,
    )
    far_params = resolve_site_discovery_params(
        session,
        user_id=int(user.id),
        site=far,
        lat=40.0,
        lon=-100.0,
    )
    assert near_params.visibility_distance_m == expected_visibility
    assert near_params.discovery_chance == expected_chance
    assert far_params.visibility_distance_m == expected_visibility
    assert far_params.discovery_chance == expected_chance


def test_expired_ridge_glass_session_ignored(
    session: Session, monkeypatch: pytest.MonkeyPatch
) -> None:
    get_game_config.cache_clear()
    _stub_overcast_weather(monkeypatch)
    user = _user(session, username="expired")
    ridge = _tool(session, name="Ridge Glass")
    instance = _grant(session, user_id=int(user.id), tool_id=int(ridge.id))
    site = _site(session, site_id=93021, lat=42.0, lon=-102.0)

    now = datetime.utcnow()
    session.add(
        ToolSession(
            user_id=int(user.id),
            tool_id=int(instance.id),
            action_key=ACTION_KEY_RIDGE_GLASS,
            status=SESSION_STATUS_ACTIVE,
            started_at=now - timedelta(hours=2),
            expires_at=now - timedelta(minutes=5),
            params_json={
                "duration_minutes": 60,
                "modifies_main_params": {
                    "using": {
                        "site_discovery": {
                            "visibility_distance_m": {
                                "op": "add",
                                "value": 20.0,
                            },
                            "discovery_chance": {"op": "add", "value": 0.1},
                        }
                    }
                },
            },
            state_json={},
            created_at=now - timedelta(hours=2),
            updated_at=now - timedelta(hours=2),
        )
    )
    session.commit()

    baseline = resolve_site_discovery_main_params(
        skill_level=1,
        weather_time=period_at(latitude=42.0, longitude=-102.0),
        weather_type="overcast",
    )
    params = resolve_site_discovery_params(
        session,
        user_id=int(user.id),
        site=site,
        lat=42.0,
        lon=-102.0,
    )
    assert params.visibility_distance_m == baseline["visibility_distance_m"]
    assert params.discovery_chance == baseline["discovery_chance"]
    assert (
        get_active_timed_session(
            session,
            user_id=int(user.id),
            action_keys=(ACTION_KEY_RIDGE_GLASS,),
        )
        is None
    )
    row = session.exec(select(ToolSession)).one()
    assert row.status == SESSION_STATUS_COMPLETED


def test_rejects_when_orbit_survey_already_in_use(session: Session) -> None:
    user = _user(session)
    ridge = _tool(session, name="Ridge Glass")
    orbit = _tool(session, name="Orbit Survey", action="Scan")
    _grant(session, user_id=int(user.id), tool_id=int(ridge.id))
    _grant(session, user_id=int(user.id), tool_id=int(orbit.id))

    start_timed_session(session, user_id=int(user.id), tool_id=int(orbit.id))
    assert (
        get_active_timed_session(
            session,
            user_id=int(user.id),
            action_keys=(ACTION_KEY_ORBIT_SURVEY,),
        )
        is not None
    )

    with pytest.raises(ValidationError, match="Orbit Survey is already in use"):
        start_timed_session(session, user_id=int(user.id), tool_id=int(ridge.id))
