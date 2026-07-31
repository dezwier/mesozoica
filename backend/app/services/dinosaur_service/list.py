"""Query helpers for dinosaur read APIs."""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from datetime import datetime
from typing import Literal

from sqlalchemy import case, func, or_
from sqlmodel import Session, col, func as sqlmodel_func, select

from app.core.exceptions import NotFoundError, ValidationError
from app.models.dinosaur import Dinosaur
from app.models.dinosaur_type import DinosaurType
from app.models.dinosaur_type_revision import DinosaurTypeRevision
from app.models.user_dinosaur import UserDinosaur, role_to_status
from app.services.curated_image_service.resolve import resolve_dinosaur_card_image_url
from app.services.dinosaur_image_service.sync import CURATED_MEDIA_PATH
from app.services.dinosaur_service.size_parse import (
    parse_length_m,
    parse_mass_kg,
    ranges_overlap,
)

SortOption = Literal["name", "random"]
ListMode = Literal["catalog", "inventory"]
_MAX_SEED_LEN = 64
MESOZOIC_YOUNGER_MA = 66.0
MESOZOIC_OLDER_MA = 252.0

# Catalog name sort: types with curated images first, then alphabetical.
_CATALOG_IMAGE_PRIORITY = case(
    (
        col(DinosaurType.main_image_url).is_not(None)
        & col(DinosaurType.main_image_url).contains(CURATED_MEDIA_PATH),
        0,
    ),
    else_=1,
)


