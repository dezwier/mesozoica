"""Query helpers for dinosaur read APIs."""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from datetime import datetime
from typing import Literal

from sqlalchemy import func, or_
from sqlmodel import Session, col, func as sqlmodel_func, select

from app.core.exceptions import NotFoundError, ValidationError
from app.models.dinosaur import Dinosaur
from app.models.dinosaur_type import DinosaurType
from app.models.user_dinosaur import USER_DINOSAUR_ROLE_DISCOVERER, UserDinosaur
from app.services.curated_image_service.resolve import resolve_dinosaur_card_image_url
from app.services.dinosaur_image_service.sync import CURATED_MEDIA_PATH

SortOption = Literal["name", "random"]
ListMode = Literal["catalog", "inventory"]
_MAX_SEED_LEN = 64
MESOZOIC_YOUNGER_MA = 66.0
MESOZOIC_OLDER_MA = 252.0


@dataclass(frozen=True)
class DinosaurListRow:
    dinosaur_type: DinosaurType
    occurrence_id: int | None = None
    created_at: datetime | None = None
    image_version: str | None = None


def list_dinosaurs(
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
    llm_enriched: bool | None = None,
    mode: ListMode = "catalog",
    viewer_user_id: int | None = None,
) -> tuple[list[DinosaurListRow], int]:
    """Return paginated dinosaur rows for catalog or inventory mode."""
    if mode == "inventory":
        return _list_inventory_dinosaurs(
            session,
            limit=limit,
            offset=offset,
            sort=sort,
            seed=seed,
            q=q,
            ma_younger=ma_younger,
            ma_older=ma_older,
            has_custom_image=has_custom_image,
            llm_enriched=llm_enriched,
            viewer_user_id=viewer_user_id,
        )
    return _list_catalog_dinosaurs(
        session,
        limit=limit,
        offset=offset,
        sort=sort,
        seed=seed,
        q=q,
        ma_younger=ma_younger,
        ma_older=ma_older,
        has_custom_image=has_custom_image,
        llm_enriched=llm_enriched,
    )


def _list_catalog_dinosaurs(
    session: Session,
    *,
    limit: int,
    offset: int,
    sort: SortOption,
    seed: str | None,
    q: str | None,
    ma_younger: float | None,
    ma_older: float | None,
    has_custom_image: bool,
    llm_enriched: bool | None,
) -> tuple[list[DinosaurListRow], int]:
    capped_limit = max(1, min(limit, 500))
    capped_offset = max(0, offset)
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
        llm_enriched=llm_enriched,
    )

    total = session.exec(
        select(sqlmodel_func.count()).select_from(filtered.subquery())
    ).one()

    if sort == "random":
        normalized_seed = (seed or "").strip()
        if not normalized_seed:
            raise ValidationError("seed is required when sort=random")
        normalized_seed = normalized_seed[:_MAX_SEED_LEN]
        rows = _list_types_random(
            session,
            filtered=filtered,
            seed=normalized_seed,
            offset=capped_offset,
            limit=capped_limit,
        )
    else:
        rows = list(
            session.exec(
                filtered.order_by(DinosaurType.name)
                .offset(capped_offset)
                .limit(capped_limit)
            ).all()
        )

    from app.services.curated_image_service.versions import ORIGINAL_VERSION

    return [
        DinosaurListRow(dinosaur_type=row, image_version=ORIGINAL_VERSION)
        for row in rows
    ], int(total)


