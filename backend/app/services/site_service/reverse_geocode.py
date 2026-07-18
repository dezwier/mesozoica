"""Reverse geocoding helpers for procedural field sites."""

from __future__ import annotations

import logging

logger = logging.getLogger(__name__)


def lookup_country_state(lat: float, lon: float) -> tuple[str | None, str | None]:
    """Return ISO-2 country code and admin1 region name for a WGS84 point."""
    try:
        import reverse_geocoder as rg
    except ImportError:
        logger.warning("reverse_geocoder is not installed; skipping geocoding")
        return None, None

    try:
        result = rg.search((lat, lon))[0]
    except Exception:
        logger.debug("Reverse geocode failed for lat=%s lon=%s", lat, lon, exc_info=True)
        return None, None

    country_code = (result.get("cc") or "").strip().upper() or None
    state = (result.get("admin1") or "").strip() or None
    if country_code and len(country_code) > 2:
        country_code = country_code[:2]
    if state and len(state) > 100:
        state = state[:100]
    return country_code, state
