"""Shared display labels for sites (match Flutter SiteSummary.displayTitle)."""

from __future__ import annotations

from app.models.site import Site
from app.services.site_common.constants import FIELD_SITE_ID_START


def site_display_title(site: Site | None) -> str:
    """Card-style title: formation when set, else short field site number (#n)."""
    if site is None:
        return ""
    formation = (site.formation or "").strip()
    if formation:
        return formation
    site_id = site.site_id
    n = site_id - FIELD_SITE_ID_START if site_id >= FIELD_SITE_ID_START else site_id
    return f"#{n}"
