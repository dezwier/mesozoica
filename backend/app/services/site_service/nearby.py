"""Spatial queries for sites within a radius of a point."""

from __future__ import annotations

import math

from sqlalchemy import text
from sqlmodel import Session, col, select

from app.models.site import Site
from app.models.site_type import SiteType
from app.services.data_source_filter import normalize_data_source
from app.services.site_service.geo_utils import haversine_km
from app.services.site_service.list import _row_from_tuple
from app.services.site_service.summary import SiteRow


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
) -> list[SiteRow]:
    normalized_data_source = normalize_data_source(data_source)
    min_lat, max_lat, min_lon, max_lon = _bbox(lat, lon, radius_km)
    rows = session.exec(
        select(Site, SiteType)
        .outerjoin(SiteType, col(Site.site_type_id) == col(SiteType.id))
        .where(
            col(Site.data_source) == normalized_data_source,
            col(Site.latitude).is_not(None),
            col(Site.longitude).is_not(None),
            col(Site.latitude) >= min_lat,
            col(Site.latitude) <= max_lat,
            col(Site.longitude) >= min_lon,
            col(Site.longitude) <= max_lon,
        )
    ).all()

    nearby: list[SiteRow] = []
    for row in rows:
        site = row[0]
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
        )
    ).one()
    return int(row[0])
