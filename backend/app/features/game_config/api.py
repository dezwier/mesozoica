"""HTTP adapters owned by the game-config feature."""

from app.features.game_config.api_admin import router as admin_router
from app.features.game_config.api_public import router as public_router

routers = (public_router, admin_router)

__all__ = ["routers"]
