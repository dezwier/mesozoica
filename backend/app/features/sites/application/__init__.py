"""Site catalog / read service exports.

Field generation, ensure queue, and purge live in ``app.features.field``.
"""

from app.features.sites.application.list import get_site_by_id, list_sites
from app.features.sites.application.nearby import (
    list_discoverable_sites_in_radius,
    list_sites_in_radius,
)
from app.features.sites.application.related import (
    list_site_dino_fossil_groups,
    list_site_dinosaurs,
    list_site_fossils,
)
from app.features.sites.application.site_type_fallback import load_site_types_by_period
from app.features.sites.application.summary import (
    enrich_site_rows_for_viewer,
    site_row_to_summary,
)

__all__ = [
    "discard_site_for_user",
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
]


def __getattr__(name: str):
    # Lazy: discover/set_status pull field_service onboard helpers.
    if name == "discover_site":
        from app.features.sites.application.discover import discover_site

        return discover_site
    if name == "set_site_status":
        from app.features.sites.application.set_status import set_site_status

        return set_site_status
    if name == "discard_site_for_user":
        from app.features.sites.application.discard import discard_site_for_user

        return discard_site_for_user
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
