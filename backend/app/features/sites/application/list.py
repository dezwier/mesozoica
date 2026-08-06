"""Query helpers for site read APIs."""

from __future__ import annotations

import hashlib
from datetime import datetime
from typing import Literal

from sqlalchemy import func, or_, text
from sqlalchemy.orm import aliased
from sqlmodel import Session, col, func as sqlmodel_func, select

from app.core.exceptions import NotFoundError, ValidationError
from app.shared.data_sources import DATA_SOURCE_FIELD
from app.models.site import HOW_DISCOVERED_VALUES, Site
from app.models.site_type import SiteType
from app.models.user_site import USER_SITE_ROLE_DISCOVERER, UserSite, role_to_status
from app.shared.data_sources import normalize_data_source
from app.shared.geography.geo_utils import haversine_km
from app.features.sites.application.status_join import (
    latest_user_site_join_condition,
    latest_user_site_subquery,
    latest_user_sites_for_ids,
)
from app.features.sites.application.summary import SiteRow
from app.features.media.public import SITE_TYPE_CURATED_MEDIA_PATH as CURATED_MEDIA_PATH

SortOption = Literal[
    "name",
    "random",
    "distance",
    "discovered_at",
    "discovered_at_desc",
]
_MAX_SEED_LEN = 64
MESOZOIC_YOUNGER_MA = 66.0
MESOZOIC_OLDER_MA = 252.0
# Probe one past Flutter MapConfig.showAllMaxSites so dense viewports fail
# fast without counting the entire bbox.
_SHOW_ALL_COUNT_PROBE = 1001
# Cap admin show-all work so abandoned client requests cannot hold pool
# connections until Railway kills the socket (SSL EOF on session close).
_SHOW_ALL_STATEMENT_TIMEOUT_MS = 8000

_LatestUserSite = aliased(UserSite)


