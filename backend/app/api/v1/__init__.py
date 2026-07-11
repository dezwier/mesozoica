"""API v1 router aggregation."""

from fastapi import APIRouter

from app.api.v1.endpoints import dinosaurs, root

api_router = APIRouter()
api_router.include_router(root.router)
api_router.include_router(dinosaurs.router)
