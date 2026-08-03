"""Tests for deferred country/state enrichment and how_discovered."""

from __future__ import annotations

from decimal import Decimal

from sqlmodel import Session

from app.models.data_source import DATA_SOURCE_FIELD
from app.models.site import (
    HOW_DISCOVERED_AERIAL_RECON,
    HOW_DISCOVERED_AERIAL_SCOUT,
    HOW_DISCOVERED_MANUAL,
    HOW_DISCOVERED_WALK,
    Site,
)
from app.models.user import User
from app.services.site_service.discover import discover_site
from app.services.field_service.field_coordinate_enrich import (
    CoordinateEnrichment,
    apply_site_discovery_enrichment,
)
from app.services.tool_action_service.discover_session import discover_site_from_aerial


def _field_site(session: Session, *, site_id: int = 2_000_000_001) -> Site:
    site = Site(
        site_id=site_id,
        latitude=Decimal("40.000000"),
        longitude=Decimal("-100.000000"),
        rock_type="sandstone",
        period="cretaceous",
        data_source=DATA_SOURCE_FIELD,
        country_code=None,
        state=None,
        how_discovered=None,
    )
    session.add(site)
    session.commit()
    session.refresh(site)
    return site


def _user(session: Session, *, username: str = "walker") -> User:
    user = User(
        username=username,
        email=f"{username}@example.com",
        password="x",
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    return user


def test_apply_site_discovery_enrichment_fills_geo_and_how(session: Session, monkeypatch):
    site = _field_site(session)
    monkeypatch.setattr(
        "app.services.field_service.field_coordinate_enrich.enrich_coordinate",
        lambda lat, lon: CoordinateEnrichment(country_code="US", state="Montana"),
    )

    apply_site_discovery_enrichment(
        session, site, how_discovered=HOW_DISCOVERED_WALK
    )
    session.commit()
    session.refresh(site)

    assert site.country_code == "US"
    assert site.state == "Montana"
    assert site.how_discovered == HOW_DISCOVERED_WALK


def test_apply_site_discovery_enrichment_is_idempotent(session: Session, monkeypatch):
    site = _field_site(session)
    site.country_code = "CA"
    site.state = "Alberta"
    site.how_discovered = HOW_DISCOVERED_WALK
    session.add(site)
    session.commit()

    calls = {"n": 0}

    def _enrich(lat, lon):
        calls["n"] += 1
        return CoordinateEnrichment(country_code="US", state="Montana")

    monkeypatch.setattr(
        "app.services.field_service.field_coordinate_enrich.enrich_coordinate",
        _enrich,
    )

    apply_site_discovery_enrichment(
        session, site, how_discovered=HOW_DISCOVERED_AERIAL_RECON
    )
    session.commit()
    session.refresh(site)

    assert calls["n"] == 0
    assert site.country_code == "CA"
    assert site.state == "Alberta"
    assert site.how_discovered == HOW_DISCOVERED_WALK


def test_discover_site_sets_walk_and_enriches(session: Session, monkeypatch):
    site = _field_site(session)
    user = _user(session)
    monkeypatch.setattr(
        "app.services.field_service.field_coordinate_enrich.enrich_coordinate",
        lambda lat, lon: CoordinateEnrichment(country_code="US", state="Kansas"),
    )
    monkeypatch.setattr(
        "app.services.site_service.discover.resolve_site_discovery_params",
        lambda session, *, user_id, site, lat=None, lon=None: type(
            "P",
            (),
            {
                "max_distance_m": 500.0,
                "discovery_chance": 1.0,
                "site_discovery_xp": 10.0,
            },
        )(),
    )
    monkeypatch.setattr(
        "app.services.site_service.discover.ensure_fossils_on_site_discovery",
        lambda session, site_id, user_id: None,
    )
    monkeypatch.setattr(
        "app.services.site_service.discover.send_site_discovered_push",
        lambda *args, **kwargs: None,
    )

    discover_site(
        session,
        site_id=int(site.site_id),
        user_id=int(user.id),
        lat=40.0,
        lon=-100.0,
    )
    session.refresh(site)
    assert site.how_discovered == HOW_DISCOVERED_WALK
    assert site.country_code == "US"
    assert site.state == "Kansas"


def test_aerial_discover_sets_aerial_recon(session: Session, monkeypatch):
    from datetime import datetime

    from app.models.tool import Tool
    from app.models.tool_type import ToolType
    from app.models.tool_session import (
        ACTION_KEY_AERIAL_RECON,
        SESSION_STATUS_ACTIVE,
        ToolSession,
    )
    from app.models.user_site import USER_SITE_ROLE_DISCOVERER, UserSite
    from sqlmodel import col, select

    site = _field_site(session, site_id=2_000_000_002)
    user = _user(session, username="pilot")
    tool_type = ToolType(
        name="Aerial Recon",
        category="1 site_discovery",
        scientific_tool="helicopter",
        description="Scout",
        rarity=5,
        action="Deploy",
    )
    session.add(tool_type)
    session.commit()
    session.refresh(tool_type)
    tool = Tool(tool_type_id=int(tool_type.id), level=1)
    session.add(tool)
    session.commit()
    session.refresh(tool)
    now = datetime.utcnow()
    tool_session = ToolSession(
        user_id=int(user.id),
        tool_id=int(tool.id),
        action_key=ACTION_KEY_AERIAL_RECON,
        status=SESSION_STATUS_ACTIVE,
        started_at=now,
        params_json={},
        state_json={
            "route": [{"lat": 40.0, "lon": -100.0}],
            "route_length_km": 1.0,
            "flight_duration_s": 60,
        },
        created_at=now,
        updated_at=now,
    )
    session.add(tool_session)
    session.commit()
    session.refresh(tool_session)

    monkeypatch.setattr(
        "app.services.field_service.field_coordinate_enrich.enrich_coordinate",
        lambda lat, lon: CoordinateEnrichment(country_code="US", state="Nebraska"),
    )
    monkeypatch.setattr(
        "app.services.tool_action_service.discover_session.ensure_fossils_on_site_discovery",
        lambda session, site_id, user_id: "ok",
    )
    monkeypatch.setattr(
        "app.services.tool_action_service.discover_session.send_site_discovered_push",
        lambda *args, **kwargs: None,
    )

    result = discover_site_from_aerial(
        session,
        site_id=int(site.site_id),
        user_id=int(user.id),
        lat=40.0,
        lon=-100.0,
        max_distance_m=500.0,
        discovery_chance=1.0,
        how_discovered=HOW_DISCOVERED_AERIAL_RECON,
        session_id=int(tool_session.id),
    )
    assert result == "ok"
    session.refresh(site)
    assert site.how_discovered == HOW_DISCOVERED_AERIAL_RECON
    assert site.country_code == "US"

    link = session.exec(
        select(UserSite).where(
            col(UserSite.user_id) == int(user.id),
            col(UserSite.site_id) == int(site.site_id),
            col(UserSite.role) == USER_SITE_ROLE_DISCOVERER,
        )
    ).one()
    assert link.source_session_id == int(tool_session.id)


def test_aerial_discover_sets_aerial_scout(session: Session, monkeypatch):
    from datetime import datetime

    from app.models.tool import Tool
    from app.models.tool_type import ToolType
    from app.models.tool_session import (
        ACTION_KEY_AERIAL_SCOUT,
        SESSION_STATUS_ACTIVE,
        ToolSession,
    )

    site = _field_site(session, site_id=2_000_000_012)
    user = _user(session, username="drone_pilot")
    tool_type = ToolType(
        name="Aerial Scout",
        category="1 site_discovery",
        scientific_tool="drone",
        description="Drone loop",
        rarity=2,
        action="Launch",
    )
    session.add(tool_type)
    session.commit()
    session.refresh(tool_type)
    tool = Tool(tool_type_id=int(tool_type.id), level=1)
    session.add(tool)
    session.commit()
    session.refresh(tool)
    now = datetime.utcnow()
    tool_session = ToolSession(
        user_id=int(user.id),
        tool_id=int(tool.id),
        action_key=ACTION_KEY_AERIAL_SCOUT,
        status=SESSION_STATUS_ACTIVE,
        started_at=now,
        params_json={},
        state_json={
            "route": [{"lat": 40.0, "lon": -100.0}],
            "route_length_km": 1.0,
            "flight_duration_s": 60,
        },
        created_at=now,
        updated_at=now,
    )
    session.add(tool_session)
    session.commit()
    session.refresh(tool_session)

    monkeypatch.setattr(
        "app.services.field_service.field_coordinate_enrich.enrich_coordinate",
        lambda lat, lon: CoordinateEnrichment(country_code="US", state="Nebraska"),
    )
    monkeypatch.setattr(
        "app.services.tool_action_service.discover_session.ensure_fossils_on_site_discovery",
        lambda session, site_id, user_id: "ok",
    )
    monkeypatch.setattr(
        "app.services.tool_action_service.discover_session.send_site_discovered_push",
        lambda *args, **kwargs: None,
    )

    result = discover_site_from_aerial(
        session,
        site_id=int(site.site_id),
        user_id=int(user.id),
        lat=40.0,
        lon=-100.0,
        max_distance_m=500.0,
        discovery_chance=1.0,
        how_discovered=HOW_DISCOVERED_AERIAL_SCOUT,
        session_id=int(tool_session.id),
    )
    assert result == "ok"
    session.refresh(site)
    assert site.how_discovered == HOW_DISCOVERED_AERIAL_SCOUT


def test_site_summary_includes_viewer_discovery(session: Session):
    from datetime import datetime, timezone

    from app.models.tool import Tool
    from app.models.tool_type import ToolType
    from app.models.tool_session import (
        ACTION_KEY_AERIAL_RECON,
        SESSION_STATUS_COMPLETED,
        ToolSession,
    )
    from app.models.user_site import USER_SITE_ROLE_DISCOVERER, UserSite
    from app.services.site_service.list import get_site_by_id
    from app.services.site_service.summary import site_row_to_summary

    site = _field_site(session, site_id=2_000_000_003)
    user = _user(session, username="viewer")
    tool_type = ToolType(
        name="Aerial Recon",
        category="1 site_discovery",
        scientific_tool="helicopter",
        description="Scout",
        rarity=5,
        action="Deploy",
    )
    session.add(tool_type)
    session.commit()
    session.refresh(tool_type)
    tool = Tool(tool_type_id=int(tool_type.id), level=1)
    session.add(tool)
    session.commit()
    session.refresh(tool)
    now = datetime.utcnow()
    tool_session = ToolSession(
        user_id=int(user.id),
        tool_id=int(tool.id),
        action_key=ACTION_KEY_AERIAL_RECON,
        status=SESSION_STATUS_COMPLETED,
        started_at=now,
        ended_at=now,
        used_duration_s=60,
        params_json={},
        state_json={
            "route": [{"lat": 40.0, "lon": -100.0}],
            "route_length_km": 1.0,
            "flight_duration_s": 60,
        },
        created_at=now,
        updated_at=now,
    )
    session.add(tool_session)
    session.commit()
    session.refresh(tool_session)

    discovered_at = datetime(2026, 7, 1, 12, 0, tzinfo=timezone.utc)
    session.add(
        UserSite(
            user_id=int(user.id),
            site_id=int(site.site_id),
            role=USER_SITE_ROLE_DISCOVERER,
            source_session_id=int(tool_session.id),
            timestamp=discovered_at,
        )
    )
    session.commit()

    row = get_site_by_id(
        session,
        int(site.site_id),
        data_source="field",
        viewer_user_id=int(user.id),
    )
    summary = site_row_to_summary(row)
    assert summary.discovered_at is not None
    assert summary.discovering_session_id == int(tool_session.id)


def test_manual_constant_available():
    assert HOW_DISCOVERED_MANUAL == "manual"
