"""Site catalog / read service exports.

Field generation, ensure queue, and purge live in ``app.services.field_service``.
"""

from app.services.site_service.list import get_site_by_id, list_sites
from app.services.site_service.nearby import (
    list_discoverable_sites_in_radius,
    list_sites_in_radius,
)
from app.services.site_service.related import (
    list_site_dino_fossil_groups,
    list_site_dinosaurs,
    list_site_fossils,
)
from app.services.site_service.site_type_fallback import load_site_types_by_period
from app.services.site_service.summary import (
    enrich_site_rows_for_viewer,
    site_row_to_summary,
)
from app.services.site_service.survey import survey_site, user_has_surveyed

__all__ = [
    "discover_site",
    "enrich_site_rows_for_viewer",
    "get_site_by_id",
    "list_site_dino_fossil_groups",
    "list_site_dinosaurs",
    "list_site_fossils",
    "list_sites",
    "list_discoverable_sites_in_radius",
    "list_sites_in_radius",
    "load_site_types_by_period",
    "set_site_status",
    "site_row_to_summary",
    "survey_site",
    "user_has_surveyed",
]


def __getattr__(name: str):
    # Lazy: discover/set_status pull field_service onboard helpers.
    if name == "discover_site":
        from app.services.site_service.discover import discover_site

        return discover_site
    if name == "set_site_status":
        from app.services.site_service.set_status import set_site_status

        return set_site_status
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
