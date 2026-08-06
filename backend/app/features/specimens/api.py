"""HTTP adapters owned by the specimens feature."""

from app.features.specimens.api_dinosaurs import router as dinosaurs_router
from app.features.specimens.api_fossils import router as fossils_router

routers = (dinosaurs_router, fossils_router)

__all__ = ["routers"]
