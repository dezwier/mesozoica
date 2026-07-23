"""Tests for lazy field site generation near a player."""

from __future__ import annotations

import math
import random
import time
from decimal import Decimal

import pytest
from shapely.geometry import box
from sqlmodel import Session, col, select

from app.models.data_source import DATA_SOURCE_ARCHIVE, DATA_SOURCE_FIELD
from app.models.field_ensure_job import FieldEnsureJob
from app.models.site import Site
from app.models.site_type import SiteType
from app.models.user_site import (
    SITE_STATUS_HIDDEN,
    USER_SITE_ROLE_EXHAUSTER,
    UserSite,
)
from app.models.user import User
from app.services.site_service.field_coordinate_filter import CoordinateSampler, LandPolygonFilter
from app.services.site_service.field_generate import (
    FIELD_SITE_ID_START,
    FieldSiteLazyConfig,
    _next_field_site_id,
    ensure_field_sites_nearby,
)
from app.services.site_service.geo_utils import haversine_km


def _archive_site(
    *,
    site_id: int,
    lat: float,
    lon: float,
    period: str = "cretaceous",
    rock_type: str = "sandstone",
) -> Site:
    return Site(
        site_id=site_id,
        latitude=Decimal(str(lat)),
        longitude=Decimal(str(lon)),
        country_code="US",
        state="Montana",
        rock_type=rock_type,
        period=period,
        data_source=DATA_SOURCE_ARCHIVE,
    )


def _site_type(*, period: str, rock_type: str) -> SiteType:
    return SiteType(period=period, rock_type=rock_type)


def _test_coordinate_sampler(center_lat: float, center_lon: float, radius_km: float) -> CoordinateSampler:
    lat_delta = radius_km / 111.0
    cos_lat = max(abs(math.cos(math.radians(center_lat))), 1e-6)
    lon_delta = radius_km / (111.0 * cos_lat)
    geometry = box(
        center_lon - lon_delta,
        center_lat - lat_delta,
        center_lon + lon_delta,
        center_lat + lat_delta,
    )
    land_filter = LandPolygonFilter.from_polygons([geometry], source_path="test")
    return CoordinateSampler(land_filter)


def test_ensure_generates_when_below_minimum(session: Session, monkeypatch):
    session.add(_site_type(period="cretaceous", rock_type="sandstone"))
    session.add(_archive_site(site_id=100, lat=40.0, lon=-100.0))
    session.commit()


    center_lat, center_lon = 40.0, -100.0
    mask = _test_coordinate_sampler(center_lat, center_lon, radius_km=1.0)
    config = FieldSiteLazyConfig(
        min_sites_in_radius=5,
        radius_km=1.0,
        min_separation_km=0.05,
        max_coordinate_attempts=50,
    )

    result = ensure_field_sites_nearby(
        session,
        lat=center_lat,
        lon=center_lon,
        config=config,
        rng=random.Random(1),
        coordinate_sampler=mask,
    )

    assert result.generated == 5
    assert result.total_in_radius == 5
    assert len(result.items) == 5
    for row in result.items:
        site = row.site
        assert site.data_source == DATA_SOURCE_FIELD
        assert row.status == SITE_STATUS_HIDDEN
        distance = haversine_km(
            center_lat,
            center_lon,
            float(site.latitude),
            float(site.longitude),
        )
        assert distance <= config.radius_km


def test_ensure_skips_when_minimum_already_met(session: Session, monkeypatch):
    site_type = _site_type(period="cretaceous", rock_type="sandstone")
    session.add(site_type)
    session.add(_archive_site(site_id=100, lat=40.0, lon=-100.0))
    session.commit()
    session.refresh(site_type)

    center_lat, center_lon = 40.0, -100.0
    for index in range(3):
        session.add(
            Site(
                site_id=FIELD_SITE_ID_START + index,
                latitude=Decimal(str(center_lat + index * 0.001)),
                longitude=Decimal(str(center_lon + index * 0.001)),
                rock_type="sandstone",
                period="cretaceous",
                site_type_id=site_type.id,
                data_source=DATA_SOURCE_FIELD,
            )
        )
    session.commit()


    config = FieldSiteLazyConfig(min_sites_in_radius=3, radius_km=1.0)
    result = ensure_field_sites_nearby(
        session,
        lat=center_lat,
        lon=center_lon,
        config=config,
        coordinate_sampler=_test_coordinate_sampler(center_lat, center_lon, radius_km=1.0),
    )

    assert result.generated == 0
    assert result.total_in_radius == 3