def list_sites(
    session: Session,
    *,
    limit: int = 200,
    offset: int = 0,
    sort: SortOption = "name",
    seed: str | None = None,
    q: str | None = None,
    ma_younger: float | None = None,
    ma_older: float | None = None,
    has_custom_image: bool = False,
    data_source: str | None = None,
    site_id_min: int | None = None,
    linked_user_id: int | None = None,
    show_all: bool = False,
    how_discovered: list[str] | None = None,
    discovered_after: datetime | None = None,
    discovered_before: datetime | None = None,
    lat: float | None = None,
    lon: float | None = None,
    min_lat: float | None = None,
    max_lat: float | None = None,
    min_lon: float | None = None,
    max_lon: float | None = None,
    viewer_user_id: int | None = None,
) -> tuple[list[SiteRow], int]:
    """Return paginated site rows joined with site_type.

    For field sites, pass ``linked_user_id`` to restrict to sites linked via
    ``user_site`` unless ``show_all`` is True.

    Optional ``min_lat``/``max_lat``/``min_lon``/``max_lon`` restrict to a
    bounding box (all four required together).
    """
    capped_limit = max(1, min(limit, 500))
    capped_offset = max(0, offset)
    normalized_data_source = normalize_data_source(data_source)
    normalized_q, younger, older, time_filter_active = _normalize_filters(
        q=q,
        ma_younger=ma_younger,
        ma_older=ma_older,
    )
    effective_time_filter = time_filter_active and normalized_q is None
    how_values = _normalize_how_discovered(how_discovered)
    discovery_viewer_id = _require_discovery_viewer(
        sort=sort,
        discovered_after=discovered_after,
        discovered_before=discovered_before,
        viewer_user_id=viewer_user_id,
    )
    origin_lat, origin_lon = _normalize_distance_origin(
        sort=sort, lat=lat, lon=lon
    )
    bbox = _normalize_bbox(
        min_lat=min_lat,
        max_lat=max_lat,
        min_lon=min_lon,
        max_lon=max_lon,
    )

    filtered = _filtered_select(
        normalized_q=normalized_q,
        ma_younger=younger,
        ma_older=older,
        time_filter_active=effective_time_filter,
        has_custom_image=has_custom_image,
        data_source=normalized_data_source,
        site_id_min=site_id_min,
        linked_user_id=linked_user_id,
        show_all=show_all,
        how_discovered=how_values,
        discovered_after=discovered_after,
        discovered_before=discovered_before,
        discovery_viewer_id=discovery_viewer_id,
        require_coordinates=sort == "distance" or bbox is not None,
        bbox=bbox,
    )

    # Admin show-all viewport: site-only probe (uses spatial index) + short
    # statement timeout so a cancelled Flutter request cannot pin a pool slot.
    if show_all and bbox is not None:
        _set_statement_timeout_ms(session, _SHOW_ALL_STATEMENT_TIMEOUT_MS)
        total = _probe_field_bbox_site_ids(
            session,
            data_source=normalized_data_source,
            bbox=bbox,
            normalized_q=normalized_q,
            ma_younger=younger,
            ma_older=older,
            time_filter_active=effective_time_filter,
            how_discovered=how_values,
            site_id_min=site_id_min,
        )
        if total >= _SHOW_ALL_COUNT_PROBE:
            return [], total
    else:
        filtered_subq = filtered.subquery()
        total = int(
            session.exec(
                select(sqlmodel_func.count()).select_from(filtered_subq)
            ).one()
        )

    if site_id_min is not None:
        if sort != "name":
            raise ValidationError("site_id_min requires sort=name")
        pairs = session.exec(
            filtered.order_by(col(Site.site_id)).limit(capped_limit)
        ).all()
        return _site_rows_from_pairs(session, pairs), total

    if sort == "random":
        normalized_seed = (seed or "").strip()
        if not normalized_seed:
            raise ValidationError("seed is required when sort=random")
        normalized_seed = normalized_seed[:_MAX_SEED_LEN]
        rows = _list_sites_random(
            session,
            filtered=filtered,
            seed=normalized_seed,
            offset=capped_offset,
            limit=capped_limit,
        )
        return rows, total

    if sort == "distance":
        assert origin_lat is not None and origin_lon is not None
        rows = _list_sites_by_distance(
            session,
            filtered=filtered,
            lat=origin_lat,
            lon=origin_lon,
            offset=capped_offset,
            limit=capped_limit,
        )
        return rows, total

    if sort in ("discovered_at", "discovered_at_desc"):
        assert discovery_viewer_id is not None
        rows = _list_sites_by_discovered_at(
            session,
            filtered=filtered,
            viewer_user_id=discovery_viewer_id,
            descending=sort == "discovered_at_desc",
            offset=capped_offset,
            limit=capped_limit,
        )
        return rows, total

    pairs = session.exec(
        filtered.order_by(
            func.coalesce(Site.formation, ""),
            Site.site_id,
        )
        .offset(capped_offset)
        .limit(capped_limit)
    ).all()
    return _site_rows_from_pairs(session, pairs), total


def get_site_by_id(
    session: Session,
    site_id: int,
    *,
    data_source: str | None = None,
    viewer_user_id: int | None = None,
) -> SiteRow:
    normalized_data_source = normalize_data_source(data_source)
    max_ts = latest_user_site_subquery()
    row = session.exec(
        select(Site, SiteType, _LatestUserSite)
        .outerjoin(SiteType, col(Site.site_type_id) == col(SiteType.id))
        .outerjoin(max_ts, col(Site.site_id) == max_ts.c.site_id)
        .outerjoin(
            _LatestUserSite,
            latest_user_site_join_condition(_LatestUserSite, max_ts),
        )
        .where(
            col(Site.site_id) == site_id,
            col(Site.data_source) == normalized_data_source,
        )
    ).first()
    if row is None:
        raise NotFoundError(f"Site {site_id} not found")
    site_row = _row_from_tuple(row)
    if viewer_user_id is not None:
        from app.features.sites.application.summary import enrich_site_rows_for_viewer

        return enrich_site_rows_for_viewer(
            session, [site_row], viewer_user_id=viewer_user_id
        )[0]
    return site_row


def _normalize_filters(
    *,
    q: str | None,
    ma_younger: float | None,
    ma_older: float | None,
) -> tuple[str | None, float | None, float | None, bool]:
    normalized_q = (q or "").strip() or None

    if ma_younger is None and ma_older is None:
        return normalized_q, None, None, False

    if ma_younger is None or ma_older is None:
        raise ValidationError("ma_younger and ma_older must both be provided")

    younger = max(MESOZOIC_YOUNGER_MA, min(float(ma_younger), MESOZOIC_OLDER_MA))
    older = max(MESOZOIC_YOUNGER_MA, min(float(ma_older), MESOZOIC_OLDER_MA))
    if younger > older:
        raise ValidationError("ma_younger must be less than or equal to ma_older")

    time_filter_active = not (
        younger <= MESOZOIC_YOUNGER_MA and older >= MESOZOIC_OLDER_MA
    )
    return normalized_q, younger, older, time_filter_active


