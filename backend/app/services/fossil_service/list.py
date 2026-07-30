"""Query helpers for fossil read APIs."""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from decimal import Decimal
from typing import Literal

from sqlalchemy import func, or_
from sqlmodel import Session, col, func as sqlmodel_func, select

from app.core.exceptions import NotFoundError, ValidationError
from app.models.dinosaur_type import DinosaurType
from app.models.fossil import Fossil
from app.models.site import Site
from app.models.site_type import SiteType
from app.services.data_source_filter import normalize_data_source
from app.services.dinosaur_image_service.sync import CURATED_MEDIA_PATH as DINOSAUR_CURATED_MEDIA_PATH
from app.services.fossil_image_service.sync import CURATED_MEDIA_PATH as FOSSIL_CURATED_MEDIA_PATH
from app.services.site_service.site_type_fallback import effective_site_type

SortOption = Literal["name", "random"]
_MAX_SEED_LEN = 64
MESOZOIC_YOUNGER_MA = 66.0
MESOZOIC_OLDER_MA = 252.0


@dataclass(frozen=True)
class FossilRow:
    fossil: Fossil
    dinosaur_name: str
    dinosaur_main_image_url: str | None
    site: Site | None
    site_type: SiteType | None


def list_fossils(
    session: Session,
    *,
    limit: int = 200,
    offset: int = 0,
    sort: SortOption = "name",
    seed: str | None = None,
    q: str | None = None,
    dino_q: str | None = None,
    fossil_q: str | None = None,
    ma_younger: float | None = None,
    ma_older: float | None = None,
    has_custom_image: bool = False,
    has_custom_fossil_image: bool = False,
    llm_enriched: bool | None = None,
    dinosaur_id: int | None = None,
    data_source: str | None = None,
    viewer_user_id: int | None = None,
    include_hidden: bool = False,
) -> tuple[list[FossilRow], int]:
    """Return paginated fossil rows joined with dinosaur catalog fields."""
    capped_limit = max(1, min(limit, 500))
    capped_offset = max(0, offset)
    normalized_data_source = normalize_data_source(data_source)
    normalized_q, normalized_dino_q, normalized_fossil_q, younger, older, time_filter_active = (
        _normalize_filters(
            q=q,
            dino_q=dino_q,
            fossil_q=fossil_q,
            ma_younger=ma_younger,
            ma_older=ma_older,
        )
    )
    search_active = (
        normalized_q is not None
        or normalized_dino_q is not None
        or normalized_fossil_q is not None
    )
    effective_time_filter = time_filter_active and not search_active
    filtered = _filtered_select(
        normalized_q=normalized_q,
        normalized_dino_q=normalized_dino_q,
        normalized_fossil_q=normalized_fossil_q,
        ma_younger=younger,
        ma_older=older,
        time_filter_active=effective_time_filter,
        has_custom_image=has_custom_image,
        has_custom_fossil_image=has_custom_fossil_image,
        llm_enriched=llm_enriched,
        dinosaur_id=dinosaur_id,
        data_source=normalized_data_source,
    )
    from app.models.data_source import DATA_SOURCE_FIELD
    from app.models.user_fossil import UserFossil

    # Field fossils are collection-gated for all viewers unless an admin
    # explicitly requests include_hidden (site/dino card admin peek).
    # Any user_fossil role links the fossil into the viewer's inventory.
    # Use IN (subquery) instead of JOIN+DISTINCT so Postgres random ORDER BY
    # (md5) remains valid.
    if normalized_data_source == DATA_SOURCE_FIELD and not include_hidden:
        if viewer_user_id is None:
            return [], 0
        linked_fossils = (
            select(col(UserFossil.fossil_id))
            .where(col(UserFossil.user_id) == viewer_user_id)
            .distinct()
        )
        filtered = filtered.where(col(Fossil.id).in_(linked_fossils))

    total = session.exec(
        select(sqlmodel_func.count()).select_from(filtered.subquery())
    ).one()

    if sort == "random":
        normalized_seed = (seed or "").strip()
        if not normalized_seed:
            raise ValidationError("seed is required when sort=random")
        normalized_seed = normalized_seed[:_MAX_SEED_LEN]
        rows = _list_fossils_random(
            session,
            filtered=filtered,
            seed=normalized_seed,
            offset=capped_offset,
            limit=capped_limit,
        )
        return rows, int(total)

    rows = session.exec(
        filtered.order_by(
            func.coalesce(Fossil.identified_name, DinosaurType.name),
            Fossil.id,
        )
        .offset(capped_offset)
        .limit(capped_limit)
    ).all()
    return [_row_from_tuple(row) for row in rows], int(total)


