"""Open-Meteo weather fetch with DB-backed 15-minute cache (~5 km cells)."""

from __future__ import annotations

import logging
import math
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Literal

import httpx
from sqlmodel import Session, col, select

from app.core.database import engine
from app.models.weather import Weather
from app.services.weather_service.solar import period_at

logger = logging.getLogger(__name__)

WeatherType = Literal[
    "clear",
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
# Align with weather_sync + Flutter poll so skill impacts see new 15-min rows.
_CACHE_TTL_S = 15 * 60
_STALE_AFTER = timedelta(hours=2)
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
    """Map Open-Meteo WMO weather interpretation codes to game types.

    ``cloudy`` is WMO partly cloudy (2); mainly clear (1) folds into ``clear``.
    UI labels ``cloudy`` as \"Partly cloudy\".
    """
    if code in (0, 1):
        return "clear"
    if code == 2:
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
                # DWD ICON via seamless blend — Open-Meteo's default
                # (often KNMI in BE/NL) can report overcast when sky is clear.
                "models": "icon_seamless",
            },
        )
        response.raise_for_status()
        payload = response.json()
    current = payload.get("current") or {}
    code = int(current.get("weather_code", -1))
    temp = float(current.get("temperature_2m", 0.0))
    return weather_type_from_wmo(code), temp, code


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _quarter_hour_floor(when: datetime) -> datetime:
    """Floor to the enclosing 15-minute UTC slot (matches Open-Meteo minutely_15)."""
    when = _as_utc(when)
    return when.replace(minute=(when.minute // 15) * 15, second=0, microsecond=0)


def _row_to_snapshot(
    row: Weather,
    *,
    lat: float,
    lon: float,
    when: datetime,
) -> WeatherSnapshot:
    weather_type = weather_type_from_wmo(row.wmo_code)
    if row.weather_type in (
        "clear",
        "cloudy",
        "overcast",
        "fog",
        "drizzle",
        "rain",
        "snow",
        "thunderstorm",
        "hail",
        "unknown",
    ):
        weather_type = row.weather_type  # type: ignore[assignment]
    cell = WeatherCell(
        i=row.cell_i,
        j=row.cell_j,
        center_lat=row.center_lat,
        center_lon=row.center_lon,
    )
    return WeatherSnapshot(
        weather_type=weather_type,
        temperature_c=float(row.temperature_c),
        weather_time=period_at(latitude=lat, longitude=lon, at=when),
        observed_at=_as_utc(row.valid_at),
        cell=cell,
        wmo_code=int(row.wmo_code),
    )


def _latest_db_row(
    session: Session,
    cell: WeatherCell,
    *,
    when: datetime,
) -> Weather | None:
    return session.exec(
        select(Weather)
        .where(
            col(Weather.cell_i) == cell.i,
            col(Weather.cell_j) == cell.j,
            col(Weather.valid_at) <= when,
        )
        .order_by(col(Weather.valid_at).desc())
        .limit(1)
    ).first()


def _write_through_current(
    session: Session,
    cell: WeatherCell,
    *,
    weather_type: WeatherType,
    temperature_c: float,
    wmo_code: int,
    when: datetime,
) -> None:
    """Upsert the current 15-minute slot from a live Open-Meteo current fetch."""
    valid_at = _quarter_hour_floor(when)
    existing = session.exec(
        select(Weather).where(
            col(Weather.cell_i) == cell.i,
            col(Weather.cell_j) == cell.j,
            col(Weather.valid_at) == valid_at,
        )
    ).first()
    if existing is None:
        session.add(
            Weather(
                cell_i=cell.i,
                cell_j=cell.j,
                center_lat=cell.center_lat,
                center_lon=cell.center_lon,
                valid_at=valid_at,
                is_forecast=False,
                weather_type=weather_type,
                temperature_c=temperature_c,
                wmo_code=wmo_code,
                fetched_at=_as_utc(when),
            )
        )
    else:
        existing.center_lat = cell.center_lat
        existing.center_lon = cell.center_lon
        existing.is_forecast = False
        existing.weather_type = weather_type
        existing.temperature_c = temperature_c
        existing.wmo_code = wmo_code
        existing.fetched_at = _as_utc(when)
        session.add(existing)
    try:
        session.commit()
    except Exception:
        session.rollback()
        logger.exception("Weather write-through failed for cell %s,%s", cell.i, cell.j)


def get_weather(
    *,
    lat: float,
    lon: float,
    now: datetime | None = None,
    session: Session | None = None,
) -> WeatherSnapshot:
    """Return weather for the 5 km cell containing lat/lon.

    Prefers the latest stored 15-minute row (``valid_at <= now``). Falls back to
    live Open-Meteo ``current`` when missing or older than two hours.
    """
    when = now or datetime.now(timezone.utc)
    when = _as_utc(when)
    cell = cell_for(lat, lon)
    key = (cell.i, cell.j)
    now_mono = time.monotonic()

    with _cache_lock:
        hit = _cache.get(key)
        if hit is not None:
            expires_at, snap = hit
            if now_mono < expires_at:
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

    owns_session = session is None
    db = session or Session(engine)
    try:
        row = _latest_db_row(db, cell, when=when)
        if row is not None and _as_utc(row.valid_at) >= when - _STALE_AFTER:
            snap = _row_to_snapshot(row, lat=lat, lon=lon, when=when)
            with _cache_lock:
                _cache[key] = (now_mono + _CACHE_TTL_S, snap)
            return snap
    finally:
        if owns_session:
            db.close()

    weather_type, temp_c, wmo = _fetch_open_meteo(cell.center_lat, cell.center_lon)
    snap = WeatherSnapshot(
        weather_type=weather_type,
        temperature_c=temp_c,
        weather_time=period_at(latitude=lat, longitude=lon, at=when),
        observed_at=when,
        cell=cell,
        wmo_code=wmo,
    )
    with _cache_lock:
        _cache[key] = (now_mono + _CACHE_TTL_S, snap)

    # Best-effort warm the table for this cell (does not fail the request).
    try:
        with Session(engine) as write_session:
            _write_through_current(
                write_session,
                cell,
                weather_type=weather_type,
                temperature_c=temp_c,
                wmo_code=wmo,
                when=when,
            )
    except Exception:
        logger.exception("Weather write-through session failed")

    return snap


def clear_weather_cache() -> None:
    """Test helper."""
    with _cache_lock:
        _cache.clear()