def _normalize_how_discovered(values: list[str] | None) -> list[str] | None:
    if not values:
        return None
    normalized: list[str] = []
    for raw in values:
        value = (raw or "").strip().lower()
        if not value:
            continue
        if value not in HOW_DISCOVERED_VALUES:
            raise ValidationError(
                f"how_discovered must be one of: {', '.join(HOW_DISCOVERED_VALUES)}"
            )
        if value not in normalized:
            normalized.append(value)
    if not normalized:
        return None
    # All methods selected ≡ no filter.
    if len(normalized) == len(HOW_DISCOVERED_VALUES):
        return None
    return normalized


def _require_discovery_viewer(
    *,
    sort: SortOption,
    discovered_after: datetime | None,
    discovered_before: datetime | None,
    viewer_user_id: int | None,
) -> int | None:
    needs_viewer = (
        sort in ("discovered_at", "discovered_at_desc")
        or discovered_after is not None
        or discovered_before is not None
    )
    if not needs_viewer:
        return None
    if viewer_user_id is None:
        raise ValidationError(
            "Authentication required for discovery time filter or sort"
        )
    if (
        discovered_after is not None
        and discovered_before is not None
        and discovered_after > discovered_before
    ):
        raise ValidationError(
            "discovered_after must be less than or equal to discovered_before"
        )
    return viewer_user_id


def _normalize_distance_origin(
    *,
    sort: SortOption,
    lat: float | None,
    lon: float | None,
) -> tuple[float | None, float | None]:
    if sort != "distance":
        return None, None
    if lat is None or lon is None:
        raise ValidationError("lat and lon are required when sort=distance")
    if not (-90.0 <= lat <= 90.0 and -180.0 <= lon <= 180.0):
        raise ValidationError("lat/lon out of range")
    return float(lat), float(lon)


def _normalize_bbox(
    *,
    min_lat: float | None,
    max_lat: float | None,
    min_lon: float | None,
    max_lon: float | None,
) -> tuple[float, float, float, float] | None:
    values = (min_lat, max_lat, min_lon, max_lon)
    if all(v is None for v in values):
        return None
    if any(v is None for v in values):
        raise ValidationError(
            "min_lat, max_lat, min_lon, and max_lon must be provided together"
        )
    assert min_lat is not None and max_lat is not None
    assert min_lon is not None and max_lon is not None
    if min_lat > max_lat:
        raise ValidationError("min_lat must be <= max_lat")
    if min_lon > max_lon:
        raise ValidationError("min_lon must be <= max_lon")
    if not (-90.0 <= min_lat <= 90.0 and -90.0 <= max_lat <= 90.0):
        raise ValidationError("latitude bounds must be between -90 and 90")
    if not (-180.0 <= min_lon <= 180.0 and -180.0 <= max_lon <= 180.0):
        raise ValidationError("longitude bounds must be between -180 and 180")
    return min_lat, max_lat, min_lon, max_lon


def _set_statement_timeout_ms(session: Session, timeout_ms: int) -> None:
    """Postgres only — no-op on SQLite test DB."""
    bind = session.get_bind()
    if bind is None or bind.dialect.name != "postgresql":
        return
    session.connection().execute(
        text(f"SET LOCAL statement_timeout = '{int(timeout_ms)}'")
    )


