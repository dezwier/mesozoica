"""Tests for solar period and Open-Meteo WMO mapping."""

from __future__ import annotations

from datetime import datetime, timezone

from app.services.weather_service.service import (
    cell_for,
    clear_weather_cache,
    weather_type_from_wmo,
)
from app.services.weather_service.solar import elevation_degrees, period_at


def test_weather_type_from_wmo_mapping() -> None:
    assert weather_type_from_wmo(0) == "clear"
    assert weather_type_from_wmo(1) == "clear"  # mainly clear
    assert weather_type_from_wmo(2) == "cloudy"  # partly cloudy (UI label)
    assert weather_type_from_wmo(3) == "overcast"
    assert weather_type_from_wmo(45) == "fog"
    assert weather_type_from_wmo(51) == "drizzle"
    assert weather_type_from_wmo(61) == "rain"
    assert weather_type_from_wmo(71) == "snow"
    assert weather_type_from_wmo(95) == "thunderstorm"
    assert weather_type_from_wmo(96) == "hail"
    assert weather_type_from_wmo(999) == "unknown"


def test_cell_for_same_neighborhood() -> None:
    clear_weather_cache()
    a = cell_for(50.8503, 4.3517)  # Brussels
    b = cell_for(50.8510, 4.3520)  # ~100 m away
    assert a.i == b.i
    assert a.j == b.j


def test_period_at_brussels_noon_summer_is_day() -> None:
    # Midday UTC in Brussels summer — sun well above horizon (≥ 6°).
    noon = datetime(2024, 6, 21, 12, 0, tzinfo=timezone.utc)
    assert period_at(latitude=50.85, longitude=4.35, at=noon) == "day"
    elev = elevation_degrees(latitude=50.85, longitude=4.35, at=noon)
    assert elev > 6


def test_period_at_brussels_midnight_is_night() -> None:
    midnight = datetime(2024, 6, 21, 0, 0, tzinfo=timezone.utc)
    assert period_at(latitude=50.85, longitude=4.35, at=midnight) == "night"
    elev = elevation_degrees(latitude=50.85, longitude=4.35, at=midnight)
    assert elev < -6


def test_period_at_golden_hour_near_sunset() -> None:
    # Brussels mid-July: find a UTC instant with 0° ≤ elev < 6°.
    lat, lon = 50.85, 4.35
    found = None
    for hour in range(17, 21):
        for minute in (0, 15, 30, 45):
            when = datetime(2024, 7, 20, hour, minute, tzinfo=timezone.utc)
            elev = elevation_degrees(latitude=lat, longitude=lon, at=when)
            if 0 <= elev < 6:
                found = when
                break
        if found is not None:
            break
    assert found is not None, "expected a golden-hour sample in Brussels July evening"
    assert period_at(latitude=lat, longitude=lon, at=found) == "golden_hour"


def test_period_at_varies_by_longitude() -> None:
    # Same UTC instant: sun over Pacific → day near International Date Line west,
    # night near western Europe.
    when = datetime(2024, 6, 21, 12, 0, tzinfo=timezone.utc)
    europe = period_at(latitude=50.0, longitude=4.0, at=when)
    pacific = period_at(latitude=0.0, longitude=-150.0, at=when)
    assert europe == "day"
    assert pacific == "night"
