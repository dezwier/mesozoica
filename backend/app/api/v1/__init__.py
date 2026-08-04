"""API v1 router aggregation."""

from fastapi import APIRouter

from app.api.v1.endpoints import (
    admin_game_config,
    auth_linking,
    auth_login,
    auth_profile,
    dinosaur_images,
    dinosaurs,
    fossil_images,
    fossils,
    game_config,
    notifications,
    root,
    site_type_images,
    site_types,
    sites,
    tool_images,
    tools,
    user_relationships,
    users,
    weather,
)

api_router = APIRouter()
api_router.include_router(root.router)
api_router.include_router(dinosaurs.router)
api_router.include_router(fossils.router)
api_router.include_router(sites.router)
api_router.include_router(site_types.router)
api_router.include_router(dinosaur_images.router)
api_router.include_router(fossil_images.router)
api_router.include_router(site_type_images.router)
api_router.include_router(tools.router)
api_router.include_router(tool_images.router)
api_router.include_router(auth_login.router)
api_router.include_router(auth_profile.router)
api_router.include_router(auth_linking.router)
api_router.include_router(users.router)
api_router.include_router(user_relationships.router)
api_router.include_router(notifications.router)
api_router.include_router(weather.router)
api_router.include_router(game_config.router)
api_router.include_router(admin_game_config.router)
