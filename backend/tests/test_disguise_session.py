"""Tests for Brush Scrim / Blackout Cover disguise covers."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from decimal import Decimal

import pytest
from sqlmodel import Session, col, select

from app.core.game_config import get_game_config
from app.core.security import create_access_token
from app.models.data_source import DATA_SOURCE_FIELD
from app.models.site import Site
from app.models.site_type import SiteType
from app.models.tool import Tool
from app.models.tool_session import (
    ACTION_KEY_BLACKOUT_COVER,
    ACTION_KEY_BRUSH_SCRIM,
    SESSION_STATUS_ACTIVE,
    SESSION_STATUS_CANCELLED,
    SESSION_STATUS_COMPLETED,
    ToolSession,
)
from app.models.tool_type import ToolType
from app.models.user import User
from app.models.user_site import (
    USER_SITE_ROLE_DISCOVERER,
    USER_SITE_ROLE_DISGUISER,
    USER_SITE_ROLE_DOCUMENTER,
    UserSite,
    role_to_status,
)
from app.models.user_tool import USER_TOOL_ACTION_OWNED, UserTool
from app.services.level_service.main_params import resolve_site_stewardship_main_params
from app.services.level_service.skills import get_skill_xp, set_skill_xp
from app.services.level_service.xp_table import SKILL_THRESHOLDS
from app.services.site_common.discovery_params import resolve_site_discovery_params
from app.services.site_service.discover import discover_site
from app.services.site_service.status_join import latest_user_sites_for_ids
from app.services.tool_action_service.disguise_session import (
    rival_discovery_multiplier,
)
from app.services.tool_action_service.tool_session import (
    cancel_timed_session,
    start_timed_session,
)
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


def _user(session: Session, *, username: str = "disguise_of_site") -> User:
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
    action: str = "Conceal",
) -> ToolType:
    tool = ToolType(
        name=name,
        category="1 field_survey",
        scientific_tool="camouflage netting",
        description="test",
        rarity=2,
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
    lat: float = 50.0,
    lon: float = 4.0,
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


def _link_discoverer(session: Session, *, user_id: int, site_id: int) -> UserSite:
    link = UserSite(
        user_id=user_id,
        site_id=site_id,
        role=USER_SITE_ROLE_DISCOVERER,
    )
    session.add(link)
    session.commit()
    session.refresh(link)
    return link


def test_tool_actions_yaml_loads_disguise_knobs() -> None:
    get_game_config.cache_clear()
    scrim = get_game_config().tool_actions.brush_scrim
    cover = get_game_config().tool_actions.blackout_cover
    assert scrim.duration_minutes == 60
    assert scrim.rival_discovery_mod is not None
    assert scrim.rival_discovery_mod.op == "multiply"
    assert scrim.rival_discovery_mod.value == 0.0
    assert cover.rival_discovery_mod is not None
    assert cover.rival_discovery_mod.op == "multiply"
    assert cover.rival_discovery_mod.value == 0.5
    assert get_game_config().site_stewardship.rival_discovery_chance == 1.0
    assert get_game_config().site_stewardship.disguise_of_site_xp == 40.0


def test_deploy_requires_discoverer(client, session: Session) -> None:
    owner = _user(session, username="owner")
    site = _site(session, site_id=91001)
    scrim = _tool(session, name="Brush Scrim")
    _grant(session, user_id=int(owner.id), tool_id=int(scrim.id))
    headers = _auth_headers(owner)

    resp = client.post(
        f"/api/v1/tools/{scrim.id}/sessions",
        headers=headers,
        json={"site_id": site.site_id},
    )
    assert resp.status_code == 400
    assert "discover" in resp.json()["detail"].lower()


def test_deploy_creates_disguiser_and_ignores_status(
    client, session: Session, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_overcast_weather(monkeypatch)
    owner = _user(session, username="owner2")
    site = _site(session, site_id=91002)
    _link_discoverer(session, user_id=int(owner.id), site_id=int(site.site_id))
    scrim = _tool(session, name="Brush Scrim")
    _grant(session, user_id=int(owner.id), tool_id=int(scrim.id))
    headers = _auth_headers(owner)

    resp = client.post(
        f"/api/v1/tools/{scrim.id}/sessions",
        headers=headers,
        json={"site_id": site.site_id},
    )
    assert resp.status_code in (201, 202), resp.text
    body = resp.json()
    assert body["action_key"] == ACTION_KEY_BRUSH_SCRIM
    assert body["status"] == SESSION_STATUS_ACTIVE
    assert body["state"]["site_id"] == site.site_id
    assert body["params"]["modifies_main_params"]["using"]["field_survey"][
        "rival_discovery_chance"
    ] == {"op": "multiply", "value": 0.0}

    disguiser = session.exec(
        select(UserSite).where(
            col(UserSite.user_id) == int(owner.id),
            col(UserSite.site_id) == int(site.site_id),
            col(UserSite.role) == USER_SITE_ROLE_DISGUISER,
        )
    ).first()
    assert disguiser is not None
    assert disguiser.source_session_id == body["session_id"]

    latest = latest_user_sites_for_ids(session, [int(site.site_id)])
    assert int(site.site_id) in latest
    assert latest[int(site.site_id)].role == USER_SITE_ROLE_DISCOVERER
    assert role_to_status(latest[int(site.site_id)].role) == "discovered"


def test_one_disguise_per_user_replaces_prior(
    client, session: Session
) -> None:
    owner = _user(session, username="owner3")
    site_a = _site(session, site_id=91003, lat=50.0, lon=4.0)
    site_b = _site(session, site_id=91004, lat=50.1, lon=4.1)
    _link_discoverer(session, user_id=int(owner.id), site_id=int(site_a.site_id))
    _link_discoverer(session, user_id=int(owner.id), site_id=int(site_b.site_id))
    scrim = _tool(session, name="Brush Scrim")
    cover = _tool(session, name="Blackout Cover", action="Shroud")
    _grant(session, user_id=int(owner.id), tool_id=int(scrim.id))
    _grant(session, user_id=int(owner.id), tool_id=int(cover.id))
    headers = _auth_headers(owner)

    first = client.post(
        f"/api/v1/tools/{scrim.id}/sessions",
        headers=headers,
        json={"site_id": site_a.site_id},
    )
    assert first.status_code in (201, 202), first.text
    first_id = first.json()["session_id"]

    second = client.post(
        f"/api/v1/tools/{cover.id}/sessions",
        headers=headers,
        json={"site_id": site_b.site_id},
    )
    assert second.status_code in (201, 202), second.text
    assert second.json()["action_key"] == ACTION_KEY_BLACKOUT_COVER

    session.expire_all()
    old = session.get(ToolSession, first_id)
    assert old is not None
    assert old.status == SESSION_STATUS_CANCELLED

    old_link = session.exec(
        select(UserSite).where(
            col(UserSite.user_id) == int(owner.id),
            col(UserSite.site_id) == int(site_a.site_id),
            col(UserSite.role) == USER_SITE_ROLE_DISGUISER,
        )
    ).first()
    assert old_link is None

    new_link = session.exec(
        select(UserSite).where(
            col(UserSite.user_id) == int(owner.id),
            col(UserSite.site_id) == int(site_b.site_id),
            col(UserSite.role) == USER_SITE_ROLE_DISGUISER,
        )
    ).first()
    assert new_link is not None


def test_rival_chance_halved_discoverer_unaffected(
    session: Session, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_overcast_weather(monkeypatch)
    owner = _user(session, username="owner4")
    rival = _user(session, username="rival4")
    site = _site(session, site_id=91005)
    _link_discoverer(session, user_id=int(owner.id), site_id=int(site.site_id))
    cover = _tool(session, name="Blackout Cover", action="Shroud")
    _grant(session, user_id=int(owner.id), tool_id=int(cover.id))

    start_timed_session(
        session,
        user_id=int(owner.id),
        tool_id=int(cover.id),
        site_id=int(site.site_id),
    )

    owner_params = resolve_site_discovery_params(
        session,
        user_id=int(owner.id),
        site=site,
        lat=50.0,
        lon=4.0,
    )
    rival_params = resolve_site_discovery_params(
        session,
        user_id=int(rival.id),
        site=site,
        lat=50.0,
        lon=4.0,
    )
    assert rival_params.discovery_chance == pytest.approx(
        owner_params.discovery_chance * 0.5, rel=1e-6
    )


def test_brush_scrim_zeros_rival_chance(
    session: Session, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_overcast_weather(monkeypatch)
    owner = _user(session, username="owner5")
    rival = _user(session, username="rival5")
    site = _site(session, site_id=91006)
    _link_discoverer(session, user_id=int(owner.id), site_id=int(site.site_id))
    scrim = _tool(session, name="Brush Scrim")
    _grant(session, user_id=int(owner.id), tool_id=int(scrim.id))

    start_timed_session(
        session,
        user_id=int(owner.id),
        tool_id=int(scrim.id),
        site_id=int(site.site_id),
    )

    rival_params = resolve_site_discovery_params(
        session,
        user_id=int(rival.id),
        site=site,
        lat=50.0,
        lon=4.0,
    )
    assert rival_params.discovery_chance == 0.0


def test_rival_blocked_roll_awards_stewardship_xp(
    session: Session, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Brush Scrim (×0) still rolls; a would-be hit is blocked and awards XP."""
    _stub_overcast_weather(monkeypatch)
    from app.core.exceptions import DiscoveryChanceMissError
    from app.services.field_service.field_coordinate_enrich import (
        CoordinateEnrichment,
    )

    monkeypatch.setattr(
        "app.services.site_service.discover.send_site_discovered_push",
        lambda *args, **kwargs: None,
    )
    monkeypatch.setattr(
        "app.services.site_service.discover.ensure_fossils_on_site_discovery",
        lambda session, site_id, user_id: None,
    )
    monkeypatch.setattr(
        "app.services.field_service.field_coordinate_enrich.enrich_coordinate",
        lambda lat, lon: CoordinateEnrichment(country_code="BE", state="Flanders"),
    )

    owner = _user(session, username="owner6")
    rival = _user(session, username="rival6")
    site = _site(session, site_id=91007)
    _link_discoverer(session, user_id=int(owner.id), site_id=int(site.site_id))
    scrim = _tool(session, name="Brush Scrim")
    _grant(session, user_id=int(owner.id), tool_id=int(scrim.id))

    start_timed_session(
        session,
        user_id=int(owner.id),
        tool_id=int(scrim.id),
        site_id=int(site.site_id),
    )
    session.refresh(owner)
    before = get_skill_xp(owner, "field_survey")

    class WouldHaveHit:
        def random(self) -> float:
            return 0.0

    with pytest.raises(DiscoveryChanceMissError):
        discover_site(
            session,
            site_id=int(site.site_id),
            user_id=int(rival.id),
            lat=50.0,
            lon=4.0,
            rng=WouldHaveHit(),  # type: ignore[arg-type]
        )

    session.refresh(owner)
    after = get_skill_xp(owner, "field_survey")
    assert after == before + 40


