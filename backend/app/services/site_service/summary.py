"""Map joined site rows to API schemas."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal

from sqlmodel import Session, col, select

from app.models.data_source import DATA_SOURCE_FIELD
from app.models.site import Site
from app.models.site_type import SiteType
from app.models.user_site import (
    USER_SITE_ROLE_DISCOVERER,
    USER_SITE_ROLE_DOCUMENTER,
    USER_SITE_ROLE_IDENTIFIER,
    UserSite,
)
from app.schemas.site import SiteDimensionBand, SiteSummary
from app.services.curated_image_service.resolve import resolve_site_type_card_image_url
from app.services.site_service.dimension_display import (
    SiteDimensionKey,
    build_site_dimension_bands,
)
from app.services.site_service.rules import PERIOD_AGE_BOUNDS_MA
from app.services.site_service.site_type_fallback import effective_site_type


@dataclass(frozen=True)
class SiteRow:
    site: Site
    site_type: SiteType | None
    status: str | None = None
    viewer_has_documented: bool | None = None
    viewer_has_identified: bool | None = None
    discovered_at: datetime | None = None
    discovering_session_id: int | None = None
    viewer_was_first_discovery: bool | None = None
    documented_at: datetime | None = None
    viewer_was_first_documentation: bool | None = None
    explored_distance_m: float | None = None
    documented: bool | None = None


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


def _band_schema(band) -> SiteDimensionBand | None:
    if band is None:
        return None
    return SiteDimensionBand(
        range_start=band.range_start,
        range_end=band.range_end,
        blur_sigma=band.blur_sigma,
        effective_accuracy=band.effective_accuracy,
    )


def _period_age_bounds(
    period: str | None,
) -> tuple[float | None, float | None]:
    if not period:
        return None, None
    bounds = PERIOD_AGE_BOUNDS_MA.get(period.strip().lower())
    if bounds is None:
        return None, None
    return bounds[0], bounds[1]


def site_row_to_summary(
    row: SiteRow,
    *,
    types_by_period: dict[str, list[SiteType]] | None = None,
    include_exact_odds: bool = False,
    stewardship_skill_level: int = 1,
) -> SiteSummary:
    from app.services.curated_image_service.versions import ORIGINAL_VERSION

    site = row.site
    site_type = (
        effective_site_type(site, row.site_type, types_by_period)
        if types_by_period is not None
        else row.site_type
    )
    is_field = site.data_source == DATA_SOURCE_FIELD
    # Archive sites are always "identified". Field sites need the identifier role
    # (or both quiz flags on the discoverer row) for the viewing user.
    viewer_identified = (
        True
        if not is_field
        else bool(row.viewer_has_identified)
    )
    # Only redact after the viewer discovered the site but before identification.
    viewer_discovered = row.discovered_at is not None
    redact = is_field and viewer_discovered and not viewer_identified

    bands = (
        {}
        if redact
        else build_site_dimension_bands(
            site_id=int(site.site_id),
            odd_dino_count=site.odd_dino_count,
            odd_fossil_count=site.odd_fossil_count,
            odd_completeness=site.odd_completeness,
            odd_quality=site.odd_quality,
            odd_depth=site.odd_depth,
            skill_level=stewardship_skill_level,
            explored_distance_m=float(row.explored_distance_m or 0.0),
        )
    )

    period = (
        site_type.period
        if site_type is not None
        else (site.period if site.period else None)
    )
    rock = (
        site_type.rock_type
        if site_type is not None
        else (site.rock_type if site.rock_type else None)
    )

    min_age = _decimal_to_float(site.min_age_ma)
    max_age = _decimal_to_float(site.max_age_ma)
    if not redact and is_field and (min_age is None or max_age is None) and period:
        period_min, period_max = _period_age_bounds(period)
        if min_age is None:
            min_age = period_min
        if max_age is None:
            max_age = period_max

    return SiteSummary(
        site_id=site.site_id,
        latitude=_decimal_to_float(site.latitude),
        longitude=_decimal_to_float(site.longitude),
        country_code=site.country_code,
        state=site.state,
        rock_type=None if redact else site.rock_type,
        formation=site.formation,
        min_age_ma=None if redact else min_age,
        max_age_ma=None if redact else max_age,
        site_type_id=site.site_type_id,
        site_type_period=None if redact else period,
        site_type_rock_type=None if redact else rock,
        main_image_url=_site_card_image_url(site, site_type),
        data_source=site.data_source,
        how_discovered=site.how_discovered,
        status=row.status,
        discovered_at=row.discovered_at,
        discovering_session_id=row.discovering_session_id,
        viewer_was_first_discovery=row.viewer_was_first_discovery,
        documented_at=row.documented_at,
        viewer_was_first_documentation=row.viewer_was_first_documentation,
        odd_dino_count=(
            None if redact or not include_exact_odds else site.odd_dino_count
        ),
        odd_fossil_count=(
            None if redact or not include_exact_odds else site.odd_fossil_count
        ),
        odd_completeness=(
            None if redact or not include_exact_odds else site.odd_completeness
        ),
        odd_quality=(
            None if redact or not include_exact_odds else site.odd_quality
        ),
        odd_depth=None if redact or not include_exact_odds else site.odd_depth,
        odd_dino_band=(
            None if redact else _band_schema(bands.get(SiteDimensionKey.DINO))
        ),
        odd_fossil_band=(
            None if redact else _band_schema(bands.get(SiteDimensionKey.FOSSIL))
        ),
        odd_completeness_band=(
            None
            if redact
            else _band_schema(bands.get(SiteDimensionKey.COMPLETENESS))
        ),
        odd_quality_band=(
            None if redact else _band_schema(bands.get(SiteDimensionKey.QUALITY))
        ),
        odd_depth_band=(
            None if redact else _band_schema(bands.get(SiteDimensionKey.DEPTH))
        ),
        explored_distance_m=row.explored_distance_m,
        documented=row.documented,
        viewer_has_documented=row.viewer_has_documented,
        viewer_has_identified=(
            True
            if not is_field
            else (True if viewer_identified else False if viewer_discovered else None)
        ),
        version=site.version or ORIGINAL_VERSION,
    )


def enrich_site_rows_for_viewer(
    session: Session,
    rows: list[SiteRow],
    *,
    viewer_user_id: int,
) -> list[SiteRow]:
    """Attach viewer discoverer / documenter / identifier flags (batch)."""
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
                (
                    USER_SITE_ROLE_DISCOVERER,
                    USER_SITE_ROLE_DOCUMENTER,
                    USER_SITE_ROLE_IDENTIFIER,
                )
            ),
        )
    ).all()

    discover_by_site: dict[int, UserSite] = {}
    document_by_site: dict[int, UserSite] = {}
    identified_sites: set[int] = set()
    for link in link_rows:
        site_id = int(link.site_id)
        if link.role == USER_SITE_ROLE_DISCOVERER:
            discover_by_site[site_id] = link
        elif link.role == USER_SITE_ROLE_DOCUMENTER:
            document_by_site[site_id] = link
        elif link.role == USER_SITE_ROLE_IDENTIFIER:
            identified_sites.add(site_id)

    enriched: list[SiteRow] = []
    for row in rows:
        site_id = int(row.site.site_id)
        discover = discover_by_site.get(site_id)
        document = document_by_site.get(site_id)
        has_documented = row.viewer_has_documented
        if has_documented is None:
            has_documented = document is not None
        discoverer_documented = (
            bool(discover.documented) if discover is not None else None
        )
        # Identifier role, or both quiz steps done on discoverer row.
        has_identified = site_id in identified_sites
        if not has_identified and discover is not None:
            has_identified = bool(
                discover.period_identified and discover.rock_identified
            )
        enriched.append(
            SiteRow(
                site=row.site,
                site_type=row.site_type,
                status=row.status,
                viewer_has_documented=has_documented,
                viewer_has_identified=has_identified,
                discovered_at=discover.timestamp if discover is not None else None,
                discovering_session_id=(
                    int(discover.source_session_id)
                    if discover is not None and discover.source_session_id is not None
                    else None
                ),
                viewer_was_first_discovery=(
                    bool(discover.was_first) if discover is not None else None
                ),
                documented_at=(
                    document.timestamp if document is not None else None
                ),
                viewer_was_first_documentation=(
                    bool(document.was_first) if document is not None else None
                ),
                explored_distance_m=(
                    float(discover.explored_distance_m or 0.0)
                    if discover is not None
                    else None
                ),
                documented=(
                    True
                    if has_documented
                    else discoverer_documented
                ),
            )
        )
    return enriched


def _decimal_to_float(value: Decimal | float | int | None) -> float | None:
    if value is None:
        return None
    return float(value)