def get_fossil_by_id(
    session: Session,
    fossil_id: int,
    *,
    data_source: str | None = None,
) -> FossilRow:
    normalized_data_source = normalize_data_source(data_source)
    row = session.exec(
        _base_select().where(
            col(Fossil.id) == fossil_id,
            col(Fossil.data_source) == normalized_data_source,
        )
    ).first()
    if row is None:
        raise NotFoundError(f"Fossil {fossil_id} not found")
    return _row_from_tuple(row)


def _normalize_filters(
    *,
    q: str | None,
    dino_q: str | None,
    fossil_q: str | None,
    ma_younger: float | None,
    ma_older: float | None,
) -> tuple[str | None, str | None, str | None, float | None, float | None, bool]:
    normalized_q = (q or "").strip() or None
    normalized_dino_q = (dino_q or "").strip() or None
    normalized_fossil_q = (fossil_q or "").strip() or None

    if ma_younger is None and ma_older is None:
        return normalized_q, normalized_dino_q, normalized_fossil_q, None, None, False

    if ma_younger is None or ma_older is None:
        raise ValidationError("ma_younger and ma_older must both be provided")

    younger = max(MESOZOIC_YOUNGER_MA, min(float(ma_younger), MESOZOIC_OLDER_MA))
    older = max(MESOZOIC_YOUNGER_MA, min(float(ma_older), MESOZOIC_OLDER_MA))
    if younger > older:
        raise ValidationError("ma_younger must be less than or equal to ma_older")

    time_filter_active = not (
        younger <= MESOZOIC_YOUNGER_MA and older >= MESOZOIC_OLDER_MA
    )
    return normalized_q, normalized_dino_q, normalized_fossil_q, younger, older, time_filter_active


def _filtered_select(
    *,
    normalized_q: str | None,
    normalized_dino_q: str | None,
    normalized_fossil_q: str | None,
    ma_younger: float | None,
    ma_older: float | None,
    time_filter_active: bool,
    has_custom_image: bool,
    has_custom_fossil_image: bool,
    llm_enriched: bool | None,
    dinosaur_id: int | None = None,
    data_source: str,
):
    stmt = _base_select().where(col(Fossil.data_source) == data_source)
    if dinosaur_id is not None:
        stmt = stmt.where(col(Fossil.dinosaur_id) == dinosaur_id)
    if has_custom_image:
        stmt = stmt.where(
            col(DinosaurType.main_image_url).is_not(None),
            col(DinosaurType.main_image_url).contains(DINOSAUR_CURATED_MEDIA_PATH),
        )
    if has_custom_fossil_image:
        stmt = stmt.where(
            col(Fossil.main_image_url).is_not(None),
            col(Fossil.main_image_url).contains(FOSSIL_CURATED_MEDIA_PATH),
        )
    if llm_enriched is not None:
        stmt = stmt.where(col(Fossil.llm_enriched).is_(llm_enriched))
    if normalized_dino_q is not None:
        pattern = f"%{normalized_dino_q}%"
        stmt = stmt.where(col(DinosaurType.name).ilike(pattern))
    if normalized_fossil_q is not None:
        pattern = f"%{normalized_fossil_q}%"
        stmt = stmt.where(col(Fossil.identified_name).ilike(pattern))
    if normalized_q is not None:
        pattern = f"%{normalized_q}%"
        stmt = stmt.where(
            or_(
                col(Fossil.identified_name).ilike(pattern),
                col(Fossil.geological_formation).ilike(pattern),
                col(Fossil.state).ilike(pattern),
                col(Fossil.collectors).ilike(pattern),
                col(DinosaurType.name).ilike(pattern),
            )
        )
    if time_filter_active:
        assert ma_younger is not None and ma_older is not None
        stmt = stmt.where(
            col(Fossil.min_age_ma).is_not(None),
            col(Fossil.max_age_ma).is_not(None),
            col(Fossil.min_age_ma) <= ma_older,
            col(Fossil.max_age_ma) >= ma_younger,
        )
    return stmt


def _list_fossils_random(
    session: Session,
    *,
    filtered,
    seed: str,
    offset: int,
    limit: int,
) -> list[FossilRow]:
    dialect_name = session.get_bind().dialect.name
    if dialect_name == "postgresql":
        order = func.md5(func.concat(Fossil.id, seed))
        rows = session.exec(
            filtered.order_by(order).offset(offset).limit(limit)
        ).all()
        return [_row_from_tuple(row) for row in rows]

    all_rows = session.exec(filtered).all()
    all_rows.sort(
        key=lambda row: hashlib.md5(f"{row[0].id}{seed}".encode()).hexdigest()
    )
    return [_row_from_tuple(row) for row in all_rows[offset : offset + limit]]