@dataclass(frozen=True)
class DinosaurListRow:
    dinosaur_type: DinosaurType
    revision: DinosaurTypeRevision | None = None
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
    diet: list[str] | None = None,
    length_m_min: float | None = None,
    length_m_max: float | None = None,
    mass_kg_min: float | None = None,
    mass_kg_max: float | None = None,
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
            diet=diet,
            length_m_min=length_m_min,
            length_m_max=length_m_max,
            mass_kg_min=mass_kg_min,
            mass_kg_max=mass_kg_max,
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
        diet=diet,
        length_m_min=length_m_min,
        length_m_max=length_m_max,
        mass_kg_min=mass_kg_min,
        mass_kg_max=mass_kg_max,
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
    diet: list[str] | None,
    length_m_min: float | None,
    length_m_max: float | None,
    mass_kg_min: float | None,
    mass_kg_max: float | None,
) -> tuple[list[DinosaurListRow], int]:
    capped_limit = max(1, min(limit, 500))
    capped_offset = max(0, offset)
    normalized_q, younger, older, time_filter_active = _normalize_filters(
        q=q,
        ma_younger=ma_younger,
        ma_older=ma_older,
    )
    effective_time_filter = time_filter_active and normalized_q is None
    diets = _normalize_diets(diet)
    length_range = _normalize_size_range(length_m_min, length_m_max, label="length_m")
    mass_range = _normalize_size_range(mass_kg_min, mass_kg_max, label="mass_kg")
    size_filter_active = length_range is not None or mass_range is not None

    filtered = _filtered_catalog_select(
        normalized_q=normalized_q,
        ma_younger=younger,
        ma_older=older,
        time_filter_active=effective_time_filter,
        has_custom_image=has_custom_image,
        llm_enriched=llm_enriched,
        diets=diets,
    )

    from app.services.curated_image_service.versions import ORIGINAL_VERSION

    if size_filter_active:
        all_rows = list(session.exec(filtered).all())
        all_rows = [
            (dino_type, revision)
            for dino_type, revision in all_rows
            if _revision_matches_size(
                revision, length_range=length_range, mass_range=mass_range
            )
        ]
        total = len(all_rows)
        if sort == "random":
            normalized_seed = _require_seed(seed)
            all_rows.sort(
                key=lambda row: hashlib.md5(
                    f"{row[0].id}{normalized_seed}".encode()
                ).hexdigest()
            )
        else:
            all_rows.sort(
                key=lambda row: (
                    0
                    if (
                        row[0].main_image_url
                        and CURATED_MEDIA_PATH in row[0].main_image_url
                    )
                    else 1,
                    row[0].name or "",
                )
            )
        page = all_rows[capped_offset : capped_offset + capped_limit]
        return [
            DinosaurListRow(
                dinosaur_type=dino_type,
                revision=revision,
                image_version=ORIGINAL_VERSION,
            )
            for dino_type, revision in page
        ], total

    total = session.exec(
        select(sqlmodel_func.count()).select_from(filtered.subquery())
    ).one()

    if sort == "random":
        normalized_seed = _require_seed(seed)
        rows = _list_catalog_random(
            session,
            filtered=filtered,
            seed=normalized_seed,
            offset=capped_offset,
            limit=capped_limit,
        )
    else:
        rows = list(
            session.exec(
                filtered.order_by(_CATALOG_IMAGE_PRIORITY.asc(), DinosaurType.name)
                .offset(capped_offset)
                .limit(capped_limit)
            ).all()
        )

    return [
        DinosaurListRow(
            dinosaur_type=dino_type,
            revision=revision,
            image_version=ORIGINAL_VERSION,
        )
        for dino_type, revision in rows
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
    diet: list[str] | None,
    length_m_min: float | None,
    length_m_max: float | None,
    mass_kg_min: float | None,
    mass_kg_max: float | None,
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
    diets = _normalize_diets(diet)
    length_range = _normalize_size_range(length_m_min, length_m_max, label="length_m")
    mass_range = _normalize_size_range(mass_kg_min, mass_kg_max, label="mass_kg")
    size_filter_active = length_range is not None or mass_range is not None

    linked_dinosaurs = (
        select(col(UserDinosaur.dinosaur_id))
        .where(col(UserDinosaur.user_id) == viewer_user_id)
        .distinct()
    )
    # Prefer pinned occurrence revision; fall back to type current revision.
    stmt = (
        select(Dinosaur, DinosaurType, DinosaurTypeRevision)
        .join(DinosaurType, col(Dinosaur.dinosaur_type_id) == col(DinosaurType.id))
        .outerjoin(
            DinosaurTypeRevision,
            col(DinosaurTypeRevision.id)
            == func.coalesce(
                col(Dinosaur.dinosaur_type_revision_id),
                col(DinosaurType.current_revision_id),
            ),
        )
        .where(col(Dinosaur.id).in_(linked_dinosaurs))
    )
    if has_custom_image:
        stmt = stmt.where(
            col(DinosaurType.main_image_url).is_not(None),
            col(DinosaurType.main_image_url).contains(CURATED_MEDIA_PATH),
        )
    if llm_enriched is not None:
        stmt = stmt.where(col(DinosaurTypeRevision.llm_enriched).is_(llm_enriched))
    if diets:
        stmt = stmt.where(func.lower(DinosaurTypeRevision.diet_type).in_(diets))
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
            col(DinosaurTypeRevision.birth).is_not(None),
            col(DinosaurTypeRevision.death).is_not(None),
            col(DinosaurTypeRevision.death) <= older,
            col(DinosaurTypeRevision.birth) >= younger,
        )

    if size_filter_active:
        rows = list(session.exec(stmt).all())
        rows = [
            (occurrence, dino_type, revision)
            for occurrence, dino_type, revision in rows
            if _revision_matches_size(
                revision, length_range=length_range, mass_range=mass_range
            )
        ]
        total = len(rows)
        if sort == "random":
            normalized_seed = _require_seed(seed)
            rows.sort(
                key=lambda row: hashlib.md5(
                    f"{row[0].id}{row[1].id}{normalized_seed}".encode()
                ).hexdigest()
            )
        else:
            rows.sort(key=lambda row: (row[1].name or "", row[0].id))
        page = rows[capped_offset : capped_offset + capped_limit]
        return [
            DinosaurListRow(
                dinosaur_type=dino_type,
                revision=revision,
                occurrence_id=int(occurrence.id),
                created_at=occurrence.created_at,
                image_version=occurrence.version,
            )
            for occurrence, dino_type, revision in page
        ], total

    total = session.exec(
        select(sqlmodel_func.count()).select_from(stmt.subquery())
    ).one()

    if sort == "random":
        normalized_seed = _require_seed(seed)
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
            revision=revision,
            occurrence_id=int(occurrence.id),
            created_at=occurrence.created_at,
            image_version=occurrence.version,
        )
        for occurrence, dino_type, revision in rows
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


def _normalize_diets(diet: list[str] | None) -> list[str] | None:
    if not diet:
        return None
    cleaned = sorted(
        {
            value.strip().lower()
            for value in diet
            if value and value.strip()
        }
    )
    return cleaned or None


