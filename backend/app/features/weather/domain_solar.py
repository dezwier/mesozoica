"""Feature-owned location-aware solar period (NOAA formulas; mirrors Flutter Solar).

No network — given lat/lon/UTC, returns dawn|day|dusk|golden_hour|night
from sun elevation.
"""

from __future__ import annotations

import math
from datetime import datetime, timedelta, timezone
from typing import Literal

WeatherTime = Literal["dawn", "day", "dusk", "golden_hour", "night"]

CIVIL_TWILIGHT_ELEVATION_DEG = -6.0
GOLDEN_HOUR_ELEVATION_DEG = 6.0


def _julian_day(utc: datetime) -> float:
    y = utc.year
    m = utc.month
    d = (
        utc.day
        + (
            utc.hour
            + utc.minute / 60.0
            + (utc.second + utc.microsecond / 1_000_000.0) / 3600.0
        )
        / 24.0
    )
    year = y
    month = m
    if month <= 2:
        year -= 1
        month += 12
    a = year // 100
    b = 2 - a + a // 4
    return (
        math.floor(365.25 * (year + 4716))
        + math.floor(30.6001 * (month + 1))
        + d
        + b
        - 1524.5
    )


def _julian_century(julian_day: float) -> float:
    return (julian_day - 2451545.0) / 36525.0


def _geom_mean_long_sun_deg(jc: float) -> float:
    l = (280.46646 + jc * (36000.76983 + 0.0003032 * jc)) % 360.0
    if l < 0:
        l += 360.0
    return l


def _geom_mean_anomaly_sun_deg(jc: float) -> float:
    return 357.52911 + jc * (35999.05029 - 0.0001537 * jc)


def _sun_declination_rad(jc: float) -> float:
    geom_mean_long = _geom_mean_long_sun_deg(jc)
    geom_mean_anom = _geom_mean_anomaly_sun_deg(jc)
    sun_eq_of_ctr = (
        math.sin(math.radians(geom_mean_anom))
        * (1.914602 - jc * (0.004817 + 0.000014 * jc))
        + math.sin(math.radians(2 * geom_mean_anom)) * (0.019993 - 0.000101 * jc)
        + math.sin(math.radians(3 * geom_mean_anom)) * 0.000289
    )
    sun_true_long = geom_mean_long + sun_eq_of_ctr
    sun_app_long = (
        sun_true_long
        - 0.00569
        - 0.00478 * math.sin(math.radians(125.04 - 1934.136 * jc))
    )
    mean_obliq = (
        23.0
        + (
            26.0
            + (
                21.448
                - jc * (46.815 + jc * (0.00059 - jc * 0.001813))
            )
            / 60.0
        )
        / 60.0
    )
    obliq_corr = mean_obliq + 0.00256 * math.cos(
        math.radians(125.04 - 1934.136 * jc)
    )
    return math.asin(
        math.sin(math.radians(obliq_corr)) * math.sin(math.radians(sun_app_long))
    )


def _equation_of_time_minutes(jc: float) -> float:
    geom_mean_long = _geom_mean_long_sun_deg(jc)
    geom_mean_anom = _geom_mean_anomaly_sun_deg(jc)
    eccent_earth = 0.016708634 - jc * (0.000042037 + 0.0000001267 * jc)
    mean_obliq = (
        23.0
        + (
            26.0
            + (
                21.448
                - jc * (46.815 + jc * (0.00059 - jc * 0.001813))
            )
            / 60.0
        )
        / 60.0
    )
    obliq_corr = mean_obliq + 0.00256 * math.cos(
        math.radians(125.04 - 1934.136 * jc)
    )
    y = math.tan(math.radians(obliq_corr) / 2.0) ** 2
    l0 = math.radians(geom_mean_long)
    e = eccent_earth
    m = math.radians(geom_mean_anom)
    eq_rad = (
        y * math.sin(2 * l0)
        - 2 * e * math.sin(m)
        + 4 * e * y * math.sin(m) * math.cos(2 * l0)
        - 0.5 * y * y * math.sin(4 * l0)
        - 1.25 * e * e * math.sin(2 * m)
    )
    return 4.0 * math.degrees(eq_rad)


def _hour_angle_degrees(utc: datetime, longitude: float, eq_time_minutes: float) -> float:
    minutes = (
        utc.hour * 60.0
        + utc.minute
        + utc.second / 60.0
        + utc.microsecond / 60_000_000.0
    )
    true_solar = minutes + eq_time_minutes + 4.0 * longitude
    true_solar = true_solar % 1440.0
    if true_solar < 0:
        true_solar += 1440.0
    ha = true_solar / 4.0
    return ha + 180.0 if ha < 0 else ha - 180.0


def solar_noon_utc(*, longitude: float, day: datetime) -> datetime:
    utc_day = datetime(day.year, day.month, day.day, tzinfo=timezone.utc)
    noon_seed = utc_day.replace(hour=12)
    jc = _julian_century(_julian_day(noon_seed))
    eq_time = _equation_of_time_minutes(jc)
    noon_minutes = 720.0 - 4.0 * longitude - eq_time
    noon = utc_day + timedelta(milliseconds=round(noon_minutes * 60000))
    jc = _julian_century(_julian_day(noon))
    eq_time = _equation_of_time_minutes(jc)
    noon_minutes = 720.0 - 4.0 * longitude - eq_time
    return utc_day + timedelta(milliseconds=round(noon_minutes * 60000))


def elevation_degrees(
    *,
    latitude: float,
    longitude: float,
    at: datetime | None = None,
) -> float:
    when = at or datetime.now(timezone.utc)
    utc = when.astimezone(timezone.utc) if when.tzinfo else when.replace(tzinfo=timezone.utc)
    jc = _julian_century(_julian_day(utc))
    decl = _sun_declination_rad(jc)
    eq_time = _equation_of_time_minutes(jc)
    hour_angle = _hour_angle_degrees(utc, longitude, eq_time)
    lat_rad = math.radians(latitude)
    cos_zenith = math.sin(lat_rad) * math.sin(decl) + math.cos(lat_rad) * math.cos(
        decl
    ) * math.cos(math.radians(hour_angle))
    cos_zenith = max(-1.0, min(1.0, cos_zenith))
    zenith = math.degrees(math.acos(cos_zenith))
    return 90.0 - zenith


def period_at(
    *,
    latitude: float,
    longitude: float,
    at: datetime | None = None,
) -> WeatherTime:
    """Dawn / day / dusk / golden_hour / night at a point in time.

    Thresholds (sun elevation above horizon):
    - day: ≥ 6°
    - golden_hour: 0° ≤ elev < 6°
    - dawn / dusk: −6° ≤ elev < 0° (civil twilight; morning vs afternoon)
    - night: < −6°
    """
    when = at or datetime.now(timezone.utc)
    utc = when.astimezone(timezone.utc) if when.tzinfo else when.replace(tzinfo=timezone.utc)
    elev = elevation_degrees(latitude=latitude, longitude=longitude, at=utc)
    if elev >= GOLDEN_HOUR_ELEVATION_DEG:
        return "day"
    if elev >= 0:
        return "golden_hour"
    if elev >= CIVIL_TWILIGHT_ELEVATION_DEG:
        noon = solar_noon_utc(longitude=longitude, day=utc)
        return "dawn" if utc < noon else "dusk"
    return "night"
