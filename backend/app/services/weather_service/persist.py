"""Persist Open-Meteo 15-minute series into the weather table."""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any

import httpx
from sqlalchemy.orm import aliased
from sqlmodel import Session, col, delete, select

from app.models.data_source import DATA_SOURCE_FIELD
from app.models.site import Site
from app.models.user_site import (
    SITE_STATUS_EXHAUSTED,
    SITE_STATUS_HIDDEN,
    UserSite,
    role_to_status,
)
from app.models.weather import Weather
from app.services.site_service.status_join import (
    latest_user_site_join_condition,
    latest_user_site_subquery,
)
from app.services.weather_service.service import (
    WeatherCell,
    cell_for,
    weather_type_from_wmo,
)

logger = logging.getLogger(__name__)

_OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast"
_DEFAULT_PAST_DAYS = 2
_DEFAULT_FORECAST_DAYS = 3
_DEFAULT_BATCH_SIZE = 50
_DEFAULT_PRUNE_DAYS = 7
_LatestUserSite = aliased(UserSite)


@dataclass(frozen=True)
class WeatherSample:
    valid_at: datetime
    weather_type: str
    temperature_c: float
    wmo_code: int


# Back-compat alias for tests / callers.
HourlySample = WeatherSample


@dataclass(frozen=True)
class WeatherSyncSummary:
    cells: int
    upserted: int
    pruned: int
    errors: int
    dry_run: bool


def list_active_weather_cells(session: Session) -> list[WeatherCell]:
    """Distinct ~5 km cells containing non-hidden, non-exhausted field sites."""
    max_ts = latest_user_site_subquery()
    stmt = (
        select(Site, _LatestUserSite)
        .outerjoin(max_ts, col(Site.site_id) == max_ts.c.site_id)
        .outerjoin(
            _LatestUserSite,
            latest_user_site_join_condition(_LatestUserSite, max_ts),
        )
        .where(
            col(Site.data_source) == DATA_SOURCE_FIELD,
            col(Site.latitude).is_not(None),
            col(Site.longitude).is_not(None),
        )
    )
    seen: set[tuple[int, int]] = set()
    cells: list[WeatherCell] = []
    for site, latest in session.exec(stmt).all():
        if site.latitude is None or site.longitude is None:
            continue
        status = role_to_status(latest.role if latest is not None else None)
        if status in (SITE_STATUS_HIDDEN, SITE_STATUS_EXHAUSTED):
            continue
        cell = cell_for(float(site.latitude), float(site.longitude))
        key = (cell.i, cell.j)
        if key in seen:
            continue
        seen.add(key)
        cells.append(cell)
    return cells


def _parse_valid_at(raw: str) -> datetime:
    text = str(raw).strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    parsed = datetime.fromisoformat(text)
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _samples_from_payload(payload: dict[str, Any]) -> list[WeatherSample]:
    """Prefer ``minutely_15``; fall back to ``hourly`` for older fixtures."""
    block = payload.get("minutely_15") or payload.get("hourly") or {}
    times = block.get("time") or []
    temps = block.get("temperature_2m") or []
    codes = block.get("weather_code") or []
    samples: list[WeatherSample] = []
    for idx, raw_time in enumerate(times):
        if idx >= len(temps) or idx >= len(codes):
            break
        temp_raw = temps[idx]
        code_raw = codes[idx]
        if temp_raw is None or code_raw is None:
            continue
        code = int(code_raw)
        samples.append(
            WeatherSample(
                valid_at=_parse_valid_at(raw_time),
                weather_type=weather_type_from_wmo(code),
                temperature_c=float(temp_raw),
                wmo_code=code,
            )
        )
    return samples