def _normalize_size_range(
    minimum: float | None,
    maximum: float | None,
    *,
    label: str,
) -> tuple[float, float] | None:
    if minimum is None and maximum is None:
        return None
    if minimum is None or maximum is None:
        raise ValidationError(f"{label}_min and {label}_max must both be provided")
    lo = float(minimum)
    hi = float(maximum)
    if lo > hi:
        raise ValidationError(f"{label}_min must be less than or equal to {label}_max")
    return lo, hi


def _revision_matches_size(
    revision: DinosaurTypeRevision | None,
    *,
    length_range: tuple[float, float] | None,
    mass_range: tuple[float, float] | None,
) -> bool:
    if revision is None:
        return False
    if length_range is not None:
        parsed = parse_length_m(revision.length)
        if parsed is None:
            return False
        if not ranges_overlap(parsed[0], parsed[1], length_range[0], length_range[1]):
            return False
    if mass_range is not None:
        parsed = parse_mass_kg(revision.mass)
        if parsed is None:
            return False
        if not ranges_overlap(parsed[0], parsed[1], mass_range[0], mass_range[1]):
            return False
    return True


def _require_seed(seed: str | None) -> str:
    normalized_seed = (seed or "").strip()
    if not normalized_seed:
        raise ValidationError("seed is required when sort=random")
    return normalized_seed[:_MAX_SEED_LEN]


def _filtered_catalog_select(
    *,
    normalized_q: str | None,
    ma_younger: float | None,
    ma_older: float | None,
    time_filter_active: bool,
    has_custom_image: bool,
    llm_enriched: bool | None,
    diets: list[str] | None,
):
    stmt = (
        select(DinosaurType, DinosaurTypeRevision)
        .outerjoin(
            DinosaurTypeRevision,
            col(DinosaurTypeRevision.id) == col(DinosaurType.current_revision_id),
        )
    )
    if has_custom_image:
        stmt = stmt.where(
            col(DinosaurType.main_image_url).is_not(None),
            col(DinosaurType.main_image_url).contains(CURATED_MEDIA_PATH),
        )
    if llm_enriched is not None:
        stmt = stmt.where(col(DinosaurTypeRevision.llm_enriched).is_(llm_enriched))
    if diets:
        stmt = stmt.where(func.lower(DinosaurTypeRevision.diet_type).in_(diets))
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
            col(DinosaurTypeRevision.birth).is_not(None),
            col(DinosaurTypeRevision.death).is_not(None),
            col(DinosaurTypeRevision.death) <= ma_older,
            col(DinosaurTypeRevision.birth) >= ma_younger,
        )
    return stmt


def _list_catalog_random(
    session: Session,
    *,
    filtered,
    seed: str,
    offset: int,
    limit: int,
) -> list[tuple[DinosaurType, DinosaurTypeRevision | None]]:
    dialect_name = session.get_bind().dialect.name
    if dialect_name == "postgresql":
        order = func.md5(func.concat(DinosaurType.id, seed))
        rows = session.exec(
            filtered.order_by(order).offset(offset).limit(limit)
        ).all()
        return list(rows)

    all_rows = session.exec(filtered).all()
    all_rows.sort(
        key=lambda row: hashlib.md5(f"{row[0].id}{seed}".encode()).hexdigest()
    )
    return all_rows[offset : offset + limit]


def get_dinosaur_by_id(session: Session, dinosaur_id: int) -> DinosaurType:
    """Fetch a catalog dinosaur type by id (article / detail routes)."""
    row = session.get(DinosaurType, dinosaur_id)
    if row is None:
        raise NotFoundError(f"DinosaurType {dinosaur_id} not found")
    return row


def get_dinosaur_with_revision(
    session: Session, dinosaur_id: int
) -> tuple[DinosaurType, DinosaurTypeRevision | None]:
    """Fetch catalog type plus its current content revision."""
    dino_type = get_dinosaur_by_id(session, dinosaur_id)
    revision = None
    if dino_type.current_revision_id is not None:
        revision = session.get(DinosaurTypeRevision, dino_type.current_revision_id)
    return dino_type, revision


