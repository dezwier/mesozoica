"""Post-accept / on-discover coordinate enrichment for procedural field sites."""

from __future__ import annotations

from dataclasses import dataclass

from sqlmodel import Session

from app.models.site import (
    HOW_DISCOVERED_VALUES,
    Site,
)
from app.services.site_service.reverse_geocode import lookup_country_state


@dataclass(frozen=True)
class CoordinateEnrichment:
    """Metadata attached after a coordinate passes filtering."""

    country_code: str | None
    state: str | None


def enrich_coordinate(lat: float, lon: float) -> CoordinateEnrichment:
    """Enrich an accepted coordinate (runs once per site, not per rejection attempt)."""
    country_code, state = lookup_country_state(lat, lon)
    return CoordinateEnrichment(country_code=country_code, state=state)


def apply_site_discovery_enrichment(
    session: Session,
    site: Site,
    *,
    how_discovered: str,
) -> Site:
    """Fill country/state if missing; set how_discovered only on first discovery.

    Intended to run when a site is first discovered (walk / aerial / manual),
    not during ensure/generation.
    """
    if how_discovered not in HOW_DISCOVERED_VALUES:
        raise ValueError(f"Invalid how_discovered: {how_discovered}")

    changed = False
    needs_geo = site.country_code is None or site.state is None
    if needs_geo and site.latitude is not None and site.longitude is not None:
        enrichment = enrich_coordinate(float(site.latitude), float(site.longitude))
        if site.country_code is None and enrichment.country_code is not None:
            site.country_code = enrichment.country_code
            changed = True
        if site.state is None and enrichment.state is not None:
            site.state = enrichment.state
            changed = True

    if site.how_discovered is None:
        site.how_discovered = how_discovered
        changed = True

    if changed:
        session.add(site)
    return site
