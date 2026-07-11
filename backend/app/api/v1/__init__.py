"""API v1 router aggregation."""

from fastapi import APIRouter

from app.api.v1.endpoints import root

api_router = APIRouter()
api_router.include_router(root.router)
