import os

from fastapi import APIRouter

router = APIRouter(tags=["meta"])

API_VERSION = os.getenv("API_VERSION", "0.1.0")


@router.get("/")
async def api_root():
    return {"name": "mesozoica-api", "version": API_VERSION}
