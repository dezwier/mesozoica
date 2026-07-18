"""Post-accept coordinate enrichment for procedural field sites."""

from __future__ import annotations

from dataclasses import dataclass

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
