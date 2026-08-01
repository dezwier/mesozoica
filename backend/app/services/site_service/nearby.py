"""Spatial queries for sites within a radius of a point."""

from __future__ import annotations

import math

from sqlalchemy import text
from sqlalchemy.orm import aliased
from sqlmodel import Session, col, select

from app.models.site import Site
from app.models.site_type import SiteType
from app.models.user_site import UserSite
from app.services.data_source_filter import normalize_data_source
from app.services.site_common.geo_utils import haversine_km
from app.services.site_service.list import _row_from_tuple
from app.services.site_service.status_join import (
    latest_user_site_join_condition,
    latest_user_site_subquery,
)
from app.services.site_service.summary import SiteRow

_LatestUserSite = aliased(UserSite)


def _bbox(lat: float, lon: float, radius_km: float) -> tuple[float, float, float, float]:
    lat_radius = radius_km / 111.0
    cos_lat = max(abs(math.cos(math.radians(lat))), 1e-6)
    lon_radius = radius_km / (111.0 * cos_lat)
    return lat - lat_radius, lat + lat_radius, lon - lon_radius, lon + lon_radius


_HAVERSINE_COUNT_SQL = text(
    """
    SELECT COUNT(*)
    FROM site
    WHERE data_source = :data_source
      AND latitude IS NOT NULL
      AND longitude IS NOT NULL
      AND latitude >= :min_lat
      AND latitude <= :max_lat
      AND longitude >= :min_lon
      AND longitude <= :max_lon
      AND (
        6371.0 * 2 * ATAN2(
          SQRT(
            POWER(SIN(RADIANS(latitude - :lat) / 2), 2)
            + COS(RADIANS(:lat)) * COS(RADIANS(latitude))
            * POWER(SIN(RADIANS(longitude - :lon) / 2), 2)
          ),
          SQRT(
            1 - (
              POWER(SIN(RADIANS(latitude - :lat) / 2), 2)
              + COS(RADIANS(:lat)) * COS(RADIANS(latitude))
              * POWER(SIN(RADIANS(longitude - :lon) / 2), 2)
            )
          )
        )
      ) <= :radius_km
      AND NOT EXISTS (
        SELECT 1
        FROM user_site us
        WHERE us.site_id = site.site_id
          AND us.role = :exhauster_role
          AND us.timestamp = (
            SELECT MAX(us2.timestamp)
            FROM user_site us2
            WHERE us2.site_id = site.site_id
          )
      )
    """
)


def list_sites_in_radius(
    session: Session,
    *,
    lat: float,
    lon: float,
    radius_km: float,
    data_source: str,
    limit: int = 500,
    linked_user_id: int | None = None,
    show_all: bool = False,
) -> list[SiteRow]:
    from app.models.data_source import DATA_SOURCE_FIELD

    normalized_data_source = normalize_data_source(data_source)
    min_lat, max_lat, min_lon, max_lon = _bbox(lat, lon, radius_km)
    max_ts = latest_user_site_subquery()
    stmt = (
        select(Site, SiteType, _LatestUserSite)
        .outerjoin(SiteType, col(Site.site_type_id) == col(SiteType.id))
        .outerjoin(max_ts, col(Site.site_id) == max_ts.c.site_id)
        .outerjoin(
            _LatestUserSite,
            latest_user_site_join_condition(_LatestUserSite, max_ts),
        )
        .where(
            col(Site.data_source) == normalized_data_source,
            col(Site.latitude).is_not(None),
            col(Site.longitude).is_not(None),
            col(Site.latitude) >= min_lat,
            col(Site.latitude) <= max_lat,
            col(Site.longitude) >= min_lon,
            col(Site.longitude) <= max_lon,
        )
    )
    if (
        normalized_data_source == DATA_SOURCE_FIELD
        and not show_all
        and linked_user_id is not None
    ):
        linked_sites = (
            select(col(UserSite.site_id))
            .where(col(UserSite.user_id) == linked_user_id)
            .distinct()
        )
        stmt = stmt.where(col(Site.site_id).in_(linked_sites))
    elif (
        normalized_data_source == DATA_SOURCE_FIELD
        and not show_all
        and linked_user_id is None
    ):
        stmt = stmt.where(col(Site.site_id).is_(None))

    rows = session.exec(stmt).all()

    nearby: list[SiteRow] = []
    for row in rows:
        site = row[0]
        distance = haversine_km(lat, lon, float(site.latitude), float(site.longitude))
        if distance <= radius_km:
            nearby.append(_row_from_tuple(row))
            if len(nearby) >= limit:
                break
    return nearby


