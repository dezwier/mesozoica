"""HTTP adapters owned by the sites feature."""

from app.features.sites.api_site_types import router as site_types_router
from app.features.sites.api_sites import router as sites_router

routers = (sites_router, site_types_router)

__all__ = ["routers"]