def dinosaur_to_summary(
    row: DinosaurListRow,
    *,
    viewer_status: str | None = None,
    owned_occurrences: list | None = None,
):
    from app.schemas.dinosaur import DinosaurSummary, OwnedOccurrenceThumb
    from app.services.curated_image_service.versions import ORIGINAL_VERSION

    dino_type = row.dinosaur_type
    revision = row.revision
    type_id = int(dino_type.id)
    thumbs: list[OwnedOccurrenceThumb] = []
    if owned_occurrences:
        thumbs = list(owned_occurrences)
    return DinosaurSummary(
        id=int(row.occurrence_id or type_id),
        dinosaur_type_id=type_id,
        name=dino_type.name,
        wikipedia_title=dino_type.wikipedia_title,
        birth=revision.birth if revision else None,
        death=revision.death if revision else None,
        period=revision.period if revision else None,
        diet_type=revision.diet_type if revision else None,
        length=revision.length if revision else None,
        mass=revision.mass if revision else None,
        location=revision.location if revision else None,
        short_description=revision.short_description if revision else None,
        cladogram=dict(revision.cladogram or {}) if revision else {},
        main_image_url=resolve_dinosaur_card_image_url(
            dinosaur_name=dino_type.name,
            version=row.image_version or ORIGINAL_VERSION,
            fallback_url=dino_type.main_image_url,
        ),
        insert_date=dino_type.insert_date,
        article_date=revision.article_date if revision else None,
        created_at=row.created_at,
        version=row.image_version if row.occurrence_id is not None else None,
        status=viewer_status,
        owned_occurrences=thumbs,
    )


def owned_occurrences_for_types(
    session: Session,
    *,
    type_ids: list[int],
    viewer_user_id: int | None,
) -> dict[int, list]:
    """Owned occurrence thumbs keyed by dinosaur type id for the viewer."""
    from app.schemas.dinosaur import OwnedOccurrenceThumb
    from app.services.curated_image_service.versions import ORIGINAL_VERSION

    if viewer_user_id is None or not type_ids:
        return {}

    # Distinct occurrences the viewer has any user_dinosaur link for.
    rows = session.exec(
        select(Dinosaur, DinosaurType)
        .join(DinosaurType, col(DinosaurType.id) == col(Dinosaur.dinosaur_type_id))
        .join(UserDinosaur, col(UserDinosaur.dinosaur_id) == col(Dinosaur.id))
        .where(
            col(UserDinosaur.user_id) == viewer_user_id,
            col(Dinosaur.dinosaur_type_id).in_(type_ids),
        )
        .order_by(col(Dinosaur.created_at).asc(), col(Dinosaur.id).asc())
    ).all()

    result: dict[int, list[OwnedOccurrenceThumb]] = {tid: [] for tid in type_ids}
    seen_occurrence_ids: set[int] = set()
    for occurrence, dino_type in rows:
        occ_id = int(occurrence.id)
        if occ_id in seen_occurrence_ids:
            continue
        seen_occurrence_ids.add(occ_id)
        type_id = int(occurrence.dinosaur_type_id)
        version = (occurrence.version or ORIGINAL_VERSION).strip() or ORIGINAL_VERSION
        result.setdefault(type_id, []).append(
            OwnedOccurrenceThumb(
                id=occ_id,
                version=version,
                main_image_url=resolve_dinosaur_card_image_url(
                    dinosaur_name=dino_type.name,
                    version=version,
                    fallback_url=dino_type.main_image_url,
                ),
                created_at=occurrence.created_at,
            )
        )
    return result


def viewer_statuses_for_types(
    session: Session,
    *,
    type_ids: list[int],
    viewer_user_id: int | None,
) -> dict[int, str]:
    """Latest user_dinosaur status per dinosaur type for the viewer."""
    if viewer_user_id is None or not type_ids:
        return {}
    links = session.exec(
        select(UserDinosaur, Dinosaur.dinosaur_type_id)
        .join(Dinosaur, col(Dinosaur.id) == col(UserDinosaur.dinosaur_id))
        .where(
            col(UserDinosaur.user_id) == viewer_user_id,
            col(Dinosaur.dinosaur_type_id).in_(type_ids),
        )
        .order_by(col(UserDinosaur.timestamp).desc())
    ).all()
    result: dict[int, str] = {}
    for link, type_id in links:
        tid = int(type_id)
        if tid not in result:
            result[tid] = role_to_status(link.role)
    return result


def viewer_status_for_occurrence(
    session: Session,
    *,
    occurrence_id: int,
    viewer_user_id: int | None,
) -> str | None:
    if viewer_user_id is None:
        return None
    link = session.exec(
        select(UserDinosaur)
        .where(
            col(UserDinosaur.user_id) == viewer_user_id,
            col(UserDinosaur.dinosaur_id) == occurrence_id,
        )
        .order_by(col(UserDinosaur.timestamp).desc())
    ).first()
    if link is None:
        return None
    return role_to_status(link.role)
