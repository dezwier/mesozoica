"""Pick a stand-in site type when a site has no rock type."""

from __future__ import annotations

from collections import defaultdict

from sqlmodel import Session, col, select

from app.models.site import Site
from app.models.site_type import SiteType
from app.services.site_service.rules import period_for_ages


def load_site_types_by_period(session: Session) -> dict[str, list[SiteType]]:
    rows = session.exec(select(SiteType).order_by(col(SiteType.id))).all()
    grouped: dict[str, list[SiteType]] = defaultdict(list)
    for row in rows:
        grouped[row.period].append(row)
    return dict(grouped)


def period_to_type_ids(types_by_period: dict[str, list[SiteType]]) -> dict[str, list[int]]:
    mapping: dict[str, list[int]] = {}
    for period, rows in types_by_period.items():
        ids = [row.id for row in rows if row.id is not None]
        if ids:
            mapping[period] = ids
    return mapping


def pick_site_type_for_period(
    *,
    site_id: int,
    period: str,
    types_by_period: dict[str, list[SiteType]],
) -> SiteType | None:
    pool = types_by_period.get(period, [])
    with_image = [row for row in pool if row.main_image_url]
    candidates = with_image or pool
    if not candidates:
        return None
    return candidates[site_id % len(candidates)]


def _rock_type_missing(site: Site) -> bool:
    return not (site.rock_type or "").strip()


def fallback_site_type(
    site: Site,
    site_type: SiteType | None,
    types_by_period: dict[str, list[SiteType]],
) -> SiteType | None:
    if site_type is not None or not _rock_type_missing(site):
        return None

    period = period_for_ages(site.min_age_ma, site.max_age_ma)
    if not period:
        return None

    return pick_site_type_for_period(
        site_id=site.site_id,
        period=period,
        types_by_period=types_by_period,
    )


def effective_site_type(
    site: Site,
    site_type: SiteType | None,
    types_by_period: dict[str, list[SiteType]],
) -> SiteType | None:
    return site_type or fallback_site_type(site, site_type, types_by_period)


def pick_site_type_id_for_period(
    *,
    site_id: int,
    period: str,
    period_to_type_ids: dict[str, list[int]],
) -> int | None:
    candidates = period_to_type_ids.get(period, [])
    if not candidates:
        return None
    return candidates[site_id % len(candidates)]