def _probe_field_bbox_site_ids(
    session: Session,
    *,
    data_source: str,
    bbox: tuple[float, float, float, float],
    normalized_q: str | None,
    ma_younger: float | None,
    ma_older: float | None,
    time_filter_active: bool,
    how_discovered: list[str] | None,
    site_id_min: int | None,
) -> int:
    """Cheap site-only id probe for admin show-all (no joins)."""
    box_min_lat, box_max_lat, box_min_lon, box_max_lon = bbox
    stmt = (
        select(col(Site.site_id))
        .where(
            col(Site.data_source) == data_source,
            col(Site.latitude).is_not(None),
            col(Site.longitude).is_not(None),
            col(Site.latitude) >= box_min_lat,
            col(Site.latitude) <= box_max_lat,
            col(Site.longitude) >= box_min_lon,
            col(Site.longitude) <= box_max_lon,
        )
        .limit(_SHOW_ALL_COUNT_PROBE)
    )
    if site_id_min is not None:
        stmt = stmt.where(col(Site.site_id) > site_id_min)
    if how_discovered is not None:
        stmt = stmt.where(col(Site.how_discovered).in_(how_discovered))
    if normalized_q is not None:
        pattern = f"%{normalized_q}%"
        stmt = stmt.where(
            or_(
                col(Site.formation).ilike(pattern),
                col(Site.state).ilike(pattern),
                col(Site.country_code).ilike(pattern),
                col(Site.rock_type).ilike(pattern),
            )
        )
    if time_filter_active:
        assert ma_younger is not None and ma_older is not None
        stmt = stmt.where(
            col(Site.min_age_ma).is_not(None),
            col(Site.max_age_ma).is_not(None),
            col(Site.min_age_ma) <= ma_older,
            col(Site.max_age_ma) >= ma_younger,
        )
    return len(session.exec(stmt).all())


def _filtered_select(
    *,
    normalized_q: str | None,
    ma_younger: float | None,
    ma_older: float | None,
    time_filter_active: bool,
    has_custom_image: bool,
    data_source: str,
    site_id_min: int | None = None,
    linked_user_id: int | None = None,
    show_all: bool = False,
    how_discovered: list[str] | None = None,
    discovered_after: datetime | None = None,
    discovered_before: datetime | None = None,
    discovery_viewer_id: int | None = None,
    require_coordinates: bool = False,
    bbox: tuple[float, float, float, float] | None = None,
):
    # Site + SiteType only. Latest user_site status is loaded for the page of
    # rows after fetch — joining a global user_site aggregation here used to
    # hold pool connections for tens of seconds on dense field tiles.
    stmt = (
        select(Site, SiteType)
        .outerjoin(SiteType, col(Site.site_type_id) == col(SiteType.id))
        .where(col(Site.data_source) == data_source)
    )
    if (
        data_source == DATA_SOURCE_FIELD
        and not show_all
        and linked_user_id is not None
    ):
        linked_sites = (
            select(col(UserSite.site_id))
            .where(col(UserSite.user_id) == linked_user_id)
            .distinct()
        )
        stmt = stmt.where(col(Site.site_id).in_(linked_sites))
    elif data_source == DATA_SOURCE_FIELD and not show_all and linked_user_id is None:
        # Field + linked-only without a user → empty result set.
        stmt = stmt.where(col(Site.site_id).is_(None))
    if site_id_min is not None:
        stmt = stmt.where(col(Site.site_id) > site_id_min)
    if has_custom_image:
        stmt = stmt.where(
            col(SiteType.main_image_url).is_not(None),
            col(SiteType.main_image_url).contains(CURATED_MEDIA_PATH),
        )
    if normalized_q is not None:
        pattern = f"%{normalized_q}%"
        stmt = stmt.where(
            or_(
                col(Site.formation).ilike(pattern),
                col(Site.state).ilike(pattern),
                col(Site.country_code).ilike(pattern),
                col(Site.rock_type).ilike(pattern),
            )
        )
    if time_filter_active:
        assert ma_younger is not None and ma_older is not None
        stmt = stmt.where(
            col(Site.min_age_ma).is_not(None),
            col(Site.max_age_ma).is_not(None),
            col(Site.min_age_ma) <= ma_older,
            col(Site.max_age_ma) >= ma_younger,
        )
    if how_discovered is not None:
        stmt = stmt.where(col(Site.how_discovered).in_(how_discovered))
    if discovery_viewer_id is not None and (
        discovered_after is not None or discovered_before is not None
    ):
        discoverer_sites = select(col(UserSite.site_id)).where(
            col(UserSite.user_id) == discovery_viewer_id,
            col(UserSite.role) == USER_SITE_ROLE_DISCOVERER,
        )
        if discovered_after is not None:
            discoverer_sites = discoverer_sites.where(
                col(UserSite.timestamp) >= discovered_after
            )
        if discovered_before is not None:
            discoverer_sites = discoverer_sites.where(
                col(UserSite.timestamp) <= discovered_before
            )
        stmt = stmt.where(col(Site.site_id).in_(discoverer_sites))
    if require_coordinates:
        stmt = stmt.where(
            col(Site.latitude).is_not(None),
            col(Site.longitude).is_not(None),
        )
    if bbox is not None:
        box_min_lat, box_max_lat, box_min_lon, box_max_lon = bbox
        stmt = stmt.where(
            col(Site.latitude) >= box_min_lat,
            col(Site.latitude) <= box_max_lat,
            col(Site.longitude) >= box_min_lon,
            col(Site.longitude) <= box_max_lon,
        )
    return stmt