def fetch_minutely_for_cells(
    cells: list[WeatherCell],
    *,
    past_days: int = _DEFAULT_PAST_DAYS,
    forecast_days: int = _DEFAULT_FORECAST_DAYS,
    client: httpx.Client | None = None,
) -> dict[tuple[int, int], list[WeatherSample]]:
    """Fetch 15-minute past+forecast for each cell; keyed by (i, j)."""
    if not cells:
        return {}

    owns_client = client is None
    if client is None:
        client = httpx.Client(timeout=httpx.Timeout(30.0, connect=10.0))
    try:
        params = {
            "latitude": ",".join(f"{c.center_lat:.6f}" for c in cells),
            "longitude": ",".join(f"{c.center_lon:.6f}" for c in cells),
            "minutely_15": "temperature_2m,weather_code",
            "past_days": past_days,
            "forecast_days": forecast_days,
            "timezone": "UTC",
            "models": "icon_seamless",
        }
        response = client.get(_OPEN_METEO_URL, params=params)
        response.raise_for_status()
        payload = response.json()
    finally:
        if owns_client:
            client.close()

    payloads: list[dict[str, Any]]
    if isinstance(payload, list):
        payloads = payload
    else:
        payloads = [payload]

    out: dict[tuple[int, int], list[WeatherSample]] = {}
    for cell, item in zip(cells, payloads, strict=False):
        if not isinstance(item, dict):
            continue
        out[(cell.i, cell.j)] = _samples_from_payload(item)
    return out


# Back-compat name used by tests / monkeypatches.
fetch_hourly_for_cells = fetch_minutely_for_cells


def upsert_weather_samples(
    session: Session,
    cell: WeatherCell,
    samples: list[WeatherSample],
    *,
    fetched_at: datetime | None = None,
) -> int:
    """Upsert weather samples for one cell. Returns number of rows written."""
    when = fetched_at or datetime.now(timezone.utc)
    if when.tzinfo is None:
        when = when.replace(tzinfo=timezone.utc)
    else:
        when = when.astimezone(timezone.utc)

    if not samples:
        return 0

    valid_times = [s.valid_at for s in samples]

    def _aware(dt: datetime) -> datetime:
        if dt.tzinfo is None:
            return dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)

    existing_rows = session.exec(
        select(Weather).where(
            col(Weather.cell_i) == cell.i,
            col(Weather.cell_j) == cell.j,
            col(Weather.valid_at).in_(valid_times),
        )
    ).all()
    by_valid = {_aware(row.valid_at): row for row in existing_rows}

    written = 0
    for sample in samples:
        valid_at = _aware(sample.valid_at)
        is_forecast = valid_at > when
        row = by_valid.get(valid_at)
        if row is None:
            session.add(
                Weather(
                    cell_i=cell.i,
                    cell_j=cell.j,
                    center_lat=cell.center_lat,
                    center_lon=cell.center_lon,
                    valid_at=valid_at,
                    is_forecast=is_forecast,
                    weather_type=sample.weather_type,
                    temperature_c=sample.temperature_c,
                    wmo_code=sample.wmo_code,
                    fetched_at=when,
                )
            )
        else:
            row.center_lat = cell.center_lat
            row.center_lon = cell.center_lon
            row.is_forecast = is_forecast
            row.weather_type = sample.weather_type
            row.temperature_c = sample.temperature_c
            row.wmo_code = sample.wmo_code
            row.fetched_at = when
            session.add(row)
        written += 1
    return written


upsert_hourly_samples = upsert_weather_samples


def prune_old_weather(
    session: Session,
    *,
    older_than_days: int = _DEFAULT_PRUNE_DAYS,
    now: datetime | None = None,
) -> int:
    """Delete weather rows older than the retention window. Returns deleted count."""
    when = now or datetime.now(timezone.utc)
    if when.tzinfo is None:
        when = when.replace(tzinfo=timezone.utc)
    else:
        when = when.astimezone(timezone.utc)
    cutoff = when - timedelta(days=older_than_days)
    ids: list[int] = []
    for row in session.exec(select(Weather)).all():
        valid = row.valid_at
        if valid.tzinfo is None:
            valid = valid.replace(tzinfo=timezone.utc)
        else:
            valid = valid.astimezone(timezone.utc)
        if valid < cutoff and row.id is not None:
            ids.append(row.id)
    if not ids:
        return 0
    session.exec(delete(Weather).where(col(Weather.id).in_(ids)))
    return len(ids)


