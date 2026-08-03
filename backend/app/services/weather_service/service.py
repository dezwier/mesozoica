"""Open-Meteo weather fetch with 5 km grid-cell TTL cache."""

from __future__ import annotations

import logging
import math
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Literal

import httpx

from app.services.weather_service.solar import period_at

logger = logging.getLogger(__name__)

WeatherType = Literal[
    "sunny",
    "cloudy",
    "overcast",
    "fog",
    "drizzle",
    "rain",
    "snow",
    "thunderstorm",
    "hail",
    "unknown",
]

# ~5 km in latitude degrees (1° lat ≈ 111.32 km).
_CELL_KM = 5.0
_LAT_DEG = _CELL_KM / 111.32
_CACHE_TTL_S = 20 * 60
_OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast"

_cache_lock = threading.Lock()
_cache: dict[tuple[int, int], tuple[float, "WeatherSnapshot"]] = {}


@dataclass(frozen=True)
class WeatherCell:
    i: int
    j: int
    center_lat: float
    center_lon: float


@dataclass(frozen=True)
class WeatherSnapshot:
    weather_type: WeatherType
    temperature_c: float
    weather_time: str
    observed_at: datetime
    cell: WeatherCell
    wmo_code: int


def cell_for(lat: float, lon: float) -> WeatherCell:
    """Quantize lat/lon into ~5 km cells."""
    i = math.floor(lat / _LAT_DEG)
    center_lat = (i + 0.5) * _LAT_DEG
    cos_lat = max(math.cos(math.radians(center_lat)), 0.05)
    lon_deg = _LAT_DEG / cos_lat
    j = math.floor(lon / lon_deg)
    center_lon = (j + 0.5) * lon_deg
    return WeatherCell(i=i, j=j, center_lat=center_lat, center_lon=center_lon)


def weather_type_from_wmo(code: int) -> WeatherType:
    """Map Open-Meteo WMO weather interpretation codes to game types."""
    if code == 0:
        return "sunny"
    if code in (1, 2):
        return "cloudy"
    if code == 3:
        return "overcast"
    if code in (45, 48):
        return "fog"
    if code in (51, 53, 55, 56, 57):
        return "drizzle"
    if code in (61, 63, 65, 66, 67, 80, 81, 82):
        return "rain"
    if code in (71, 73, 75, 77, 85, 86):
        return "snow"
    if code == 95:
        return "thunderstorm"
    if code in (96, 99):
        return "hail"
    return "unknown"


def _fetch_open_meteo(lat: float, lon: float) -> tuple[WeatherType, float, int]:
    with httpx.Client(timeout=httpx.Timeout(10.0, connect=5.0)) as client:
        response = client.get(
            _OPEN_METEO_URL,
            params={
                "latitude": lat,
                "longitude": lon,
                "current": "temperature_2m,weather_code",
            },
        )
        response.raise_for_status()
        payload = response.json()
    current = payload.get("current") or {}
    code = int(current.get("weather_code", -1))
    temp = float(current.get("temperature_2m", 0.0))
    return weather_type_from_wmo(code), temp, code


def get_weather(
    *,
    lat: float,
    lon: float,
    now: datetime | None = None,
) -> WeatherSnapshot:
    """Return cached or freshly fetched weather for the 5 km cell containing lat/lon."""
    when = now or datetime.now(timezone.utc)
    cell = cell_for(lat, lon)
    key = (cell.i, cell.j)
    now_mono = time.monotonic()

    with _cache_lock:
        hit = _cache.get(key)
        if hit is not None:
            expires_at, snap = hit
            if now_mono < expires_at:
                # Refresh weather_time for the caller's exact location/time.
                return WeatherSnapshot(
                    weather_type=snap.weather_type,
                    temperature_c=snap.temperature_c,
                    weather_time=period_at(
                        latitude=lat, longitude=lon, at=when
                    ),
                    observed_at=snap.observed_at,
                    cell=snap.cell,
                    wmo_code=snap.wmo_code,
                )

    weather_type, temp_c, wmo = _fetch_open_meteo(cell.center_lat, cell.center_lon)
    snap = WeatherSnapshot(
        weather_type=weather_type,
        temperature_c=temp_c,
        weather_time=period_at(latitude=lat, longitude=lon, at=when),
        observed_at=when.astimezone(timezone.utc),
        cell=cell,
        wmo_code=wmo,
    )
    with _cache_lock:
        _cache[key] = (now_mono + _CACHE_TTL_S, snap)
    return snap


def clear_weather_cache() -> None:
    """Test helper."""
    with _cache_lock:
        _cache.clear()