def _list_sites_random(
    session: Session,
    *,
    filtered,
    seed: str,
    offset: int,
    limit: int,
) -> list[SiteRow]:
    dialect_name = session.get_bind().dialect.name
    if dialect_name == "postgresql":
        order = func.md5(func.concat(Site.site_id, seed))
        pairs = session.exec(
            filtered.order_by(order).offset(offset).limit(limit)
        ).all()
        return _site_rows_from_pairs(session, pairs)

    all_pairs = session.exec(filtered).all()
    all_pairs.sort(
        key=lambda row: hashlib.md5(
            f"{row[0].site_id}{seed}".encode()
        ).hexdigest()
    )
    return _site_rows_from_pairs(session, all_pairs[offset : offset + limit])


def _list_sites_by_distance(
    session: Session,
    *,
    filtered,
    lat: float,
    lon: float,
    offset: int,
    limit: int,
) -> list[SiteRow]:
    all_pairs = session.exec(filtered).all()

    def distance_key(row: tuple) -> tuple[float, int]:
        site = row[0]
        dist = haversine_km(
            lat, lon, float(site.latitude), float(site.longitude)
        )
        return (dist, int(site.site_id))

    all_pairs.sort(key=distance_key)
    return _site_rows_from_pairs(session, all_pairs[offset : offset + limit])


def _list_sites_by_discovered_at(
    session: Session,
    *,
    filtered,
    viewer_user_id: int,
    descending: bool,
    offset: int,
    limit: int,
) -> list[SiteRow]:
    all_pairs = session.exec(filtered).all()
    site_ids = [int(row[0].site_id) for row in all_pairs]
    timestamps: dict[int, datetime] = {}
    if site_ids:
        links = session.exec(
            select(UserSite).where(
                col(UserSite.user_id) == viewer_user_id,
                col(UserSite.role) == USER_SITE_ROLE_DISCOVERER,
                col(UserSite.site_id).in_(site_ids),
            )
        ).all()
        for link in links:
            timestamps[int(link.site_id)] = link.timestamp

    def sort_key(row: tuple) -> tuple:
        site_id = int(row[0].site_id)
        ts = timestamps.get(site_id)
        missing = ts is None
        if ts is None:
            epoch = 0.0
        else:
            naive = ts.replace(tzinfo=None) if ts.tzinfo else ts
            epoch = naive.timestamp()
        if descending:
            return (1 if missing else 0, -epoch, site_id)
        return (1 if missing else 0, epoch, site_id)

    all_pairs.sort(key=sort_key)
    return _site_rows_from_pairs(session, all_pairs[offset : offset + limit])


def _site_rows_from_pairs(session: Session, pairs: list) -> list[SiteRow]:
    """Attach latest user_site status for a page of (Site, SiteType) rows."""
    site_ids = [int(site.site_id) for site, _site_type in pairs]
    latest_by_id = latest_user_sites_for_ids(session, site_ids)
    rows: list[SiteRow] = []
    for site, site_type in pairs:
        latest = latest_by_id.get(int(site.site_id))
        if latest is not None:
            status_value = role_to_status(latest.role)
        elif site.data_source == DATA_SOURCE_FIELD:
            status_value = role_to_status(None)
        else:
            status_value = None
        rows.append(SiteRow(site=site, site_type=site_type, status=status_value))
    return rows


def _row_from_tuple(row: tuple) -> SiteRow:
    site, site_type, latest_user_site = row[0], row[1], row[2]
    if latest_user_site is not None:
        status_value = role_to_status(latest_user_site.role)
    elif site.data_source == DATA_SOURCE_FIELD:
        status_value = role_to_status(None)
    else:
        status_value = None
    return SiteRow(site=site, site_type=site_type, status=status_value)
