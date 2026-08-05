"""Tests for Nocturne Lens night-gated main-param buffs."""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal

import pytest
from sqlmodel import Session, select

from app.core.game_config import get_game_config
from app.core.security import create_access_token
from app.models.data_source import DATA_SOURCE_FIELD
from app.models.site import Site
from app.models.site_type import SiteType
from app.models.tool import Tool
from app.models.tool_session import (
    ACTION_KEY_NOCTURNE_LENS,
    SESSION_STATUS_ACTIVE,
    SESSION_STATUS_CANCELLED,
    ToolSession,
)
from app.models.tool_type import ToolType
from app.models.user import User
from app.models.user_tool import USER_TOOL_ACTION_OWNED, UserTool
from app.services.site_common.discovery_params import resolve_site_discovery_params
from app.services.tool_action_service.tool_session import start_timed_session
from app.services.weather_service.service import WeatherSnapshot, cell_for
from app.services.weather_service.solar import period_at


def _stub_overcast_weather(monkeypatch: pytest.MonkeyPatch) -> None:
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


def _user(session: Session, *, username: str = "nocturne") -> User:
    user = User(
        username=username,
        email=f"{username}@example.com",
        password="x",
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    return user


def _tool(session: Session, *, name: str = "Nocturne Lens") -> ToolType:
    tool = ToolType(
        name=name,
        category="1 field_survey",
        scientific_tool="night-vision goggles",
        description="test",
        rarity=2,
        action="Pierce",
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


def test_tool_actions_yaml_loads_nocturne_lens_knobs() -> None:
    get_game_config.cache_clear()
    cfg = get_game_config().tool_actions.nocturne_lens
    assert cfg.duration_minutes > 0
    assert cfg.active_weather_times == ("night",)
    assert cfg.site_discovery_mod("discovery_distance_m") is not None
    assert cfg.site_discovery_mod("discovery_chance") is not None
    assert cfg.site_discovery_mod("discovery_max_speed_kmh") is None
    assert cfg.is_active_for_weather_time("night")
    assert not cfg.is_active_for_weather_time("dusk")
    assert not cfg.is_active_for_weather_time("day")


def test_start_nocturne_rejects_off_night(
    client, session: Session, monkeypatch: pytest.MonkeyPatch
) -> None:
    get_game_config.cache_clear()
    monkeypatch.setattr(
        "app.services.tool_action_service.tool_session.timed.period_at",
        lambda **_: "dusk",
    )
    user = _user(session)
    tool = _tool(session)
    _grant(session, user_id=int(user.id), tool_id=int(tool.id))
    headers = _auth_headers(user)

    resp = client.post(
        f"/api/v1/tools/{tool.id}/sessions",
        headers=headers,
        json={"lat": 50.0, "lon": 4.0},
    )
    assert resp.status_code == 400
    assert "night" in resp.json()["detail"].lower()


def test_start_nocturne_at_night_snapshots_gate(
    client, session: Session, monkeypatch: pytest.MonkeyPatch
) -> None:
    get_game_config.cache_clear()
    monkeypatch.setattr(
        "app.services.tool_action_service.tool_session.timed.period_at",
        lambda **_: "night",
    )
    user = _user(session)
    tool = _tool(session)
    _grant(session, user_id=int(user.id), tool_id=int(tool.id))
    headers = _auth_headers(user)

    resp = client.post(
        f"/api/v1/tools/{tool.id}/sessions",
        headers=headers,
        json={"lat": 50.0, "lon": 4.0},
    )
    assert resp.status_code in (201, 202), resp.text
    body = resp.json()
    assert body["action_key"] == ACTION_KEY_NOCTURNE_LENS
    assert body["status"] == SESSION_STATUS_ACTIVE
    assert body["params"]["active_weather_times"] == ["night"]
    mods = body["params"]["modifies_main_params"]["using"]["field_survey"]
    cfg = get_game_config().tool_actions.nocturne_lens
    for key in ("discovery_distance_m", "discovery_chance"):
        expected = cfg.site_discovery_mod(key)
        assert expected is not None
        assert mods[key] == {"op": expected.op, "value": expected.value}


def test_nocturne_boosts_at_night_and_autostops_at_dusk(
    session: Session, monkeypatch: pytest.MonkeyPatch
) -> None:
    get_game_config.cache_clear()
    _stub_overcast_weather(monkeypatch)
    user = _user(session, username="nightboost")
    tool = _tool(session)
    _grant(session, user_id=int(user.id), tool_id=int(tool.id))
    site = _site(session, site_id=91001, lat=50.0, lon=4.0)

    monkeypatch.setattr(
        "app.services.tool_action_service.tool_session.timed.period_at",
        lambda **_: "night",
    )
    monkeypatch.setattr(
        "app.services.site_common.discovery_params.period_at",
        lambda **_: "night",
    )
    row = start_timed_session(
        session,
        user_id=int(user.id),
        tool_id=int(tool.id),
        lat=50.0,
        lon=4.0,
    )
    assert row.status == SESSION_STATUS_ACTIVE
    assert row.params_json.get("active_weather_times") == ["night"]

    night_params = resolve_site_discovery_params(
        session,
        user_id=int(user.id),
        site=site,
        lat=50.0,
        lon=4.0,
    )
    from app.services.level_service.main_params import (
        apply_ambient_modifiers,
        apply_modifier,
        resolve_site_discovery_main_params,
    )

    disc = get_game_config().site_discovery
    nocturne = get_game_config().tool_actions.nocturne_lens
    night_dist_mods = list(
        (disc.weather_time_modifiers.get("discovery_distance_m") or {}).get(
            "night", []
        )
    )
    night_chance_mods = list(
        (disc.weather_time_modifiers.get("discovery_chance") or {}).get("night", [])
    )
    dist_tool = nocturne.site_discovery_mod("discovery_distance_m")
    chance_tool = nocturne.site_discovery_mod("discovery_chance")
    assert dist_tool is not None and chance_tool is not None
    expected_dist = apply_ambient_modifiers(
        float(disc.discovery_distance_m), night_dist_mods
    )
    expected_dist = apply_modifier(expected_dist, dist_tool)
    expected_chance = apply_ambient_modifiers(
        float(disc.discovery_chance), night_chance_mods
    )
    expected_chance = apply_modifier(expected_chance, chance_tool)
    expected_chance = min(1.0, max(0.0, expected_chance))
    assert night_params.discovery_distance_m == pytest.approx(expected_dist)
    assert night_params.base_discovery_chance == pytest.approx(expected_chance)

    monkeypatch.setattr(
        "app.services.site_common.discovery_params.period_at",
        lambda **_: "dusk",
    )
    dusk_params = resolve_site_discovery_params(
        session,
        user_id=int(user.id),
        site=site,
        lat=50.0,
        lon=4.0,
    )
    session.refresh(row)
    assert row.status == SESSION_STATUS_CANCELLED
    # Tool auto-stopped; dusk ambient from config only.
    dusk_resolved = resolve_site_discovery_main_params(
        skill_level=1, weather_time="dusk"
    )
    assert dusk_params.discovery_distance_m == pytest.approx(
        dusk_resolved["discovery_distance_m"]
    )
    assert dusk_params.base_discovery_chance == pytest.approx(
        dusk_resolved["discovery_chance"]
    )

    rows = session.exec(select(ToolSession)).all()
    assert len(rows) == 1
    assert rows[0].status == SESSION_STATUS_CANCELLED
