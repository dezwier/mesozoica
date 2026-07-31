"""List site types for the catalog album drawer."""

from __future__ import annotations

from sqlalchemy import case
from sqlmodel import Session, col, func as sqlmodel_func, select

from app.models.site import Site
from app.models.site_type import SiteType
from app.models.user_site import UserSite
from app.schemas.site import OwnedOccurrenceThumb, SiteTypeSummary
from app.services.curated_image_service.resolve import resolve_site_type_card_image_url
from app.services.curated_image_service.versions import ORIGINAL_VERSION

# Geological order: oldest → youngest.
_PERIOD_ORDER = case(
    (col(SiteType.period) == "triassic", 0),
    (col(SiteType.period) == "jurassic", 1),
    (col(SiteType.period) == "cretaceous", 2),
    else_=3,
)


def list_site_types(
    session: Session,
    *,
    limit: int = 200,
    offset: int = 0,
) -> tuple[list[SiteType], int]:
    """Return paginated site types ordered by period (geo), then rock_type."""
    capped_limit = max(1, min(limit, 500))
    capped_offset = max(0, offset)
    total = session.exec(select(sqlmodel_func.count()).select_from(SiteType)).one()
    rows = session.exec(
        select(SiteType)
        .order_by(_PERIOD_ORDER.asc(), col(SiteType.rock_type).asc())
        .offset(capped_offset)
        .limit(capped_limit)
    ).all()
    return list(rows), int(total)


def site_type_to_summary(
    row: SiteType,
    *,
    owned_occurrences: list[OwnedOccurrenceThumb] | None = None,
) -> SiteTypeSummary:
    """Build a catalog album summary for one site type."""
    type_id = int(row.id) if row.id is not None else 0
    thumbs = list(owned_occurrences or [])
    return SiteTypeSummary(
        id=type_id,
        period=row.period,
        rock_type=row.rock_type,
        main_image_url=resolve_site_type_card_image_url(
            period=row.period,
            rock_type=row.rock_type,
            version=ORIGINAL_VERSION,
            fallback_url=row.main_image_url,
        ),
        owned_occurrences=thumbs,
    )


def owned_occurrences_for_site_types(
    session: Session,
    *,
    type_ids: list[int],
    viewer_user_id: int | None,
) -> dict[int, list[OwnedOccurrenceThumb]]:
    """Owned site occurrence thumbs keyed by site type id for the viewer."""
    if viewer_user_id is None or not type_ids:
        return {}

    rows = session.exec(
        select(Site, SiteType)
        .join(SiteType, col(SiteType.id) == col(Site.site_type_id))
        .join(UserSite, col(UserSite.site_id) == col(Site.site_id))
        .where(
            col(UserSite.user_id) == viewer_user_id,
            col(Site.site_type_id).in_(type_ids),
        )
        .order_by(col(Site.created_at).asc().nulls_last(), col(Site.site_id).asc())
    ).all()

    result: dict[int, list[OwnedOccurrenceThumb]] = {tid: [] for tid in type_ids}
    seen_site_ids: set[int] = set()
    for site, site_type in rows:
        site_id = int(site.site_id)
        if site_id in seen_site_ids:
            continue
        seen_site_ids.add(site_id)
        type_id = int(site.site_type_id) if site.site_type_id is not None else 0
        version = (site.version or ORIGINAL_VERSION).strip() or ORIGINAL_VERSION
        result.setdefault(type_id, []).append(
            OwnedOccurrenceThumb(
                id=site_id,
                version=version,
                main_image_url=resolve_site_type_card_image_url(
                    period=site_type.period,
                    rock_type=site_type.rock_type,
                    version=version,
                    fallback_url=site_type.main_image_url,
                ),
                created_at=site.created_at,
            )
        )
    return result