def recent_weather(
    session: Session,
    *,
    lat: float,
    lon: float,
    hours: int = 24,
    now: datetime | None = None,
) -> list[Weather]:
    """Return recent weather rows for the cell containing lat/lon (oldest first)."""
    when = now or datetime.now(timezone.utc)
    if when.tzinfo is None:
        when = when.replace(tzinfo=timezone.utc)
    cell = cell_for(lat, lon)
    start = when - timedelta(hours=hours)
    rows = session.exec(
        select(Weather)
        .where(
            col(Weather.cell_i) == cell.i,
            col(Weather.cell_j) == cell.j,
            col(Weather.valid_at) >= start,
            col(Weather.valid_at) <= when,
        )
        .order_by(col(Weather.valid_at).asc())
    ).all()
    return list(rows)


def weather_series(
    session: Session,
    *,
    lat: float,
    lon: float,
    past_hours: int = 48,
    forecast_hours: int = 72,
    now: datetime | None = None,
) -> list[Weather]:
    """Past + forecast weather rows for the cell containing lat/lon."""
    when = now or datetime.now(timezone.utc)
    if when.tzinfo is None:
        when = when.replace(tzinfo=timezone.utc)
    cell = cell_for(lat, lon)
    start = when - timedelta(hours=past_hours)
    end = when + timedelta(hours=forecast_hours)
    rows = session.exec(
        select(Weather)
        .where(
            col(Weather.cell_i) == cell.i,
            col(Weather.cell_j) == cell.j,
            col(Weather.valid_at) >= start,
            col(Weather.valid_at) <= end,
        )
        .order_by(col(Weather.valid_at).asc())
    ).all()
    return list(rows)


def sync_weather_for_active_cells(
    session: Session,
    *,
    past_days: int = _DEFAULT_PAST_DAYS,
    forecast_days: int = _DEFAULT_FORECAST_DAYS,
    batch_size: int = _DEFAULT_BATCH_SIZE,
    prune_days: int = _DEFAULT_PRUNE_DAYS,
    dry_run: bool = False,
    client: httpx.Client | None = None,
) -> WeatherSyncSummary:
    """Fetch and upsert 15-minute weather for all active cells; prune stale rows."""
    cells = list_active_weather_cells(session)
    upserted = 0
    errors = 0
    fetched_at = datetime.now(timezone.utc)

    owns_client = client is None
    if client is None:
        client = httpx.Client(timeout=httpx.Timeout(30.0, connect=10.0))
    try:
        for start in range(0, len(cells), max(batch_size, 1)):
            batch = cells[start : start + max(batch_size, 1)]
            try:
                by_cell = fetch_minutely_for_cells(
                    batch,
                    past_days=past_days,
                    forecast_days=forecast_days,
                    client=client,
                )
            except Exception:
                logger.exception(
                    "Open-Meteo batch failed for %d cells starting at %d",
                    len(batch),
                    start,
                )
                errors += len(batch)
                continue
            if dry_run:
                upserted += sum(len(samples) for samples in by_cell.values())
                continue
            for cell in batch:
                samples = by_cell.get((cell.i, cell.j), [])
                upserted += upsert_weather_samples(
                    session, cell, samples, fetched_at=fetched_at
                )
            session.commit()
    finally:
        if owns_client:
            client.close()

    pruned = 0
    if not dry_run:
        pruned = prune_old_weather(session, older_than_days=prune_days, now=fetched_at)
        if pruned:
            session.commit()

    return WeatherSyncSummary(
        cells=len(cells),
        upserted=upserted,
        pruned=pruned,
        errors=errors,
        dry_run=dry_run,
    )
