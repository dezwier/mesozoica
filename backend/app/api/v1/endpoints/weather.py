"""Ambient weather status for the player's location."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.security import get_current_user
from app.models.user import User
from app.schemas.weather import WeatherCellInfo, WeatherStatusResponse
from app.services.weather_service import get_weather

router = APIRouter(prefix="/weather", tags=["weather"])


@router.get("", response_model=WeatherStatusResponse)
async def get_weather_status(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    current_user: User = Depends(get_current_user),
):
    """Current weather type, temperature, and solar period for a location.

    Weather type/temp are cached per ~5 km cell (Open-Meteo). ``weather_time``
    is computed locally from lat/lon/UTC (no sunrise API).
    """
    _ = current_user
    try:
        snap = get_weather(lat=lat, lon=lon)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Weather upstream failed: {exc}",
        ) from exc
    return WeatherStatusResponse(
        weather_type=snap.weather_type,
        temperature_c=snap.temperature_c,
        weather_time=snap.weather_time,
        observed_at=snap.observed_at,
        cell=WeatherCellInfo(
            i=snap.cell.i,
            j=snap.cell.j,
            center_lat=snap.cell.center_lat,
            center_lon=snap.cell.center_lon,
        ),
        wmo_code=snap.wmo_code,
    )