def list_discoverable_sites_in_radius(
    session: Session,
    *,
    lat: float,
    lon: float,
    radius_km: float,
    user_id: int,
    limit: int = 500,
) -> list[SiteRow]:
    """Field sites within radius that this user has not linked and can still discover.

    Includes globally ``hidden`` sites and sites already ``discovered`` by others.
    """
    from app.models.data_source import DATA_SOURCE_FIELD
    from app.models.user_site import (
        SITE_STATUS_DISCOVERED,
        SITE_STATUS_HIDDEN,
        USER_SITE_ROLE_DISCOVERER,
        role_to_status,
    )

    min_lat, max_lat, min_lon, max_lon = _bbox(lat, lon, radius_km)
    max_ts = latest_user_site_subquery()
    linked_sites = (
        select(col(UserSite.site_id))
        .where(col(UserSite.user_id) == user_id)
        .distinct()
    )
    stmt = (
        select(Site, SiteType, _LatestUserSite)
        .outerjoin(SiteType, col(Site.site_type_id) == col(SiteType.id))
        .outerjoin(max_ts, col(Site.site_id) == max_ts.c.site_id)
        .outerjoin(
            _LatestUserSite,
            latest_user_site_join_condition(_LatestUserSite, max_ts),
        )
        .where(
            col(Site.data_source) == DATA_SOURCE_FIELD,
            col(Site.latitude).is_not(None),
            col(Site.longitude).is_not(None),
            col(Site.latitude) >= min_lat,
            col(Site.latitude) <= max_lat,
            col(Site.longitude) >= min_lon,
            col(Site.longitude) <= max_lon,
            ~col(Site.site_id).in_(linked_sites),
        )
    )
    rows = session.exec(stmt).all()

    nearby: list[SiteRow] = []
    for row in rows:
        site = row[0]
        latest = row[2]
        status = role_to_status(latest.role if latest is not None else None)
        if status not in (SITE_STATUS_HIDDEN, SITE_STATUS_DISCOVERED):
            continue
        # Discoverable when no latest role (hidden) or latest is discoverer.
        if latest is not None and latest.role != USER_SITE_ROLE_DISCOVERER:
            continue
        distance = haversine_km(lat, lon, float(site.latitude), float(site.longitude))
        if distance <= radius_km:
            nearby.append(_row_from_tuple(row))
            if len(nearby) >= limit:
                break
    return nearby


def count_sites_in_radius(
    session: Session,
    *,
    lat: float,
    lon: float,
    radius_km: float,
    data_source: str,
) -> int:
    """Count field/archive sites in radius, excluding latest-role ``exhauster``."""
    from app.models.user_site import USER_SITE_ROLE_EXHAUSTER

    normalized_data_source = normalize_data_source(data_source)
    min_lat, max_lat, min_lon, max_lon = _bbox(lat, lon, radius_km)
    row = session.exec(
        _HAVERSINE_COUNT_SQL.bindparams(
            data_source=normalized_data_source,
            lat=lat,
            lon=lon,
            radius_km=radius_km,
            min_lat=min_lat,
            max_lat=max_lat,
            min_lon=min_lon,
            max_lon=max_lon,
            exhauster_role=USER_SITE_ROLE_EXHAUSTER,
        )
    ).one()
    return int(row[0])


_BBOX_COUNT_SQL = text(
    """
    SELECT COUNT(*)
    FROM site
    WHERE data_source = :data_source
      AND latitude IS NOT NULL
      AND longitude IS NOT NULL
      AND latitude >= :min_lat
      AND latitude < :max_lat
      AND longitude >= :min_lon
      AND longitude < :max_lon
      AND NOT EXISTS (
        SELECT 1
        FROM user_site us
        WHERE us.site_id = site.site_id
          AND us.role = :exhauster_role
          AND us.timestamp = (
            SELECT MAX(us2.timestamp)
            FROM user_site us2
            WHERE us2.site_id = site.site_id
          )
      )
    """
)