def _row_from_tuple(row: tuple) -> FossilRow:
    fossil, dinosaur_name, dinosaur_main_image_url, site, site_type = row
    return FossilRow(
        fossil=fossil,
        dinosaur_name=dinosaur_name,
        dinosaur_main_image_url=dinosaur_main_image_url,
        site=site,
        site_type=site_type,
    )


def _base_select():
    return (
        select(
            Fossil,
            DinosaurType.name,
            DinosaurType.main_image_url,
            Site,
            SiteType,
        )
        .join(DinosaurType, col(Fossil.dinosaur_id) == col(DinosaurType.id))
        .outerjoin(Site, col(Site.site_id) == col(Fossil.site_id))
        .outerjoin(SiteType, col(Site.site_type_id) == col(SiteType.id))
    )


def _fossil_site_id(row: FossilRow) -> int | None:
    return row.fossil.site_id


def _fossil_site_main_image_url(
    row: FossilRow,
    *,
    types_by_period: dict[str, list[SiteType]] | None,
) -> str | None:
    if row.site is None:
        return None
    effective = (
        effective_site_type(row.site, row.site_type, types_by_period)
        if types_by_period is not None
        else row.site_type
    )
    if effective is None:
        return None
    from app.services.curated_image_service.resolve import resolve_site_type_card_image_url
    from app.services.curated_image_service.versions import ORIGINAL_VERSION

    return resolve_site_type_card_image_url(
        period=effective.period,
        rock_type=effective.rock_type,
        version=row.site.version or ORIGINAL_VERSION,
        fallback_url=effective.main_image_url,
    )


def fossil_row_to_summary(
    row: FossilRow,
    *,
    types_by_period: dict[str, list[SiteType]] | None = None,
    viewer_user_id: int | None = None,
    session: Session | None = None,
):
    """Build API schema from a joined fossil row."""
    from app.models.user_fossil import (
        FOSSIL_STATUS_DISCOVERED,
        FOSSIL_STATUS_HIDDEN,
        USER_FOSSIL_ROLE_IN_SITU,
        UserFossil,
        role_to_status,
    )
    from app.schemas.fossil import FossilSummary

    fossil = row.fossil
    payload = {
        name: _fossil_field_value(fossil, name) for name in Fossil.model_fields
    }
    from app.services.curated_image_service.resolve import resolve_fossil_card_image_url
    from app.services.curated_image_service.versions import ORIGINAL_VERSION

    payload["main_image_url"] = resolve_fossil_card_image_url(
        fossil_id=int(fossil.id),
        version=fossil.version or ORIGINAL_VERSION,
        fallback_url=fossil.main_image_url,
    )
    payload["dinosaur_name"] = row.dinosaur_name
    payload["dinosaur_main_image_url"] = row.dinosaur_main_image_url
    payload["site_id"] = _fossil_site_id(row)
    payload["site_main_image_url"] = _fossil_site_main_image_url(
        row,
        types_by_period=types_by_period,
    )
    status = FOSSIL_STATUS_HIDDEN
    discovered_at = None
    if fossil.data_source != "field":
        # Archive fossils are not discovery-gated.
        status = FOSSIL_STATUS_DISCOVERED
    elif viewer_user_id is not None and session is not None:
        links = list(
            session.exec(
                select(UserFossil)
                .where(
                    col(UserFossil.user_id) == viewer_user_id,
                    col(UserFossil.fossil_id) == fossil.id,
                )
                .order_by(col(UserFossil.timestamp).desc())
            ).all()
        )
        if links:
            status = role_to_status(links[0].role)
            for link in links:
                if link.role == USER_FOSSIL_ROLE_IN_SITU:
                    discovered_at = link.timestamp
                    break
    payload["status"] = status
    payload["discovered_at"] = discovered_at
    payload["version"] = fossil.version or ORIGINAL_VERSION
    return FossilSummary.model_validate(payload)


def _fossil_field_value(fossil: Fossil, name: str):
    value = getattr(fossil, name)
    if isinstance(value, Decimal):
        return float(value)
    return value


def _decimal_to_float(value: Decimal | float | int | None) -> float | None:
    if value is None:
        return None
    return float(value)