def _list_inventory_dinosaurs(
    session: Session,
    *,
    limit: int,
    offset: int,
    sort: SortOption,
    seed: str | None,
    q: str | None,
    ma_younger: float | None,
    ma_older: float | None,
    has_custom_image: bool,
    llm_enriched: bool | None,
    viewer_user_id: int | None,
) -> tuple[list[DinosaurListRow], int]:
    if viewer_user_id is None:
        return [], 0

    capped_limit = max(1, min(limit, 500))
    capped_offset = max(0, offset)
    normalized_q, younger, older, time_filter_active = _normalize_filters(
        q=q,
        ma_younger=ma_younger,
        ma_older=ma_older,
    )
    effective_time_filter = time_filter_active and normalized_q is None

    stmt = (
        select(Dinosaur, DinosaurType)
        .join(DinosaurType, col(Dinosaur.dinosaur_type_id) == col(DinosaurType.id))
        .join(
            UserDinosaur,
            (col(UserDinosaur.dinosaur_id) == col(Dinosaur.id))
            & (col(UserDinosaur.user_id) == viewer_user_id)
            & (col(UserDinosaur.role) == USER_DINOSAUR_ROLE_DISCOVERER),
        )
    )
    if has_custom_image:
        stmt = stmt.where(
            col(DinosaurType.main_image_url).is_not(None),
            col(DinosaurType.main_image_url).contains(CURATED_MEDIA_PATH),
        )
    if llm_enriched is not None:
        stmt = stmt.where(col(DinosaurType.llm_enriched).is_(llm_enriched))
    if normalized_q is not None:
        pattern = f"%{normalized_q}%"
        stmt = stmt.where(
            or_(
                col(DinosaurType.name).ilike(pattern),
                col(DinosaurType.wikipedia_title).ilike(pattern),
            )
        )
    if effective_time_filter:
        assert younger is not None and older is not None
        stmt = stmt.where(
            col(DinosaurType.birth).is_not(None),
            col(DinosaurType.death).is_not(None),
            col(DinosaurType.death) <= older,
            col(DinosaurType.birth) >= younger,
        )

    total = session.exec(
        select(sqlmodel_func.count()).select_from(stmt.subquery())
    ).one()

    if sort == "random":
        normalized_seed = (seed or "").strip()
        if not normalized_seed:
            raise ValidationError("seed is required when sort=random")
        normalized_seed = normalized_seed[:_MAX_SEED_LEN]
        rows = list(session.exec(stmt).all())
        rows.sort(
            key=lambda row: hashlib.md5(
                f"{row[0].id}{row[1].id}{normalized_seed}".encode()
            ).hexdigest()
        )
        rows = rows[capped_offset : capped_offset + capped_limit]
    else:
        rows = list(
            session.exec(
                stmt.order_by(col(DinosaurType.name), col(Dinosaur.id))
                .offset(capped_offset)
                .limit(capped_limit)
            ).all()
        )

    return [
        DinosaurListRow(
            dinosaur_type=dino_type,
            occurrence_id=int(occurrence.id),
            created_at=occurrence.created_at,
            image_version=occurrence.version,
        )
        for occurrence, dino_type in rows
    ], int(total)


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
    llm_enriched: bool | None,
):
    stmt = select(DinosaurType)
    if has_custom_image:
        stmt = stmt.where(
            col(DinosaurType.main_image_url).is_not(None),
            col(DinosaurType.main_image_url).contains(CURATED_MEDIA_PATH),
        )
    if llm_enriched is not None:
        stmt = stmt.where(col(DinosaurType.llm_enriched).is_(llm_enriched))
    if normalized_q is not None:
        pattern = f"%{normalized_q}%"
        stmt = stmt.where(
            or_(
                col(DinosaurType.name).ilike(pattern),
                col(DinosaurType.wikipedia_title).ilike(pattern),
            )
        )
    if time_filter_active:
        assert ma_younger is not None and ma_older is not None
        stmt = stmt.where(
            col(DinosaurType.birth).is_not(None),
            col(DinosaurType.death).is_not(None),
            col(DinosaurType.death) <= ma_older,
            col(DinosaurType.birth) >= ma_younger,
        )
    return stmt


def _list_types_random(
    session: Session,
    *,
    filtered,
    seed: str,
    offset: int,
    limit: int,
) -> list[DinosaurType]:
    dialect_name = session.get_bind().dialect.name
    if dialect_name == "postgresql":
        order = func.md5(func.concat(DinosaurType.id, seed))
        rows = session.exec(
            filtered.order_by(order).offset(offset).limit(limit)
        ).all()
        return list(rows)

    all_rows = session.exec(filtered).all()
    all_rows.sort(
        key=lambda row: hashlib.md5(f"{row.id}{seed}".encode()).hexdigest()
    )
    return all_rows[offset : offset + limit]


def get_dinosaur_by_id(session: Session, dinosaur_id: int) -> DinosaurType:
    """Fetch a catalog dinosaur type by id (article / detail routes)."""
    row = session.get(DinosaurType, dinosaur_id)
    if row is None:
        raise NotFoundError(f"DinosaurType {dinosaur_id} not found")
    return row


def dinosaur_to_summary(row: DinosaurListRow):
    from app.schemas.dinosaur import DinosaurSummary
    from app.services.curated_image_service.versions import ORIGINAL_VERSION

    dino_type = row.dinosaur_type
    type_id = int(dino_type.id)
    return DinosaurSummary(
        id=int(row.occurrence_id or type_id),
        dinosaur_type_id=type_id,
        name=dino_type.name,
        wikipedia_title=dino_type.wikipedia_title,
        birth=dino_type.birth,
        death=dino_type.death,
        period=dino_type.period,
        diet_type=dino_type.diet_type,
        length=dino_type.length,
        mass=dino_type.mass,
        location=dino_type.location,
        short_description=dino_type.short_description,
        cladogram=dict(dino_type.cladogram or {}),
        main_image_url=resolve_dinosaur_card_image_url(
            dinosaur_name=dino_type.name,
            version=row.image_version or ORIGINAL_VERSION,
            fallback_url=dino_type.main_image_url,
        ),
        created_at=row.created_at,
        version=row.image_version if row.occurrence_id is not None else None,
    )
