"""Resolve effective site-discovery params (baseline + guidance boosts)."""

from __future__ import annotations

from dataclasses import dataclass

from sqlmodel import Session

from app.core.game_config import get_game_config
from app.models.site import Site
from app.models.tool_session import GUIDANCE_ACTION_KEYS
from app.services.site_common.geo_utils import haversine_km
from app.services.site_service.nearby import list_discoverable_sites_in_radius


@dataclass(frozen=True)
class ResolvedSiteDiscoveryParams:
    max_distance_m: float
    discovery_chance: float  # clamped 0..1


def nearest_discoverable_site_id(
    session: Session,
    *,
    user_id: int,
    lat: float,
    lon: float,
) -> int | None:
    """Id of the nearest still-discoverable field site, or None."""
    radius_km = float(get_game_config().site_discovery.client.cache_radius_km)
    rows = list_discoverable_sites_in_radius(
        session,
        lat=lat,
        lon=lon,
        radius_km=radius_km,
        user_id=user_id,
    )
    best_id: int | None = None
    best_km = float("inf")
    for row in rows:
        site = row.site
        if site.latitude is None or site.longitude is None:
            continue
        dist = haversine_km(
            lat, lon, float(site.latitude), float(site.longitude)
        )
        if dist < best_km:
            best_km = dist
            best_id = int(site.site_id)
    return best_id


def resolve_site_discovery_params(
    session: Session,
    *,
    user_id: int,
    site: Site,
    lat: float | None = None,
    lon: float | None = None,
) -> ResolvedSiteDiscoveryParams:
    """Baseline from game_config; active guidance boosts nearest-site chance.

    When the user has an active guidance session with a snapshotted
    ``discovery_chance``, that chance replaces the baseline **only** if
    [site] is the nearest still-discoverable site to (lat, lon).
    """
    # Lazy import: tool_session → site nearby → discover → this module.
    from app.services.tool_action_service.tool_session import (
        get_active_timed_session,
    )

    cfg = get_game_config().site_discovery
    chance = min(1.0, max(0.0, float(cfg.discovery_chance)))
    max_distance_m = float(cfg.max_distance_m)

    if lat is not None and lon is not None:
        guidance = get_active_timed_session(
            session, user_id=user_id, action_keys=GUIDANCE_ACTION_KEYS
        )
        params = (guidance.params_json if guidance is not None else None) or {}
        boost = params.get("discovery_chance")
        if guidance is not None and boost is not None:
            nearest_id = nearest_discoverable_site_id(
                session,
                user_id=user_id,
                lat=lat,
                lon=lon,
            )
            if nearest_id is not None and int(site.site_id) == nearest_id:
                chance = min(1.0, max(0.0, float(boost)))

    return ResolvedSiteDiscoveryParams(
        max_distance_m=max_distance_m,
        discovery_chance=chance,
    )
