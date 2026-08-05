"""Ambient weather status for the player's location."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlmodel import Session

from app.core.database import get_session
from app.core.security import get_current_user
from app.models.user import User
from app.schemas.weather import (
    WeatherCellInfo,
    WeatherForecastResponse,
    WeatherHourPoint,
    WeatherStatusResponse,
)
from app.services.weather_service import get_weather
from app.services.weather_service.persist import weather_series
from app.services.weather_service.service import cell_for

router = APIRouter(prefix="/weather", tags=["weather"])


@router.get("", response_model=WeatherStatusResponse)
async def get_weather_status(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    current_user: User = Depends(get_current_user),
):
    """Current weather type, temperature, and solar period for a location.

    Prefers the latest 15-minute row in ``weather`` for the ~5 km cell; falls
    back to live Open-Meteo when missing or stale. ``weather_time`` is computed
    locally from lat/lon/UTC.
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


@router.get("/forecast", response_model=WeatherForecastResponse)
async def get_weather_forecast(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    past_hours: int = Query(48, ge=0, le=168),
    forecast_hours: int = Query(72, ge=0, le=168),
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """15-minute past + forecast weather for the ~5 km cell containing lat/lon.

    Returns rows already stored by the weather_sync cron (or live write-through).
    Does not call Open-Meteo on the request path.
    """
    _ = current_user
    cell = cell_for(lat, lon)
    rows = weather_series(
        session,
        lat=lat,
        lon=lon,
        past_hours=past_hours,
        forecast_hours=forecast_hours,
    )
    return WeatherForecastResponse(
        cell=WeatherCellInfo(
            i=cell.i,
            j=cell.j,
            center_lat=cell.center_lat,
            center_lon=cell.center_lon,
        ),
        hours=[
            WeatherHourPoint(
                valid_at=row.valid_at,
                weather_type=row.weather_type,
                temperature_c=row.temperature_c,
                wmo_code=row.wmo_code,
                is_forecast=row.is_forecast,
                fetched_at=row.fetched_at,
            )
            for row in rows
        ],
    )
