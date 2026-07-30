"""Resolve effective site-discovery params (baseline + guidance boosts)."""

from __future__ import annotations

from dataclasses import dataclass

from sqlmodel import Session

from app.core.game_config import get_game_config
from app.models.site import Site


@dataclass(frozen=True)
class ResolvedSiteDiscoveryParams:
    max_distance_m: float
    discovery_chance: float  # clamped 0..1


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
    # Lazy import: guidance_session → site nearby → discover → this module.
    from app.services.tool_action_service.guidance_session import (
        get_active_guidance_session,
        nearest_discoverable_site_id,
    )

    cfg = get_game_config().site_discovery
    chance = min(1.0, max(0.0, float(cfg.discovery_chance)))
    max_distance_m = float(cfg.max_distance_m)

    if lat is not None and lon is not None:
        guidance = get_active_guidance_session(session, user_id=user_id)
        if (
            guidance is not None
            and guidance.discovery_chance is not None
        ):
            nearest_id = nearest_discoverable_site_id(
                session,
                user_id=user_id,
                lat=lat,
                lon=lon,
            )
            if nearest_id is not None and int(site.site_id) == nearest_id:
                chance = min(
                    1.0, max(0.0, float(guidance.discovery_chance))
                )

    return ResolvedSiteDiscoveryParams(
        max_distance_m=max_distance_m,
        discovery_chance=chance,
    )
