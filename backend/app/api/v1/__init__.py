"""API v1 router aggregation."""

from fastapi import APIRouter

from app.api.v1.endpoints import (
    dinosaur_images,
    dinosaurs,
    fossil_images,
    fossils,
    root,
    site_type_images,
    sites,
)

api_router = APIRouter()
api_router.include_router(root.router)
api_router.include_router(dinosaurs.router)
api_router.include_router(fossils.router)
api_router.include_router(sites.router)
api_router.include_router(dinosaur_images.router)
api_router.include_router(fossil_images.router)
api_router.include_router(site_type_images.router)
