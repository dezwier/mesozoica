"""Query helpers for dinosaur read APIs."""

from __future__ import annotations

import hashlib
from typing import Literal

from sqlalchemy import func, or_
from sqlmodel import Session, col, func as sqlmodel_func, select

from app.core.exceptions import NotFoundError, ValidationError
from app.models.dinosaur import Dinosaur
from app.services.dinosaur_image_service.sync import CURATED_MEDIA_PATH

SortOption = Literal["name", "random"]
_MAX_SEED_LEN = 64
MESOZOIC_YOUNGER_MA = 66.0
MESOZOIC_OLDER_MA = 252.0


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
) -> tuple[list[Dinosaur], int]:
    """Return paginated dinosaur rows ordered by name or seed-stable random."""
    capped_limit = max(1, min(limit, 500))
    capped_offset = max(0, offset)
    normalized_q, younger, older, time_filter_active = _normalize_filters(
        q=q,
        ma_younger=ma_younger,
        ma_older=ma_older,
    )
    # Name search scans the full catalog; time range applies only when browsing.
    effective_time_filter = time_filter_active and normalized_q is None
    filtered = _filtered_select(
        normalized_q=normalized_q,
        ma_younger=younger,
        ma_older=older,
        time_filter_active=effective_time_filter,
        has_custom_image=has_custom_image,
    )

    total = session.exec(
        select(sqlmodel_func.count()).select_from(filtered.subquery())
    ).one()

    if sort == "random":
        normalized_seed = (seed or "").strip()
        if not normalized_seed:
            raise ValidationError("seed is required when sort=random")
        normalized_seed = normalized_seed[:_MAX_SEED_LEN]
        rows = _list_dinosaurs_random(
            session,
            filtered=filtered,
            seed=normalized_seed,
            offset=capped_offset,
            limit=capped_limit,
        )
        return rows, int(total)

    rows = session.exec(
        filtered.order_by(Dinosaur.name).offset(capped_offset).limit(capped_limit)
    ).all()
    return list(rows), int(total)


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
):
    stmt = select(Dinosaur)
    if has_custom_image:
        stmt = stmt.where(
            col(Dinosaur.main_image_url).is_not(None),
            col(Dinosaur.main_image_url).contains(CURATED_MEDIA_PATH),
        )
    if normalized_q is not None:
        pattern = f"%{normalized_q}%"
        stmt = stmt.where(
            or_(
                col(Dinosaur.name).ilike(pattern),
                col(Dinosaur.wikipedia_title).ilike(pattern),
            )
        )
    if time_filter_active:
        assert ma_younger is not None and ma_older is not None
        stmt = stmt.where(
            col(Dinosaur.birth).is_not(None),
            col(Dinosaur.death).is_not(None),
            col(Dinosaur.death) <= ma_older,
            col(Dinosaur.birth) >= ma_younger,
        )
    return stmt


def _list_dinosaurs_random(
    session: Session,
    *,
    filtered,
    seed: str,
    offset: int,
    limit: int,
) -> list[Dinosaur]:
    dialect_name = session.get_bind().dialect.name
    if dialect_name == "postgresql":
        order = func.md5(func.concat(Dinosaur.id, seed))
        rows = session.exec(
            filtered.order_by(order).offset(offset).limit(limit)
        ).all()
        return list(rows)

    all_rows = session.exec(filtered).all()
    all_rows.sort(
        key=lambda row: hashlib.md5(f"{row.id}{seed}".encode()).hexdigest()
    )
    return all_rows[offset : offset + limit]


def get_dinosaur_by_id(session: Session, dinosaur_id: int) -> Dinosaur:
    row = session.get(Dinosaur, dinosaur_id)
    if row is None:
        raise NotFoundError(f"Dinosaur {dinosaur_id} not found")
    return row
