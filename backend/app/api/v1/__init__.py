"""API v1 router aggregation."""

from fastapi import APIRouter

from app.api.v1.endpoints import root
from app.features.accounts.api import routers as account_routers
from app.features.assistant.api import routers as assistant_routers
from app.features.game_config.api import routers as game_config_routers
from app.features.media.api import routers as media_routers
from app.features.sites.api import routers as site_routers
from app.features.specimens.api import routers as specimen_routers
from app.features.tools.api import routers as tool_routers
from app.features.weather.api import routers as weather_routers

api_router = APIRouter()
api_router.include_router(root.router)
for router in specimen_routers:
    api_router.include_router(router)
for router in site_routers:
    api_router.include_router(router)
for router in media_routers[:3]:
    api_router.include_router(router)
for router in tool_routers:
    api_router.include_router(router)
api_router.include_router(media_routers[3])
for router in account_routers:
    api_router.include_router(router)
for router in weather_routers:
    api_router.include_router(router)
for router in game_config_routers:
    api_router.include_router(router)
for router in assistant_routers:
    api_router.include_router(router)