def count_sites_in_bbox(
    session: Session,
    *,
    south: float,
    north: float,
    west: float,
    east: float,
    data_source: str,
) -> int:
    """Count non-exhausted sites inside an axis-aligned lat/lon square [south,north)×[west,east)."""
    from app.models.user_site import USER_SITE_ROLE_EXHAUSTER

    normalized_data_source = normalize_data_source(data_source)
    row = session.exec(
        _BBOX_COUNT_SQL.bindparams(
            data_source=normalized_data_source,
            min_lat=min(south, north),
            max_lat=max(south, north),
            min_lon=min(west, east),
            max_lon=max(west, east),
            exhauster_role=USER_SITE_ROLE_EXHAUSTER,
        )
    ).one()
    return int(row[0])


def list_sites_in_cell(
    session: Session,
    *,
    ix: int,
    iy: int,
    cell_size_m: float,
    data_source: str,
    limit: int = 500,
    show_all: bool = True,
) -> list[SiteRow]:
    """List sites inside the meter-space density cell ``(ix, iy)``.

    Lat/lon bbox is only a prefilter — lon edges curve under the projection, so
    every candidate is filtered with ``cell_indices``.
    """
    from app.services.site_common.survey_grid import cell_indices, cell_latlon_bbox

    south, north, west, east = cell_latlon_bbox(
        ix, iy, cell_size_m=cell_size_m, pad_m=2.0
    )
    candidates = list_sites_in_bbox(
        session,
        south=south,
        north=north,
        west=west,
        east=east,
        data_source=data_source,
        show_all=show_all,
        limit=max(limit * 4, 500),
    )
    items: list[SiteRow] = []
    for row in candidates:
        site = row.site
        if site.latitude is None or site.longitude is None:
            continue
        if cell_indices(
            float(site.latitude), float(site.longitude), cell_size_m=cell_size_m
        ) != (ix, iy):
            continue
        items.append(row)
        if len(items) >= limit:
            break
    return items


def count_sites_in_cell(
    session: Session,
    *,
    ix: int,
    iy: int,
    cell_size_m: float,
    data_source: str,
) -> int:
    """Count non-exhausted sites inside the meter-space density cell ``(ix, iy)``."""
    from app.models.user_site import SITE_STATUS_EXHAUSTED

    items = list_sites_in_cell(
        session,
        ix=ix,
        iy=iy,
        cell_size_m=cell_size_m,
        data_source=data_source,
        show_all=True,
        limit=10_000,
    )
    return sum(1 for row in items if row.status != SITE_STATUS_EXHAUSTED)


def list_sites_in_bbox(
    session: Session,
    *,
    south: float,
    north: float,
    west: float,
    east: float,
    data_source: str,
    limit: int = 500,
    show_all: bool = True,
) -> list[SiteRow]:
    """List sites inside an axis-aligned square (same filters as list_sites_in_radius)."""
    from app.models.data_source import DATA_SOURCE_FIELD

    normalized_data_source = normalize_data_source(data_source)
    min_lat, max_lat = min(south, north), max(south, north)
    min_lon, max_lon = min(west, east), max(west, east)
    max_ts = latest_user_site_subquery()
    stmt = (
        select(Site, SiteType, _LatestUserSite)
        .outerjoin(SiteType, col(Site.site_type_id) == col(SiteType.id))
        .outerjoin(max_ts, col(Site.site_id) == max_ts.c.site_id)
        .outerjoin(
            _LatestUserSite,
            latest_user_site_join_condition(_LatestUserSite, max_ts),
        )
        .where(
            col(Site.data_source) == normalized_data_source,
            col(Site.latitude).is_not(None),
            col(Site.longitude).is_not(None),
            col(Site.latitude) >= min_lat,
            col(Site.latitude) < max_lat,
            col(Site.longitude) >= min_lon,
            col(Site.longitude) < max_lon,
        )
    )
    if normalized_data_source == DATA_SOURCE_FIELD and not show_all:
        stmt = stmt.where(col(Site.site_id).is_(None))

    rows = session.exec(stmt).all()
    items: list[SiteRow] = []
    for row in rows:
        items.append(_row_from_tuple(row))
        if len(items) >= limit:
            break
    return items