def test_blackout_cover_blocked_band_awards_stewardship_xp(
    session: Session, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Blackout Cover: rolls in (effective, base] are blocked and award XP."""
    _stub_overcast_weather(monkeypatch)
    from app.core.exceptions import DiscoveryChanceMissError
    from app.services.field_service.field_coordinate_enrich import (
        CoordinateEnrichment,
    )

    monkeypatch.setattr(
        "app.services.site_service.discover.send_site_discovered_push",
        lambda *args, **kwargs: None,
    )
    monkeypatch.setattr(
        "app.services.site_service.discover.ensure_fossils_on_site_discovery",
        lambda session, site_id, user_id: None,
    )
    monkeypatch.setattr(
        "app.services.field_service.field_coordinate_enrich.enrich_coordinate",
        lambda lat, lon: CoordinateEnrichment(country_code="BE", state="Flanders"),
    )

    owner = _user(session, username="owner6b")
    rival = _user(session, username="rival6b")
    site = _site(session, site_id=91008)
    _link_discoverer(session, user_id=int(owner.id), site_id=int(site.site_id))
    cover = _tool(session, name="Blackout Cover", action="Shroud")
    _grant(session, user_id=int(owner.id), tool_id=int(cover.id))

    start_timed_session(
        session,
        user_id=int(owner.id),
        tool_id=int(cover.id),
        site_id=int(site.site_id),
    )

    rival_params = resolve_site_discovery_params(
        session,
        user_id=int(rival.id),
        site=site,
        lat=50.0,
        lon=4.0,
    )
    # Midpoint of the blocked band [effective, base).
    blocked_u = (
        rival_params.discovery_chance + rival_params.base_discovery_chance
    ) / 2.0
    assert rival_params.discovery_chance < blocked_u < rival_params.base_discovery_chance

    session.refresh(owner)
    before = get_skill_xp(owner, "field_survey")

    class BlockedBand:
        def random(self) -> float:
            return blocked_u

    with pytest.raises(DiscoveryChanceMissError):
        discover_site(
            session,
            site_id=int(site.site_id),
            user_id=int(rival.id),
            lat=50.0,
            lon=4.0,
            rng=BlockedBand(),  # type: ignore[arg-type]
        )

    session.refresh(owner)
    assert get_skill_xp(owner, "field_survey") == before + 40


def test_stop_clears_disguiser_and_restores_chance(
    client, session: Session, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_overcast_weather(monkeypatch)
    owner = _user(session, username="owner7")
    rival = _user(session, username="rival7")
    site = _site(session, site_id=91008)
    _link_discoverer(session, user_id=int(owner.id), site_id=int(site.site_id))
    scrim = _tool(session, name="Brush Scrim")
    _grant(session, user_id=int(owner.id), tool_id=int(scrim.id))
    headers = _auth_headers(owner)

    started = client.post(
        f"/api/v1/tools/{scrim.id}/sessions",
        headers=headers,
        json={"site_id": site.site_id},
    )
    assert started.status_code in (201, 202)
    session_id = started.json()["session_id"]

    assert (
        resolve_site_discovery_params(
            session, user_id=int(rival.id), site=site, lat=50.0, lon=4.0
        ).discovery_chance
        == 0.0
    )

    cancelled = cancel_timed_session(
        session, user_id=int(owner.id), session_id=session_id
    )
    assert cancelled is not None
    assert cancelled.status == SESSION_STATUS_CANCELLED

    link = session.exec(
        select(UserSite).where(
            col(UserSite.user_id) == int(owner.id),
            col(UserSite.site_id) == int(site.site_id),
            col(UserSite.role) == USER_SITE_ROLE_DISGUISER,
        )
    ).first()
    assert link is None

    restored = resolve_site_discovery_params(
        session, user_id=int(rival.id), site=site, lat=50.0, lon=4.0
    )
    assert restored.discovery_chance > 0.0


def test_expiry_clears_disguiser(session: Session) -> None:
    owner = _user(session, username="owner8")
    site = _site(session, site_id=91009)
    _link_discoverer(session, user_id=int(owner.id), site_id=int(site.site_id))
    scrim = _tool(session, name="Brush Scrim")
    _grant(session, user_id=int(owner.id), tool_id=int(scrim.id))

    row = start_timed_session(
        session,
        user_id=int(owner.id),
        tool_id=int(scrim.id),
        site_id=int(site.site_id),
    )
    row.expires_at = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(
        seconds=1
    )
    session.add(row)
    session.commit()

    from app.services.tool_action_service.tool_session import get_active_timed_session

    active = get_active_timed_session(
        session,
        user_id=int(owner.id),
        action_keys=(ACTION_KEY_BRUSH_SCRIM,),
    )
    assert active is None

    session.expire_all()
    expired = session.get(ToolSession, row.id)
    assert expired is not None
    assert expired.status == SESSION_STATUS_COMPLETED

    link = session.exec(
        select(UserSite).where(
            col(UserSite.user_id) == int(owner.id),
            col(UserSite.site_id) == int(site.site_id),
            col(UserSite.role) == USER_SITE_ROLE_DISGUISER,
        )
    ).first()
    assert link is None


def test_passive_rival_discovery_from_steward_skill(
    session: Session, monkeypatch: pytest.MonkeyPatch
) -> None:
    """High stewardship skill lowers rival chance with no disguise tool."""
    _stub_overcast_weather(monkeypatch)
    owner = _user(session, username="owner_passive")
    rival = _user(session, username="rival_passive")
    site = _site(session, site_id=91010)
    _link_discoverer(session, user_id=int(owner.id), site_id=int(site.site_id))
    set_skill_xp(owner, "field_survey", SKILL_THRESHOLDS[99])
    session.add(owner)
    session.commit()

    expected_mult = float(
        resolve_site_stewardship_main_params(skill_level=99)["rival_discovery_chance"]
    )
    assert expected_mult == pytest.approx(0.5, abs=1e-6)

    mult = rival_discovery_multiplier(
        session, site_id=int(site.site_id), rolling_user_id=int(rival.id)
    )
    assert mult == pytest.approx(expected_mult, rel=1e-6)

    base = resolve_site_discovery_params(
        session,
        user_id=int(owner.id),
        site=site,
        lat=50.0,
        lon=4.0,
    ).discovery_chance
    rival_params = resolve_site_discovery_params(
        session,
        user_id=int(rival.id),
        site=site,
        lat=50.0,
        lon=4.0,
    )
    assert rival_params.discovery_chance == pytest.approx(
        base * expected_mult, rel=1e-6
    )


def test_documenter_status_applies_rival_discovery(
    session: Session, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Any status above hidden (e.g. documenter) applies rival_discovery_chance."""
    _stub_overcast_weather(monkeypatch)
    owner = _user(session, username="owner_doc")
    rival = _user(session, username="rival_doc")
    site = _site(session, site_id=91011)
    session.add(
        UserSite(
            user_id=int(owner.id),
            site_id=int(site.site_id),
            role=USER_SITE_ROLE_DOCUMENTER,
        )
    )
    set_skill_xp(owner, "field_survey", SKILL_THRESHOLDS[99])
    session.add(owner)
    session.commit()

    mult = rival_discovery_multiplier(
        session, site_id=int(site.site_id), rolling_user_id=int(rival.id)
    )
    assert mult == pytest.approx(0.5, abs=1e-6)

    # Rolling user with status above hidden is unaffected.
    assert (
        rival_discovery_multiplier(
            session, site_id=int(site.site_id), rolling_user_id=int(owner.id)
        )
        == 1.0
    )