def test_ensure_tops_up_when_sites_are_exhausted(session: Session, monkeypatch):
    from datetime import datetime, timezone

    session.add(_site_type(period="cretaceous", rock_type="sandstone"))
    session.add(_archive_site(site_id=100, lat=40.0, lon=-100.0))
    user = User(username="exhauster", email="exhauster@example.com", password="x")
    session.add(user)
    session.commit()
    session.refresh(user)

    center_lat, center_lon = 40.0, -100.0
    for index in range(5):
        site_id = FIELD_SITE_ID_START + index
        session.add(
            Site(
                site_id=site_id,
                latitude=Decimal(str(center_lat + index * 0.001)),
                longitude=Decimal(str(center_lon + index * 0.001)),
                rock_type="sandstone",
                period="cretaceous",
                data_source=DATA_SOURCE_FIELD,
            )
        )
        if index < 3:
            session.add(
                UserSite(
                    user_id=user.id,
                    site_id=site_id,
                    role=USER_SITE_ROLE_EXHAUSTER,
                    timestamp=datetime.now(timezone.utc),
                )
            )
    session.commit()


    # 2 non-exhausted + 3 exhausted → need 3 more to reach min of 5
    result = ensure_field_sites_nearby(
        session,
        lat=center_lat,
        lon=center_lon,
        config=FieldSiteLazyConfig(
            min_sites_in_radius=5,
            radius_km=1.0,
            min_separation_km=0.05,
            max_coordinate_attempts=50,
        ),
        rng=random.Random(3),
        coordinate_sampler=_test_coordinate_sampler(center_lat, center_lon, radius_km=1.0),
    )

    assert result.generated == 3
    assert result.total_in_radius == 5
    new_sites = list(
        session.exec(
            select(Site).where(col(Site.site_id) >= FIELD_SITE_ID_START + 5)
        ).all()
    )
    assert len(new_sites) == 3
    assert all(row.status == SITE_STATUS_HIDDEN for row in result.items if row.site.site_id >= FIELD_SITE_ID_START + 5)


def test_load_existing_field_coords_skips_exhausted(session: Session):
    from datetime import datetime, timezone

    from app.services.site_service.field_generate import _load_existing_field_coords

    center_lat, center_lon = 40.0, -100.0
    user = User(username="coord_user", email="coord@example.com", password="x")
    session.add(user)
    session.add(
        Site(
            site_id=FIELD_SITE_ID_START,
            latitude=Decimal(str(center_lat)),
            longitude=Decimal(str(center_lon)),
            rock_type="sandstone",
            period="cretaceous",
            data_source=DATA_SOURCE_FIELD,
        )
    )
    session.add(
        Site(
            site_id=FIELD_SITE_ID_START + 1,
            latitude=Decimal(str(center_lat + 0.001)),
            longitude=Decimal(str(center_lon + 0.001)),
            rock_type="sandstone",
            period="cretaceous",
            data_source=DATA_SOURCE_FIELD,
        )
    )
    session.commit()
    session.refresh(user)
    session.add(
        UserSite(
            user_id=user.id,
            site_id=FIELD_SITE_ID_START,
            role=USER_SITE_ROLE_EXHAUSTER,
            timestamp=datetime.now(timezone.utc),
        )
    )
    session.commit()

    coords = _load_existing_field_coords(
        session,
        lat=center_lat,
        lon=center_lon,
        radius_km=1.0,
    )
    assert len(coords) == 1
    assert abs(coords[0][0] - (center_lat + 0.001)) < 1e-6


def test_ensure_does_not_delete_archive_sites(session: Session, monkeypatch):
    session.add(_site_type(period="cretaceous", rock_type="sandstone"))
    session.add(_archive_site(site_id=100, lat=40.0, lon=-100.0))
    session.commit()


    center_lat, center_lon = 40.0, -100.0
    ensure_field_sites_nearby(
        session,
        lat=center_lat,
        lon=center_lon,
        config=FieldSiteLazyConfig(min_sites_in_radius=2, radius_km=1.0, min_separation_km=0.05),
        rng=random.Random(3),
        coordinate_sampler=_test_coordinate_sampler(center_lat, center_lon, radius_km=1.0),
    )

    archive_sites = list(session.exec(select(Site).where(Site.data_source == DATA_SOURCE_ARCHIVE)).all())
    assert len(archive_sites) == 1


def test_sites_nearby_api_is_read_only(client, session: Session, monkeypatch):
    site_type = _site_type(period="cretaceous", rock_type="sandstone")
    session.add(site_type)
    session.add(_archive_site(site_id=100, lat=40.0, lon=-100.0))
    session.commit()

    monkeypatch.setattr(
        "app.services.site_service.field_generate.build_coordinate_sampler",
        lambda **kwargs: _test_coordinate_sampler(40.0, -100.0, radius_km=1.0),
    )

    response = client.get(
        "/api/v1/sites/nearby",
        params={"lat": 40.0, "lon": -100.0, "radius_km": 1.0, "data_source": "field"},
    )
    assert response.status_code == 200
    payload = response.json()
    assert payload["generated"] == 0
    assert payload["total"] == 0

    field_sites = list(session.exec(select(Site).where(Site.data_source == DATA_SOURCE_FIELD)).all())
    assert len(field_sites) == 0


