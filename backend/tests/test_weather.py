"""Tests for solar period, WMO mapping, weather table, and forecast API."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from decimal import Decimal
from unittest.mock import MagicMock

import httpx
from sqlmodel import Session, col, select

from app.core.security import create_access_token
from app.models.data_source import DATA_SOURCE_FIELD
from app.models.site import Site
from app.models.user import User
from app.models.user_site import (
    USER_SITE_ROLE_DISCOVERER,
    USER_SITE_ROLE_EXHAUSTER,
    UserSite,
)
from app.models.weather import Weather
from app.services.site_common.constants import FIELD_SITE_ID_START
from app.services.weather_service.persist import (
    HourlySample,
    fetch_hourly_for_cells,
    list_active_weather_cells,
    prune_old_weather,
    sync_weather_for_active_cells,
    upsert_hourly_samples,
    weather_series,
)
from app.services.weather_service.service import (
    cell_for,
    clear_weather_cache,
    get_weather,
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


def _auth_headers(user: User) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token({'sub': str(user.id)})}"}


def _seed_user(session: Session, username: str = "wx_user") -> User:
    user = User(username=username, email=f"{username}@example.com", password="x")
    session.add(user)
    session.commit()
    session.refresh(user)
    return user


def _seed_field_site(
    session: Session,
    *,
    site_id: int,
    lat: float,
    lon: float,
) -> Site:
    site = Site(
        site_id=site_id,
        latitude=Decimal(str(lat)),
        longitude=Decimal(str(lon)),
        rock_type="sandstone",
        period="cretaceous",
        data_source=DATA_SOURCE_FIELD,
    )
    session.add(site)
    session.commit()
    return site


def test_list_active_weather_cells_excludes_hidden_and_exhausted(session: Session):
    user = _seed_user(session)
    lat, lon = 50.85, 4.35
    cell = cell_for(lat, lon)

    hidden_id = FIELD_SITE_ID_START
    discovered_id = FIELD_SITE_ID_START + 1
    exhausted_id = FIELD_SITE_ID_START + 2
    _seed_field_site(session, site_id=hidden_id, lat=lat, lon=lon)
    _seed_field_site(
        session, site_id=discovered_id, lat=lat + 0.001, lon=lon + 0.001
    )
    _seed_field_site(
        session, site_id=exhausted_id, lat=lat + 0.002, lon=lon + 0.002
    )
    now = datetime.now(timezone.utc)
    session.add(
        UserSite(
            user_id=user.id,
            site_id=discovered_id,
            role=USER_SITE_ROLE_DISCOVERER,
            timestamp=now,
        )
    )
    session.add(
        UserSite(
            user_id=user.id,
            site_id=exhausted_id,
            role=USER_SITE_ROLE_EXHAUSTER,
            timestamp=now,
        )
    )
    session.commit()

    cells = list_active_weather_cells(session)
    keys = {(c.i, c.j) for c in cells}
    assert (cell.i, cell.j) in keys
    assert len(cells) == 1


def test_upsert_hourly_samples_is_idempotent(session: Session):
    cell = cell_for(50.85, 4.35)
    valid_at = datetime(2026, 8, 5, 12, 0, tzinfo=timezone.utc)
    sample = HourlySample(
        valid_at=valid_at,
        weather_type="rain",
        temperature_c=12.5,
        wmo_code=61,
    )
    written = upsert_hourly_samples(session, cell, [sample])
    session.commit()
    assert written == 1

    sample2 = HourlySample(
        valid_at=valid_at,
        weather_type="overcast",
        temperature_c=11.0,
        wmo_code=3,
    )
    written2 = upsert_hourly_samples(session, cell, [sample2])
    session.commit()
    assert written2 == 1

    rows = session.exec(
        select(Weather).where(
            col(Weather.cell_i) == cell.i,
            col(Weather.cell_j) == cell.j,
        )
    ).all()
    assert len(rows) == 1
    assert rows[0].weather_type == "overcast"
    assert rows[0].temperature_c == 11.0
    assert rows[0].wmo_code == 3


def test_get_weather_prefers_db_over_live_api(session: Session, monkeypatch):
    clear_weather_cache()
    cell = cell_for(50.85, 4.35)
    # Prefer the later 15-min slot within the hour when both exist.
    now = datetime(2026, 8, 5, 12, 30, tzinfo=timezone.utc)
    slot = datetime(2026, 8, 5, 12, 15, tzinfo=timezone.utc)
    session.add(
        Weather(
            cell_i=cell.i,
            cell_j=cell.j,
            center_lat=cell.center_lat,
            center_lon=cell.center_lon,
            valid_at=slot,
            is_forecast=False,
            weather_type="snow",
            temperature_c=-2.0,
            wmo_code=71,
            fetched_at=now,
        )
    )
    session.commit()

    def _boom(*_args, **_kwargs):
        raise AssertionError("live Open-Meteo should not be called")

    monkeypatch.setattr(
        "app.services.weather_service.service._fetch_open_meteo",
        _boom,
    )
    snap = get_weather(lat=50.85, lon=4.35, now=now, session=session)
    assert snap.weather_type == "snow"
    assert snap.temperature_c == -2.0
    assert snap.wmo_code == 71


def test_get_weather_falls_back_when_stale(session: Session, monkeypatch):
    clear_weather_cache()
    cell = cell_for(50.85, 4.35)
    now = datetime(2026, 8, 5, 12, 30, tzinfo=timezone.utc)
    stale = now - timedelta(hours=5)
    session.add(
        Weather(
            cell_i=cell.i,
            cell_j=cell.j,
            center_lat=cell.center_lat,
            center_lon=cell.center_lon,
            valid_at=stale.replace(minute=0, second=0, microsecond=0),
            is_forecast=False,
            weather_type="fog",
            temperature_c=5.0,
            wmo_code=45,
            fetched_at=stale,
        )
    )
    session.commit()

    monkeypatch.setattr(
        "app.services.weather_service.service._fetch_open_meteo",
        lambda lat, lon: ("clear", 18.0, 0),
    )
    snap = get_weather(lat=50.85, lon=4.35, now=now, session=session)
    assert snap.weather_type == "clear"
    assert snap.temperature_c == 18.0


def test_fetch_minutely_for_cells_parses_open_meteo_payload(monkeypatch):
    cell = cell_for(50.85, 4.35)
    payload = {
        "minutely_15": {
            "time": ["2026-08-05T10:00", "2026-08-05T10:15"],
            "temperature_2m": [10.0, 11.5],
            "weather_code": [0, 61],
        }
    }

    class _Resp:
        def raise_for_status(self) -> None:
            return None

        def json(self):
            return payload

    client = MagicMock(spec=httpx.Client)
    client.get.return_value = _Resp()

    by_cell = fetch_hourly_for_cells([cell], client=client)
    samples = by_cell[(cell.i, cell.j)]
    assert len(samples) == 2
    assert samples[0].weather_type == "clear"
    assert samples[1].weather_type == "rain"
    assert samples[1].temperature_c == 11.5
    assert samples[1].valid_at.minute == 15
    # Request should ask for minutely_15, not hourly.
    params = client.get.call_args.kwargs.get("params") or client.get.call_args[1].get(
        "params"
    )
    assert "minutely_15" in params
    assert "hourly" not in params


def test_sync_weather_dry_run_does_not_write(session: Session, monkeypatch):
    user = _seed_user(session, "wx_sync")
    lat, lon = 50.85, 4.35
    site = _seed_field_site(
        session, site_id=FIELD_SITE_ID_START + 10, lat=lat, lon=lon
    )
    session.add(
        UserSite(
            user_id=user.id,
            site_id=site.site_id,
            role=USER_SITE_ROLE_DISCOVERER,
            timestamp=datetime.now(timezone.utc),
        )
    )
    session.commit()

    cell = cell_for(lat, lon)

    def _fake_fetch(cells, **_kwargs):
        return {
            (cell.i, cell.j): [
                HourlySample(
                    valid_at=datetime(2026, 8, 5, 12, 0, tzinfo=timezone.utc),
                    weather_type="clear",
                    temperature_c=20.0,
                    wmo_code=0,
                )
            ]
        }

    monkeypatch.setattr(
        "app.services.weather_service.persist.fetch_minutely_for_cells",
        _fake_fetch,
    )
    summary = sync_weather_for_active_cells(session, dry_run=True)
    assert summary.cells == 1
    assert summary.upserted == 1
    assert summary.dry_run is True
    assert session.exec(select(Weather)).first() is None


def test_prune_old_weather(session: Session):
    cell = cell_for(50.85, 4.35)
    now = datetime(2026, 8, 5, 12, 0, tzinfo=timezone.utc)
    session.add(
        Weather(
            cell_i=cell.i,
            cell_j=cell.j,
            center_lat=cell.center_lat,
            center_lon=cell.center_lon,
            valid_at=now - timedelta(days=10),
            is_forecast=False,
            weather_type="clear",
            temperature_c=1.0,
            wmo_code=0,
            fetched_at=now,
        )
    )
    session.add(
        Weather(
            cell_i=cell.i,
            cell_j=cell.j,
            center_lat=cell.center_lat,
            center_lon=cell.center_lon,
            valid_at=now - timedelta(hours=1),
            is_forecast=False,
            weather_type="rain",
            temperature_c=2.0,
            wmo_code=61,
            fetched_at=now,
        )
    )
    session.commit()
    deleted = prune_old_weather(session, older_than_days=7, now=now)
    session.commit()
    assert deleted == 1
    rows = session.exec(select(Weather)).all()
    assert len(rows) == 1
    assert rows[0].weather_type == "rain"


def test_weather_forecast_api(client, session: Session):
    user = _seed_user(session, "wx_api")
    cell = cell_for(50.85, 4.35)
    now = datetime(2026, 8, 5, 12, 0, tzinfo=timezone.utc)
    past = now - timedelta(hours=1)
    future = now + timedelta(hours=1)
    for valid_at, is_forecast, wtype, temp, code in (
        (past, False, "rain", 10.0, 61),
        (now, False, "cloudy", 12.0, 2),
        (future, True, "clear", 14.0, 0),
    ):
        session.add(
            Weather(
                cell_i=cell.i,
                cell_j=cell.j,
                center_lat=cell.center_lat,
                center_lon=cell.center_lon,
                valid_at=valid_at,
                is_forecast=is_forecast,
                weather_type=wtype,
                temperature_c=temp,
                wmo_code=code,
                fetched_at=now,
            )
        )
    session.commit()

    response = client.get(
        "/api/v1/weather/forecast",
        params={"lat": 50.85, "lon": 4.35, "past_hours": 6, "forecast_hours": 6},
        headers=_auth_headers(user),
    )
    assert response.status_code == 200
    body = response.json()
    assert body["cell"]["i"] == cell.i
    assert body["cell"]["j"] == cell.j
    assert len(body["hours"]) == 3
    assert body["hours"][0]["weather_type"] == "rain"
    assert body["hours"][2]["is_forecast"] is True

    series = weather_series(
        session, lat=50.85, lon=4.35, past_hours=6, forecast_hours=6, now=now
    )
    assert len(series) == 3
