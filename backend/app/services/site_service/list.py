"""Query helpers for site read APIs."""

from __future__ import annotations

import hashlib
from typing import Literal

from sqlalchemy import func, or_
from sqlmodel import Session, col, func as sqlmodel_func, select

from app.core.exceptions import NotFoundError, ValidationError
from app.models.site import Site
from app.models.site_type import SiteType
from app.services.data_source_filter import normalize_data_source
from app.services.site_service.summary import SiteRow
from app.services.site_type_image_service.sync import CURATED_MEDIA_PATH

SortOption = Literal["name", "random"]
_MAX_SEED_LEN = 64
MESOZOIC_YOUNGER_MA = 66.0
MESOZOIC_OLDER_MA = 252.0


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
) -> tuple[list[SiteRow], int]:
    """Return paginated site rows joined with site_type."""
    capped_limit = max(1, min(limit, 500))
    capped_offset = max(0, offset)
    normalized_data_source = normalize_data_source(data_source)
    normalized_q, younger, older, time_filter_active = _normalize_filters(
        q=q,
        ma_younger=ma_younger,
        ma_older=ma_older,
    )
    effective_time_filter = time_filter_active and normalized_q is None
    filtered = _filtered_select(
        normalized_q=normalized_q,
        ma_younger=younger,
        ma_older=older,
        time_filter_active=effective_time_filter,
        has_custom_image=has_custom_image,
        data_source=normalized_data_source,
    )

    total = session.exec(
        select(sqlmodel_func.count()).select_from(filtered.subquery())
    ).one()

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
        return rows, int(total)

    rows = session.exec(
        filtered.order_by(
            func.coalesce(Site.formation, ""),
            Site.site_id,
        )
        .offset(capped_offset)
        .limit(capped_limit)
    ).all()
    return [_row_from_tuple(row) for row in rows], int(total)


def get_site_by_id(
    session: Session,
    site_id: int,
    *,
    data_source: str | None = None,
) -> SiteRow:
    normalized_data_source = normalize_data_source(data_source)
    row = session.exec(
        select(Site, SiteType)
        .outerjoin(SiteType, col(Site.site_type_id) == col(SiteType.id))
        .where(
            col(Site.site_id) == site_id,
            col(Site.data_source) == normalized_data_source,
        )
    ).first()
    if row is None:
        raise NotFoundError(f"Site {site_id} not found")
    return _row_from_tuple(row)


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


def _filtered_select(
    *,
    normalized_q: str | None,
    ma_younger: float | None,
    ma_older: float | None,
    time_filter_active: bool,
    has_custom_image: bool,
    data_source: str,
):
    stmt = select(Site, SiteType).outerjoin(
        SiteType, col(Site.site_type_id) == col(SiteType.id)
    ).where(col(Site.data_source) == data_source)
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
        rows = session.exec(
            filtered.order_by(order).offset(offset).limit(limit)
        ).all()
        return [_row_from_tuple(row) for row in rows]

    all_rows = session.exec(filtered).all()
    all_rows.sort(
        key=lambda row: hashlib.md5(
            f"{row[0].site_id}{seed}".encode()
        ).hexdigest()
    )
    return [_row_from_tuple(row) for row in all_rows[offset : offset + limit]]


def _row_from_tuple(row: tuple) -> SiteRow:
    site, site_type = row
    return SiteRow(site=site, site_type=site_type)