def test_field_ensure_api_enqueues_job(client, session: Session):
    site_type = _site_type(period="cretaceous", rock_type="sandstone")
    session.add(site_type)
    session.add(_archive_site(site_id=100, lat=40.0, lon=-100.0))
    session.commit()

    response = client.post(
        "/api/v1/sites/field/ensure",
        json={
            "lat": 40.0,
            "lon": -100.0,
            "radius_km": 1.0,
            "reason": "resume",
        },
    )
    assert response.status_code == 202
    payload = response.json()
    assert payload["accepted"] is True
    assert payload["job_id"] is not None
    assert payload["missing"] is None
    assert payload["existing_in_radius"] is None

    jobs = list(session.exec(select(FieldEnsureJob)).all())
    assert len(jobs) == 1
    assert jobs[0].status == "pending"
    assert jobs[0].cell_key == "40.0:-100.0:1.0"
    assert jobs[0].id == payload["job_id"]

    duplicate = client.post(
        "/api/v1/sites/field/ensure",
        json={"lat": 40.0, "lon": -100.0, "radius_km": 1.0},
    )
    assert duplicate.status_code == 202
    assert duplicate.json()["accepted"] is False
    assert duplicate.json()["job_id"] == payload["job_id"]
    assert len(list(session.exec(select(FieldEnsureJob)).all())) == 1


def test_field_ensure_api_enqueues_even_when_full(
    client, session: Session, caplog
):
    import logging

    from app.services.site_service.field_site_logging import logger as field_site_logger

    field_site_logger.propagate = True
    site_type = _site_type(period="cretaceous", rock_type="sandstone")
    session.add(site_type)
    session.commit()
    session.refresh(site_type)

    center_lat, center_lon = 40.0, -100.0
    for index in range(100):
        session.add(
            Site(
                site_id=FIELD_SITE_ID_START + index,
                latitude=Decimal(str(center_lat + index * 0.00001)),
                longitude=Decimal(str(center_lon + index * 0.00001)),
                rock_type="sandstone",
                period="cretaceous",
                site_type_id=site_type.id,
                data_source=DATA_SOURCE_FIELD,
            )
        )
    session.commit()

    caplog.set_level(logging.INFO, logger="field_site_generate")
    response = client.post(
        "/api/v1/sites/field/ensure",
        json={
            "lat": center_lat,
            "lon": center_lon,
            "radius_km": 1.0,
            "reason": "move_500m",
        },
    )
    assert response.status_code == 202
    payload = response.json()
    assert payload["missing"] is None
    assert payload["accepted"] is True
    assert any(
        "action=ensure_enqueued" in record.message
        and "service=api" in record.message
        and "reason=move_500m" in record.message
        and "enqueued=True" in record.message
        for record in caplog.records
    )
    jobs = list(session.exec(select(FieldEnsureJob)).all())
    assert len(jobs) == 1
    assert jobs[0].status == "pending"


def test_field_ensure_worker_noops_when_full(client, session: Session, monkeypatch):
    site_type = _site_type(period="cretaceous", rock_type="sandstone")
    session.add(site_type)
    session.add(_archive_site(site_id=100, lat=40.0, lon=-100.0))
    session.commit()
    session.refresh(site_type)

    center_lat, center_lon = 40.0, -100.0
    for index in range(100):
        session.add(
            Site(
                site_id=FIELD_SITE_ID_START + index,
                latitude=Decimal(str(center_lat + index * 0.00001)),
                longitude=Decimal(str(center_lon + index * 0.00001)),
                rock_type="sandstone",
                period="cretaceous",
                site_type_id=site_type.id,
                data_source=DATA_SOURCE_FIELD,
            )
        )
    session.commit()

    monkeypatch.setattr(
        "app.services.site_service.field_generate.build_coordinate_sampler",
        lambda **kwargs: _test_coordinate_sampler(center_lat, center_lon, radius_km=1.0),
    )

    response = client.post(
        "/api/v1/sites/field/ensure",
        json={"lat": center_lat, "lon": center_lon, "radius_km": 1.0},
    )
    assert response.status_code == 202

    from app.workers.field_ensure_worker import process_one_job

    assert process_one_job(worker_id="test-worker") is True

    field_sites = list(session.exec(select(Site).where(Site.data_source == DATA_SOURCE_FIELD)).all())
    assert len(field_sites) == 100

    job = session.exec(select(FieldEnsureJob)).first()
    assert job is not None
    assert job.status == "done"
    assert job.generated_count == 0
    assert job.total_in_radius == 100

    status = client.get(f"/api/v1/sites/field/ensure/jobs/{job.id}")
    assert status.status_code == 200
    body = status.json()
    assert body["status"] == "done"
    assert body["generated"] == 0
    assert body["total_in_radius"] == 100


