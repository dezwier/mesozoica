"""Map joined site rows to API schemas."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal

from sqlmodel import Session, col, select

from app.models.site import Site
from app.models.site_type import SiteType
from app.models.user_site import (
    USER_SITE_ROLE_DISCOVERER,
    USER_SITE_ROLE_SURVEYOR,
    UserSite,
)
from app.schemas.site import SiteSummary
from app.services.curated_image_service.resolve import resolve_site_type_card_image_url
from app.services.site_service.site_type_fallback import effective_site_type


@dataclass(frozen=True)
class SiteRow:
    site: Site
    site_type: SiteType | None
    status: str | None = None
    viewer_has_surveyed: bool | None = None
    discovered_at: datetime | None = None
    discovering_mission_id: int | None = None


def _site_card_image_url(site: Site, site_type: SiteType | None) -> str | None:
    if site_type is None:
        return None
    from app.services.curated_image_service.versions import ORIGINAL_VERSION

    return resolve_site_type_card_image_url(
        period=site_type.period,
        rock_type=site_type.rock_type,
        version=site.version or ORIGINAL_VERSION,
        fallback_url=site_type.main_image_url,
    )


def site_row_to_summary(
    row: SiteRow,
    *,
    types_by_period: dict[str, list[SiteType]] | None = None,
) -> SiteSummary:
    site = row.site
    site_type = (
        effective_site_type(site, row.site_type, types_by_period)
        if types_by_period is not None
        else row.site_type
    )
    return SiteSummary(
        site_id=site.site_id,
        latitude=_decimal_to_float(site.latitude),
        longitude=_decimal_to_float(site.longitude),
        country_code=site.country_code,
        state=site.state,
        rock_type=site.rock_type,
        formation=site.formation,
        min_age_ma=_decimal_to_float(site.min_age_ma),
        max_age_ma=_decimal_to_float(site.max_age_ma),
        site_type_id=site.site_type_id,
        site_type_period=(
            site_type.period
            if site_type is not None
            else (site.period if site.period else None)
        ),
        site_type_rock_type=(
            site_type.rock_type
            if site_type is not None
            else (site.rock_type if site.rock_type else None)
        ),
        main_image_url=_site_card_image_url(site, site_type),
        data_source=site.data_source,
        how_discovered=site.how_discovered,
        status=row.status,
        viewer_has_surveyed=row.viewer_has_surveyed,
        discovered_at=row.discovered_at,
        discovering_mission_id=row.discovering_mission_id,
        odd_dino_count=site.odd_dino_count,
        odd_fossil_count=site.odd_fossil_count,
        odd_completeness=site.odd_completeness,
        odd_quality=site.odd_quality,
        odd_depth=site.odd_depth,
    )


def enrich_site_rows_for_viewer(
    session: Session,
    rows: list[SiteRow],
    *,
    viewer_user_id: int,
) -> list[SiteRow]:
    """Attach viewer discoverer timestamp / mission id and survey flag (batch)."""
    if not rows:
        return rows
    site_ids = [int(row.site.site_id) for row in rows if row.site.site_id is not None]
    if not site_ids:
        return rows

    link_rows = session.exec(
        select(UserSite).where(
            col(UserSite.user_id) == viewer_user_id,
            col(UserSite.site_id).in_(site_ids),
            col(UserSite.role).in_(
                (USER_SITE_ROLE_DISCOVERER, USER_SITE_ROLE_SURVEYOR)
            ),
        )
    ).all()

    discover_by_site: dict[int, UserSite] = {}
    surveyed_ids: set[int] = set()
    for link in link_rows:
        site_id = int(link.site_id)
        if link.role == USER_SITE_ROLE_DISCOVERER:
            discover_by_site[site_id] = link
        elif link.role == USER_SITE_ROLE_SURVEYOR:
            surveyed_ids.add(site_id)

    enriched: list[SiteRow] = []
    for row in rows:
        site_id = int(row.site.site_id)
        discover = discover_by_site.get(site_id)
        surveyed = row.viewer_has_surveyed
        if surveyed is None:
            surveyed = site_id in surveyed_ids
        enriched.append(
            SiteRow(
                site=row.site,
                site_type=row.site_type,
                status=row.status,
                viewer_has_surveyed=surveyed,
                discovered_at=discover.timestamp if discover is not None else None,
                discovering_mission_id=(
                    int(discover.source_mission_id)
                    if discover is not None and discover.source_mission_id is not None
                    else None
                ),
            )
        )
    return enriched


def _decimal_to_float(value: Decimal | float | int | None) -> float | None:
    if value is None:
        return None
    return float(value)
