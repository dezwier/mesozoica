"""HTTP adapters owned by curated media."""

from app.features.media.api_dinosaur_images import router as dinosaur_router
from app.features.media.api_fossil_images import router as fossil_router
from app.features.media.api_site_type_images import router as site_type_router
from app.features.media.api_tool_images import router as tool_router

routers = (dinosaur_router, fossil_router, site_type_router, tool_router)

__all__ = ["routers"]