def test_field_ensure_worker_processes_job(client, session: Session, monkeypatch):
    site_type = _site_type(period="cretaceous", rock_type="sandstone")
    session.add(site_type)
    session.add(_archive_site(site_id=100, lat=40.0, lon=-100.0))
    session.commit()

    monkeypatch.setattr(
        "app.services.site_service.field_generate.build_coordinate_sampler",
        lambda **kwargs: _test_coordinate_sampler(40.0, -100.0, radius_km=1.0),
    )

    response = client.post(
        "/api/v1/sites/field/ensure",
        json={"lat": 40.0, "lon": -100.0, "radius_km": 1.0},
    )
    assert response.status_code == 202

    from app.workers.field_ensure_worker import process_one_job

    assert process_one_job(worker_id="test-worker") is True

    field_sites = list(session.exec(select(Site).where(Site.data_source == DATA_SOURCE_FIELD)).all())
    assert len(field_sites) == 100

    job = session.exec(select(FieldEnsureJob)).first()
    assert job is not None
    assert job.status == "done"
    assert job.generated_count == 100
    assert job.total_in_radius == 100


def test_next_field_site_id_reads_postgresql_nextval_row(session: Session, monkeypatch):
    from types import SimpleNamespace

    monkeypatch.setattr(
        "app.services.site_service.field_generate.engine",
        SimpleNamespace(dialect=SimpleNamespace(name="postgresql")),
    )

    class _SeqResult:
        def __init__(self, value):
            self._value = value

        def one(self):
            return (self._value,)

    def fake_exec(stmt):
        sql = str(stmt)
        if "nextval" not in sql:
            raise AssertionError(f"unexpected sql: {sql}")
        return _SeqResult(FIELD_SITE_ID_START + 7)

    monkeypatch.setattr(session, "exec", fake_exec)

    assert _next_field_site_id(session) == FIELD_SITE_ID_START + 7


def test_ensure_uses_fresh_ids_after_existing_field_site(
    session: Session, monkeypatch
):
    site_type = _site_type(period="cretaceous", rock_type="sandstone")
    session.add(site_type)
    session.add(_archive_site(site_id=100, lat=40.0, lon=-100.0))
    session.add(
        Site(
            site_id=FIELD_SITE_ID_START + 1,
            latitude=Decimal("40.0001"),
            longitude=Decimal("-100.0001"),
            rock_type="sandstone",
            period="cretaceous",
            site_type_id=site_type.id,
            data_source=DATA_SOURCE_FIELD,
        )
    )
    session.commit()
    session.refresh(site_type)

    assigned: list[int] = []

    class _FakeAllocator:
        def next_id(self):
            assigned.append(FIELD_SITE_ID_START + 2 + len(assigned))
            return assigned[-1]

    monkeypatch.setattr(
        "app.services.site_service.field_generate._FieldSiteIdAllocator",
        lambda session: _FakeAllocator(),
    )
    monkeypatch.setattr(
        "app.services.site_service.field_generate.build_coordinate_sampler",
        lambda **kwargs: _test_coordinate_sampler(40.0, -100.0, radius_km=1.0),
    )

    result = ensure_field_sites_nearby(
        session,
        lat=40.0,
        lon=-100.0,
        config=FieldSiteLazyConfig(min_sites_in_radius=3, radius_km=1.0),
    )

    assert result.generated == 2
    assert assigned == [FIELD_SITE_ID_START + 2, FIELD_SITE_ID_START + 3]
    assert len(assigned) == len(set(assigned))


@pytest.mark.slow
def test_ensure_generates_100_sites_within_time_budget(session: Session, monkeypatch):
    session.add(_site_type(period="cretaceous", rock_type="sandstone"))
    session.add(_archive_site(site_id=100, lat=40.0, lon=-100.0))
    session.commit()


    center_lat, center_lon = 40.0, -100.0
    mask = _test_coordinate_sampler(center_lat, center_lon, radius_km=1.0)
    config = FieldSiteLazyConfig(
        min_sites_in_radius=100,
        radius_km=1.0,
        min_separation_km=0.01,
        max_coordinate_attempts=200,
    )

    started = time.monotonic()
    result = ensure_field_sites_nearby(
        session,
        lat=center_lat,
        lon=center_lon,
        config=config,
        rng=random.Random(42),
        coordinate_sampler=mask,
    )
    elapsed_s = time.monotonic() - started

    assert result.generated == 100
    assert result.total_in_radius == 100
    assert elapsed_s < 30.0, (
        f"expected 100-site batch within 30s, got {elapsed_s:.1f}s "
        f"(skipped_coords={result.skipped_coords})"
    )
