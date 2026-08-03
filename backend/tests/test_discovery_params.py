"""Tests for site discovery param resolver (boost seam)."""

from __future__ import annotations

from decimal import Decimal

from sqlmodel import Session

from app.core.game_config import get_game_config
from app.models.site import Site
from app.models.site_type import SiteType
from app.services.site_common.discovery_params import (
    ResolvedSiteDiscoveryParams,
    resolve_site_discovery_params,
)


def _seed_site(session: Session) -> Site:
    site_type = SiteType(period="cretaceous", rock_type="sandstone")
    session.add(site_type)
    session.commit()
    session.refresh(site_type)
    site = Site(
        site_id=91001,
        latitude=Decimal("40.0"),
        longitude=Decimal("-100.0"),
        rock_type="sandstone",
        period="cretaceous",
        site_type_id=site_type.id,
        data_source="field",
    )
    session.add(site)
    session.commit()
    session.refresh(site)
    return site


def test_resolve_site_discovery_params_baseline(session: Session) -> None:
    get_game_config.cache_clear()
    site = _seed_site(session)
    params = resolve_site_discovery_params(session, user_id=1, site=site)
    cfg = get_game_config().site_discovery
    assert params.visibility_distance_m == cfg.visibility_distance_m
    assert params.max_distance_m == cfg.visibility_distance_m
    assert params.discovery_chance == cfg.discovery_chance


def test_resolve_site_discovery_params_boost_hook(
    session: Session, monkeypatch
) -> None:
    """Lock the extension point: boosts multiply baseline chance."""
    get_game_config.cache_clear()
    site = _seed_site(session)
    base = get_game_config().site_discovery.discovery_chance

    def boosted(
        session: Session, *, user_id: int, site: Site
    ) -> ResolvedSiteDiscoveryParams:
        cfg = get_game_config().site_discovery
        # Example future boost: +period affinity
        chance = min(1.0, cfg.discovery_chance * 2.0)
        return ResolvedSiteDiscoveryParams(
            visibility_distance_m=cfg.visibility_distance_m,
            discovery_chance=chance,
            site_discovery_xp=cfg.site_discovery_xp,
        )

    monkeypatch.setattr(
        "app.services.site_common.discovery_params.resolve_site_discovery_params",
        boosted,
    )
    from app.services.site_service import discovery_params as mod

    params = mod.resolve_site_discovery_params(session, user_id=1, site=site)
    assert params.discovery_chance == min(1.0, base * 2.0)
