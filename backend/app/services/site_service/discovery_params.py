"""Resolve effective site-discovery params (baseline + future boosts)."""

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
) -> ResolvedSiteDiscoveryParams:
    """Baseline from game_config; later: user / period / rock_type / tool boosts.

    ``session``, ``user_id``, and ``site`` are accepted now so callers and
    future boosts share one seam without API churn.
    """
    _ = (session, user_id, site)
    cfg = get_game_config().site_discovery
    chance = min(1.0, max(0.0, float(cfg.discovery_chance)))
    return ResolvedSiteDiscoveryParams(
        max_distance_m=float(cfg.max_distance_m),
        discovery_chance=chance,
    )
